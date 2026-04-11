-- ═══════════════════════════════════════════════════════════════
-- client/core/gearbox_core.lua
-- 換檔核心：狀態機轉換、ExecuteShift、Neutral、傳動型號切換
--
-- 職責：
--   - ExecuteShift(fromGear, toGear, opts)：唯一的換檔入口
--   - SetNeutral(bool)：空檔切換
--   - ChangeTransmission(key)：更換傳動型號
--   - 每幀 Tick(dt)：處理換檔冷卻結束、dirty flag 更新
--
-- 不負責：決定何時升/降檔（由 modes/ 決定）
-- ═══════════════════════════════════════════════════════════════

GB = GB or {}
GB.Core = {}

-- ─────────────────────────────────────────────────────────────
-- 工具
-- ─────────────────────────────────────────────────────────────
local function Lerp(a, b, t)
    return a + (b - a) * math.min(1.0, math.max(0.0, t))
end

-- ─────────────────────────────────────────────────────────────
-- GB.Core.GetShiftDelay(cfg)
-- 計算有效換檔延遲（考慮溫度懲罰）
-- ─────────────────────────────────────────────────────────────
function GB.Core.GetShiftDelay(cfg)
    if not cfg then return 200 end
    local base = cfg.shiftDelay or 200
    -- 過熱懲罰
    if Config.Temperature and Config.Temperature.enabled then
        local temp = GB.State.gearboxTemp or 20.0
        if temp >= (GearboxConst.Temp.OVERHEAT or 120.0) then
            base = base + (Config.Temperature.overheatShiftPenalty or 100)
        end
    end
    return base
end

-- ─────────────────────────────────────────────────────────────
-- GB.Core.CalcTargetRpmAfterShift(fromGear, toGear, cfg)
-- 換檔後的目標 RPM（依齒比換算，升檔落轉 / 降檔補轉）
-- ─────────────────────────────────────────────────────────────
function GB.Core.CalcTargetRpmAfterShift(fromGear, toGear, cfg)
    local ratios   = cfg and cfg.gearRatios
    if not ratios then return GB.State.rpm end
    local oldRatio = ratios[fromGear] or 1.0
    local newRatio = ratios[toGear]   or 1.0
    return math.clamp(
        GB.State.rpm * (newRatio / oldRatio),
        GearboxConst.Rpm.IDLE, 0.98
    )
end

-- ─────────────────────────────────────────────────────────────
-- GB.Core.ExecuteShift(fromGear, toGear, opts)
-- 核心換檔執行（AT/ATMT/MT 共用）
--
-- opts = {
--   needClutch = bool,   -- MT 用：換檔是否需要踩離合
--   silent     = bool,   -- 不播放音效（rev match 呼叫）
-- }
-- ─────────────────────────────────────────────────────────────
function GB.Core.ExecuteShift(fromGear, toGear, opts)
    local state = GB.State
    local cfg   = state.cfg
    opts = opts or {}

    if not cfg then return end
    if toGear == fromGear then return end

    local now   = GetGameTimer()
    local delay = GB.Core.GetShiftDelay(cfg)

    -- ── 狀態更新 ───────────────────────────────────────────
    state.isShifting     = true
    state.currentGear    = toGear
    state.desiredGear    = toGear
    state.shiftLockUntil = now + delay

    -- 目標 RPM（升檔落轉、降檔補轉）
    state.targetRpm = GB.Core.CalcTargetRpmAfterShift(fromGear, toGear, cfg)

    -- ── Native 同步（換檔瞬間一次）────────────────────────
    local vehicle = state.vehicle
    GB.Native.SetCurrentGear(vehicle, toGear)
    GB.Native.SetNextGear(vehicle, toGear)

    -- AT 模式需更新 highGear 防止 GTA AT 自行升檔
    if state:IsATMode() then
        GB.Native.SyncATHighGear(vehicle, toGear, cfg.maxGear)
    end

    -- 換檔後 per-gear 速度限制（dirty flag → Tick 中更新）
    state.speedLimitDirty = true
    state.gearNativeDirty = true

    -- MT 換檔：clutch 切斷驅動力（若按了離合）
    if state:IsMTMode() and not state.clutchKeyDown then
        -- 未踩離合 = bad shift
        if opts.needClutch then
            GB.Core._HandleBadShift()
            return
        end
    end

    -- ── 溫度上升 ───────────────────────────────────────────
    if Config.Temperature and Config.Temperature.enabled then
        state.gearboxTemp = state.gearboxTemp + 0.3
    end

    -- ── 離合器磨損 ──────────────────────────────────────────
    local isBadShift = opts.needClutch and not state.clutchKeyDown
    if type(GB.Clutch) == 'table' and type(GB.Clutch.WearOnShift) == 'function' then
        GB.Clutch.WearOnShift(isBadShift)
    end

    -- ── 音效同步 ───────────────────────────────────────────
    if not opts.silent then
        if type(BroadcastShiftRpm) == 'function' then
            BroadcastShiftRpm(state.vehicleNetId, state.targetRpm, toGear)
        end
        -- 渦輪洩壓（升檔）
        if toGear > fromGear and type(PlayTurboBlowoff) == 'function' then
            PlayTurboBlowoff(vehicle)
        end
    end

    if Config.Debug then
        print(('[GearboxCore] Shift %d→%d rpm=%.2f→%.2f delay=%dms type=%s')
            :format(fromGear, toGear, state.rpm, state.targetRpm, delay, cfg.type))
    end
end

