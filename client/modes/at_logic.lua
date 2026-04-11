-- ═══════════════════════════════════════════════════════════════
-- client/modes/at_logic.lua
-- AT 自動換檔決策
--
-- 職責：
--   - 讀取 RPM / 油門，決定何時升/降檔
--   - 冷卻期間防止 GTA 自行換檔（SyncATHighGear）
--   - 同步 nativeGear 到 state
--
-- 不負責：執行換檔（呼叫 GB.Core.ExecuteShift）
-- ═══════════════════════════════════════════════════════════════

GB = GB or {}
GB.AT = {}

-- ─────────────────────────────────────────────────────────────
-- GB.AT.Tick(dt)
-- 每幀由主循環在 AT 模式下呼叫
-- ─────────────────────────────────────────────────────────────
function GB.AT.Tick(dt)
    local state = GB.State
    local cfg   = state.cfg
    if not cfg or cfg.type ~= GearboxConst.Type.AT then return end
    if state.isShifting then return end
    if not state.engineOn then return end
    if state.reversing then return end

    local vehicle  = state.vehicle
    local now      = GetGameTimer()
    local maxGear  = cfg.maxGear
    local rpm      = state.rpm       -- AT 模式 rpm = native RPM（由 rpm_engine 直讀）
    local gear     = state.currentGear
    local throttle = state.throttleInput

    -- ── 換檔冷卻期間：鎖住 highGear = scriptGear，防止 GTA AT 升檔 ──
    if now < state.shiftLockUntil then
        GB.Native.SyncATHighGear(vehicle, gear, maxGear)
        return
    end

    -- ── 同步 GTA 原生檔位 → state ────────────────────────
    local nativeGear = GB.GearSync.PullATReference(vehicle, maxGear)
    if nativeGear and nativeGear > 0 then
        state.nativeGear = nativeGear
        if nativeGear ~= gear then
            state.currentGear = nativeGear
            gear = nativeGear
        end
    end

    -- ── 升降檔決策 ────────────────────────────────────────

    -- Kickdown（急加速降檔）
    -- 限制在 3 檔以上才 kickdown，避免 2→1 在全油門時反覆觸發
    if throttle > 0.92 and gear > 2 and gear < maxGear
        and rpm < math.max((cfg.downshiftRpm or 0.0) + 0.04, 0.35)
    then
        GB.AT._DoShift(gear, gear - 1, 'kickdown')
        return
    end

    -- 自動升檔
    if rpm > (cfg.upshiftRpm or 0.84) and gear < maxGear then
        GB.AT._DoShift(gear, gear + 1, 'upshift')
        return
    end

    -- 自動降檔（鬆油門 + 低 RPM）
    if rpm < (cfg.downshiftRpm or 0.42) and gear > 1 and throttle < 0.35 then
        GB.AT._DoShift(gear, gear - 1, 'downshift')
        return
    end

    -- 保持當前檔：確保 highGear = scriptGear（防止 GTA 自行升檔）
    GB.Native.SyncATHighGear(vehicle, gear, maxGear)
end

-- ─────────────────────────────────────────────────────────────
-- GB.AT._DoShift(fromGear, toGear, reason)
-- ─────────────────────────────────────────────────────────────
function GB.AT._DoShift(fromGear, toGear, reason)
    if Config.F8GearDebug then
        print(('[AT] %s: %d→%d rpm=%.3f'):format(reason, fromGear, toGear, GB.State.rpm))
    end
    GB.Core.ExecuteShift(fromGear, toGear, { needClutch = false })
end
