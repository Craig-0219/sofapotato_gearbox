-- ═══════════════════════════════════════════════════════════════
-- client/core/rpm_engine.lua
-- RPM 模擬引擎（ATMT/MT 專用）
--
-- 職責：
--   - 根據車速 + 檔位 + 油門計算目標 RPM
--   - 平滑 RPM（lerp）
--   - 每幀呼叫 GB.Native.SyncRpm
--   - 渦輪遲滯模擬
--
-- 不負責：AT 模式（AT 直接讀 native，不計算）
-- 不負責：換檔決策
-- ═══════════════════════════════════════════════════════════════

GB = GB or {}
GB.RPM = {}

-- ─────────────────────────────────────────────────────────────
-- 工具
-- ─────────────────────────────────────────────────────────────
local function Lerp(a, b, t)
    return a + (b - a) * math.min(1.0, math.max(0.0, t))
end

-- ─────────────────────────────────────────────────────────────
-- GB.RPM.CalcSpeedRpm(gear, speedMps, cfg)
-- 依車速 + 齒比反推理論轉速
-- 公式：speedRpm = (speedMps * gearRatio) / (topSpeedMps * topRatio) * REDLINE
-- ─────────────────────────────────────────────────────────────
function GB.RPM.CalcSpeedRpm(gear, speedMps, cfg)
    if not cfg or not cfg.gearRatios then return GearboxConst.Rpm.IDLE end

    local cache = GB.State.perGearCache
    if not cache or not cache[gear] then return GearboxConst.Rpm.IDLE end

    local topSpeedMps = cache[gear].topSpeedMps
    if not topSpeedMps or topSpeedMps <= 0 then return GearboxConst.Rpm.IDLE end

    -- speedRpm: 車速對應的 RPM（0~REDLINE 範圍）
    local speedRpm = (speedMps / topSpeedMps) * GearboxConst.Rpm.REDLINE
    return math.clamp(speedRpm, GearboxConst.Rpm.IDLE, 0.98)
end

-- ─────────────────────────────────────────────────────────────
-- GB.RPM.CalcThrottleFloor(throttle, cfg, isMT)
-- 計算油門基準 RPM（離合切斷時的自由轉速）
-- ─────────────────────────────────────────────────────────────
function GB.RPM.CalcThrottleFloor(throttle, cfg, isMT)
    local hasTurbo    = cfg and cfg.turbo == true
    local turboFactor = hasTurbo and (GB.State.turboBoost or 0.0) or 1.0
    local effectiveThr = throttle * (0.20 + turboFactor * 0.80)

    -- [FIX] 舊版 ATMT 使用 0.30 倍率（最高 0.42 RPM），理由是「避免 UpdateAT 誤判升檔」。
    -- 但 GB.ATMT.Tick 現在是空函式，根本沒有自動升檔邏輯。
    -- 限制 ATMT 的 RPM 上限會直接削弱 GTA 的驅動力信號，導致高檔低速時無法加速。
    -- 改為與 MT 相同的完整油門範圍。
    if isMT then
        -- MT：全油門時 RPM 接近紅線（讓 GTA 施加最大驅動力）
        return GearboxConst.Rpm.IDLE + effectiveThr * (GearboxConst.Rpm.REDLINE - GearboxConst.Rpm.IDLE)
    else
        -- ATMT：同 MT，使用完整油門範圍（GB.ATMT.Tick 為空，無自動升檔風險）
        return GearboxConst.Rpm.IDLE + effectiveThr * (GearboxConst.Rpm.REDLINE - GearboxConst.Rpm.IDLE)
    end
end