-- ─────────────────────────────────────────────────────────────
-- GB.Core._HandleBadShift()
-- MT 未踩離合換檔的懲罰
-- ─────────────────────────────────────────────────────────────
function GB.Core._HandleBadShift()
    local state   = GB.State
    local vehicle = state.vehicle
    local throttle = math.max(0.0, state.throttleInput)

    -- 頓挫力
    if throttle > 0.20 then
        local jerk = (throttle - 0.20) * 0.45
        local fwd  = GetEntityForwardVector(vehicle)
        ApplyForceToEntity(vehicle, 5,
            -fwd.x * jerk, -fwd.y * jerk, 0.0,
            0.0, 0.0, 0.0, false, false, true, true, false)
    end

    -- 溫度
    if Config.Temperature and Config.Temperature.enabled then
        state.gearboxTemp = state.gearboxTemp + (Config.Temperature.shiftAbuseRise or 0.8)
    end

    -- 熄火機率
    if type(GB.Stall) == 'table' and type(GB.Stall.TryStallFromAbuse) == 'function' then
        GB.Stall.TryStallFromAbuse()
    end

    -- 通知
    if type(exports['sp_bridge']) == 'table' then
        exports['sp_bridge']:Notify(GetLocale('ShiftFailed'), 'error')
    end
end

-- ─────────────────────────────────────────────────────────────
-- GB.Core.SetNeutral(toNeutral)
-- 空檔切換（MT 專用）
-- ─────────────────────────────────────────────────────────────
function GB.Core.SetNeutral(toNeutral)
    local state = GB.State
    if toNeutral == state.isNeutral then return end

    state.isNeutral = toNeutral

    local vehicle = state.vehicle
    if toNeutral then
        -- 進空檔：切斷動力，保留 currentGear = 1 供 RPM 公式用
        state.clutchAxis  = 1.0
        state.currentGear = 1
        state.desiredGear = 1
        GB.Native.SetCurrentGear(vehicle, 1)
        GB.Native.SetNextGear(vehicle, 1)
        GB.Native.SyncClutch(vehicle, 1.0)  -- 切斷
        if Config.Debug then print('[GearboxCore] → Neutral') end
    else
        -- 出空檔：接回 1 檔
        state.clutchAxis  = 1.0  -- 保持踩住，讓玩家自己放離合起步
        state.currentGear = 1
        state.desiredGear = 1
        GB.Native.SetCurrentGear(vehicle, 1)
        GB.Native.SetNextGear(vehicle, 1)
        -- clutch 由 clutch_engine 在下一幀更新
        if Config.Debug then print('[GearboxCore] Neutral → 1st') end
    end
end

function GB.Core.ToggleNeutral()
    GB.Core.SetNeutral(not GB.State.isNeutral)
end

-- ─────────────────────────────────────────────────────────────
-- GB.Core.Tick(dt)
-- 每幀呼叫：處理換檔冷卻結束、dirty flag 驅動的 native 更新
-- ─────────────────────────────────────────────────────────────
function GB.Core.Tick(dt)
    local state = GB.State
    local now   = GetGameTimer()

    -- ── 換檔冷卻結束 ───────────────────────────────────────
    if state.isShifting and now >= state.shiftLockUntil then
        state.isShifting = false
        if Config.Debug then
            print(('[GearboxCore] Shift complete, gear=%d'):format(state.currentGear))
        end
    end

    -- ── Speed Limit Dirty Flag ─────────────────────────────
    -- 換檔後更新一次 per-gear 頂速，之後不再每幀設
    if state.speedLimitDirty and not state.isShifting then
        GB.GearRatios.ApplyGearSpeedLimit(state.vehicle, state.currentGear)
        -- ApplyGearSpeedLimit 內部會清除 dirty flag
    end

    -- ── ATMT/MT：Gear Native Dirty Flag ───────────────────
    -- 每幀強制同步 SetVehicleCurrentGear + SetVehicleNextGear
    -- 必須搭配正確 RPM，否則 GTA AT 邏輯會 override
    if state:IsManualMode() and not state.reversing then
        GB.GearSync.ApplyManualTruth(state.vehicle)
    end
end

-- ─────────────────────────────────────────────────────────────
-- GB.Core.ChangeTransmission(key)
-- 更換傳動型號（進車後玩家可在選單切換）
-- ─────────────────────────────────────────────────────────────
function GB.Core.ChangeTransmission(key)
    local state   = GB.State
    local vehicle = state.vehicle

    if key == 'STOCK' or key == nil then
        -- 還原原廠 handling
        GB.GearRatios.RestoreSnapshot(vehicle)
        state.transmKey  = 'STOCK'
        state.cfg        = nil
        state.perGearCache = nil
        state.currentGear = 1
        state.isNeutral   = false
        if Config.Debug then print('[GearboxCore] → STOCK') end
        return
    end

    local cfg = Config.Transmissions and Config.Transmissions[key]
    if not cfg then
        print('[GearboxCore] ERROR: Unknown transmission key: ' .. tostring(key))
        return
    end

    -- 確保 snapshot 存在
    if not state.handlingSnapshot then
        GB.GearRatios.CaptureSnapshot(vehicle)
    end

    state.transmKey   = key
    state.cfg         = cfg
    state.currentGear = 1
    state.desiredGear = 1
    state.isNeutral   = false
    state.isShifting  = false
    state.shiftLockUntil = 0

    -- 預算每檔快取
    GB.GearRatios.BuildPerGearCache(cfg, state.handlingSnapshot)

    -- 套用 handling
    GB.GearRatios.ApplyToVehicle(vehicle, cfg)

    -- MT 進車空檔
    if cfg.type == GearboxConst.Type.MT and Config.MTStartInNeutral then
        GB.Core.SetNeutral(true)
    end

    -- 重設 native_adapter 內部狀態
    GB.Native.Reset()

    if Config.Debug then
        print(('[GearboxCore] Changed to %s (%s, maxGear=%d)')
            :format(key, cfg.type, cfg.maxGear))
    end
end