-- ─────────────────────────────────────────────────────────────
-- GB.RPM.Tick(dt)
-- 每幀更新 RPM 狀態並同步到 GTA
-- 只在 ATMT/MT 模式呼叫
-- ─────────────────────────────────────────────────────────────
function GB.RPM.Tick(dt)
    local state = GB.State
    local cfg   = state.cfg
    if not cfg then return end

    -- AT 模式：直接讀 native，不計算不寫回
    if state:IsATMode() then
        state.rpm       = GetVehicleCurrentRpm(state.vehicle)
        state.targetRpm = state.rpm
        return
    end

    -- ── 目標轉速計算 ──────────────────────────────────────
    if not state.engineOn then
        state.targetRpm = 0.0

    elseif state:ClutchDisengaged() then
        -- 離合器切斷（含空檔）：自由轉速跟隨油門
        local freeTarget = state.throttleInput > 0.05
            and (GearboxConst.Rpm.IDLE + state.throttleInput * 0.86)
            or  GearboxConst.Rpm.IDLE
        state.targetRpm = Lerp(state.targetRpm, freeTarget, 2.5 * dt)

    else
        -- 在檔 + 離合接合：依車速反推
        local gear     = state.currentGear
        local isMT     = state:IsMTMode()
        local speedRpm = GB.RPM.CalcSpeedRpm(gear, state.vehicleSpeed, cfg)
        local throttleFloor = GB.RPM.CalcThrottleFloor(state.throttleInput, cfg, isMT)

        local rawTarget = math.max(speedRpm, throttleFloor)

        -- 換檔期間快速 lerp（升檔落轉 / 降檔補轉效果）
        local targetRate = state.isShifting
            and ((cfg.revDropRate or 0.28) * 32.0)
            or  10.0
        state.targetRpm = Lerp(state.targetRpm, rawTarget, targetRate * dt)
    end

    -- ── 渦輪建壓 ─────────────────────────────────────────
    if cfg.turbo == true then
        GB.RPM.UpdateTurbo(state.isShifting, state.throttleInput, dt)
    end

    -- ── RPM 平滑跟隨目標 ─────────────────────────────────
    local turboLerpFactor = (cfg.turbo == true)
        and (0.30 + (state.turboBoost or 0.0) * 0.70)
        or  1.0
    local lerpRate = state.isShifting
        and ((cfg.revDropRate or 0.28) * 32.0)
        or  (4.0 * turboLerpFactor)
    state.rpm = Lerp(state.rpm, state.targetRpm, lerpRate * dt)
    state.rpm = math.clamp(state.rpm, 0.0, 1.0)

    -- ── 防熄火輔助（轉速極低時短暫補 RPM）───────────────
    if state.antiStall and state.engineOn then
        local stallRpm = (cfg.stallRpm or GearboxConst.Rpm.STALL)
        if state.rpm < stallRpm + 0.03 then
            state.rpm = math.min(GearboxConst.Rpm.IDLE + 0.02, state.rpm + 0.02)
        end
    end

    -- ── 寫回 GTA ─────────────────────────────────────────
    GB.Native.SyncRpm(state.vehicle, state.rpm)
end

-- ─────────────────────────────────────────────────────────────
-- GB.RPM.UpdateTurbo(isShifting, throttle, dt)
-- 渦輪遲滯模擬
-- ─────────────────────────────────────────────────────────────
function GB.RPM.UpdateTurbo(isShifting, throttle, dt)
    local state = GB.State
    if isShifting or throttle < 0.10 then
        state.turboBoost = Lerp(state.turboBoost, 0.0,
            (Config.Turbo and Config.Turbo.dropRate or 3.0) * dt)
    else
        state.turboBoost = Lerp(state.turboBoost, throttle,
            (Config.Turbo and Config.Turbo.spoolRate or 0.8) * dt)
    end
    state.turboBoost = math.clamp(state.turboBoost, 0.0, 1.0)
end

-- ─────────────────────────────────────────────────────────────
-- GB.RPM.DoRevMatch(oldGear, newGear, cfg)
-- 降檔補油：預先拉高 RPM 到新檔接合後的合理值
-- ─────────────────────────────────────────────────────────────
function GB.RPM.DoRevMatch(oldGear, newGear, cfg)
    if not GB.State.revMatch then return end
    if newGear >= oldGear then return end  -- 只在降檔

    local ratios   = cfg and cfg.gearRatios
    if not ratios then return end
    local oldRatio = ratios[oldGear] or 1.0
    local newRatio = ratios[newGear] or 1.0

    -- 預拉到新檔轉速（×0.90 避免太突兀）
    local matchRpm = math.min(GB.State.rpm * (newRatio / oldRatio) * 0.90, 0.92)
    GB.Native.SetRpm(GB.State.vehicle, matchRpm)
    GB.State.rpm       = matchRpm
    GB.State.targetRpm = matchRpm
end
