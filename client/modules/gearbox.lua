-- ─────────────────────────────────────────────────────
-- 換檔邏輯：AT 自動 / ATMT 手自排 / MT 手排
-- ─────────────────────────────────────────────────────

local AT_DEBUG_INTERVAL_MS = 400
local _lastATDebugAt = 0
local _lastATDebugReason = nil

local function LockScriptedATGear(vehicle, gear)
    if Config.UseNativeATLogic ~= false then return end
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if not gear or gear < 1 then return end

    -- 注意：不在此呼叫 SetVehicleHighGear。
    -- SetVehicleHighGear 若設為 currentGear，GTA 物理引擎會把車輛傳動
    -- 上限鎖死在該檔，導致速度被蓋頂、RPM 無法攀升、永遠卡檔。
    -- SetVehicleHighGear(maxGear) 已由 EnforceTransmissionGearLimit 在
    -- 進車與每次換檔時統一維護，此處不重複覆蓋。

    if type(SetVehicleCurrentGear) == 'function' then
        SetVehicleCurrentGear(vehicle, gear)
    end

    if type(SetVehicleNextGear) == 'function' then
        SetVehicleNextGear(vehicle, gear)
    end
end

local function PrintATDebug(reason, cfg, maxGear, throttle)
    if not Config.F8GearDebug then return end

    local state = GearboxState
    local vehicle = state.vehicle
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local now = GetGameTimer()
    local important = reason ~= 'hold'
    if not important and _lastATDebugReason == reason and (now - _lastATDebugAt) < AT_DEBUG_INTERVAL_MS then
        return
    end

    _lastATDebugAt = now
    _lastATDebugReason = reason

    local gtaGear = type(GetVehicleCurrentGear) == 'function' and GetVehicleCurrentGear(vehicle) or -1
    local nextGear = type(GetVehicleNextGear) == 'function' and GetVehicleNextGear(vehicle) or -1
    local speedMph = GetEntitySpeed(vehicle) * 2.236936
    local currentRatio = (cfg.gearRatios and cfg.gearRatios[state.currentGear]) or -1.0
    local topRatio = (cfg.gearRatios and cfg.gearRatios[maxGear]) or -1.0

    print(('[gearbox][ATDBG][%s] transm=%s gear=%d gta=%d next=%d rpm=%.3f target=%.3f up=%.3f down=%.3f max=%d thr=%.2f speed=%.1f ratio=%.2f top=%.2f shifting=%s')
        :format(
            reason,
            tostring(state.transmKey),
            state.currentGear or -1,
            gtaGear,
            nextGear,
            state.rpm or -1.0,
            state.targetRpm or -1.0,
            cfg.upshiftRpm or -1.0,
            cfg.downshiftRpm or -1.0,
            maxGear or -1,
            throttle or -1.0,
            speedMph,
            currentRatio,
            topRatio,
            tostring(state.isShifting)
        ))
end

-- ── 統一換檔入口（由 input.lua 的 RegisterCommand 呼叫）─────
function TriggerShift(direction)
    local state = GearboxState
    local cfg = GetActiveTransmissionConfig() or state.cfg
    if not state.inVehicle or not cfg then return end
    if not state.engineOn then return end
    if state.isShifting then return end

    local t = cfg.type
    if     t == GearboxConst.Type.AT   then return   -- AT 不接受手動換檔
    elseif t == GearboxConst.Type.ATMT then ShiftATMT(direction)
    elseif t == GearboxConst.Type.MT   then ShiftMT(direction)
    end
end

-- ── ATMT 手自排 ─────────────────────────────────────────────
function ShiftATMT(direction)
    local state   = GearboxState
    local cfg     = GetActiveTransmissionConfig() or state.cfg
    local maxGear = GetActiveTransmissionMaxGear() or cfg.maxGear
    local newGear = state.currentGear + direction

    if direction == GearboxConst.ShiftDir.UP   and newGear > maxGear then return end
    if direction == GearboxConst.ShiftDir.DOWN and newGear < 1               then return end

    ExecuteShift(state.currentGear, newGear, false)
end

-- ── MT 手排 ─────────────────────────────────────────────────
function ShiftMT(direction)
    local state       = GearboxState
    local cfg         = GetActiveTransmissionConfig() or state.cfg
    local maxGear     = GetActiveTransmissionMaxGear() or cfg.maxGear

    -- 離合器故障（耐久 0）：完全無法換檔
    if state.clutchHealth <= GearboxConst.ClutchHealth.BROKEN then
        exports['sp_bridge']:Notify(GetLocale('ClutchBroken'), 'error')
        return
    end

    -- 鍵盤二元離合：直接檢查按鍵狀態（clutchValue 在主循環才更新，此處不可靠）
    if not state.clutchKeyDown then
        HandleBadShift()
        return
    end

    local newGear = state.currentGear + direction

    -- 降到 1 檔以下 → 進空檔
    if direction == GearboxConst.ShiftDir.DOWN and newGear < 1 then
        if not state.isNeutral then
            SetNeutral(true)
        end
        return
    end

    -- 從空檔升檔 → 接回 1 檔
    if state.isNeutral and direction == GearboxConst.ShiftDir.UP then
        SetNeutral(false)
        newGear = 1
    end

    if newGear < 1 or newGear > maxGear then return end

    -- 降檔補油（rev match assist）
    if direction == GearboxConst.ShiftDir.DOWN then
        DoRevMatch(state.currentGear, newGear, cfg)
    end

    ExecuteShift(state.currentGear, newGear, true)
end

-- ── AT 自動換檔（每幀由 main.lua 呼叫）─────────────────────
function UpdateAT(dt)
    local state = GearboxState
    local cfg = GetActiveTransmissionConfig() or state.cfg
    if not cfg or cfg.type ~= GearboxConst.Type.AT then return end
    if state.isShifting then return end
    if not state.engineOn then return end
    if IsVehicleReversingState(state.vehicle) then return end

    local now = GetGameTimer()
    local maxGear  = GetActiveTransmissionMaxGear() or cfg.maxGear
    local rpm      = state.rpm
    local gear     = state.currentGear
    local throttle = math.abs(GetVehicleThrottleOffset(state.vehicle))
    local debugReason = 'hold'

    -- 可切換成 GTA 原生自排邏輯。
    -- 預設目前是腳本控制；只有明確開啟時才走這條分支。
    if Config.UseNativeATLogic ~= false then
        local gtaGear = GetVehicleCurrentGear(state.vehicle)
        if maxGear and gtaGear > maxGear then
            gtaGear = maxGear
        end

        if gtaGear > 0 and gtaGear ~= gear then
            state.currentGear = gtaGear
            state.targetRpm = GetVehicleCurrentRpm(state.vehicle)
            BroadcastShiftRpm(state.vehicleNetId, state.targetRpm, gtaGear)
            PrintATDebug(('native_shift_%d_to_%d'):format(gear, gtaGear), cfg, maxGear, throttle)
        else
            PrintATDebug((gtaGear >= maxGear) and 'native_at_max' or 'native_hold', cfg, maxGear, throttle)
        end

        return
    end

    if state.shiftTimer and state.shiftTimer > now then
        -- 換檔冷卻期間鎖定檔位，防止 GTA 原生邏輯立刻重新換檔
        LockScriptedATGear(state.vehicle, gear)
        PrintATDebug('cooldown', cfg, maxGear, throttle)
        return
    end

    -- 同步 GTA 原生檔位 → state（平時讓 GTA 物理自由加速，不強制鎖檔）
    local nativeGear = GetVehicleCurrentGear(state.vehicle)
    if nativeGear > 0 and nativeGear ~= gear then
        -- 超過 maxGear 才截斷，其他讓 GTA 自然換檔
        if nativeGear > maxGear then
            nativeGear = maxGear
            SetVehicleCurrentGear(state.vehicle, maxGear)
        end
        state.currentGear = nativeGear
        gear = nativeGear
    end

    -- 急加速降檔（Kickdown）
    -- 限制在 3 檔以上才 kickdown，避免 2→1 在全油門時反覆觸發。
    if throttle > 0.92 and gear > 2 and gear < maxGear and rpm < math.max((cfg.downshiftRpm or 0.0) + 0.04, 0.35) then
        PrintATDebug('kickdown', cfg, maxGear, throttle)
        ExecuteShift(gear, gear - 1, false)
        return
    end

    -- 自動升檔
    if rpm > cfg.upshiftRpm and gear < maxGear then
        PrintATDebug('upshift', cfg, maxGear, throttle)
        ExecuteShift(gear, gear + 1, false)

    -- 自動降檔
    elseif rpm < cfg.downshiftRpm and gear > 1 and throttle < 0.35 then
        PrintATDebug('downshift', cfg, maxGear, throttle)
        ExecuteShift(gear, gear - 1, false)
    else
        if gear >= maxGear then
            debugReason = 'at_max'
        elseif rpm <= cfg.upshiftRpm and gear < maxGear then
            debugReason = 'hold'
        end
    end

    -- 注意：平時不在此呼叫 LockScriptedATGear。
    -- 每幀強制 SetVehicleCurrentGear 會讓 GTA 物理鎖死在低檔，造成卡檔。
    -- 鎖檔只在換檔冷卻期間（shiftTimer）執行。
    PrintATDebug(debugReason, cfg, maxGear, throttle)
end

-- ── 核心換檔執行（三種類型共用）────────────────────────────
function ExecuteShift(fromGear, toGear, needClutch)
    local state   = GearboxState
    local cfg     = GetActiveTransmissionConfig() or state.cfg
    if not cfg then return end

    local delay = GetEffectiveShiftDelay()
    state.isShifting  = true
    state.currentGear = toGear
    state.shiftTimer  = GetGameTimer() + delay + 220

    -- 換檔後轉速目標（依齒比換算）
    local oldRatio    = cfg.gearRatios[fromGear] or 1.0
    local newRatio    = cfg.gearRatios[toGear]   or 1.0
    state.targetRpm   = math.clamp(
        state.rpm * (newRatio / oldRatio),
        GearboxConst.Rpm.IDLE, 0.98
    )

    -- 套用到 GTA（每次換檔觸發一次，非每幀強制）
    -- 每幀強制 SetVehicleCurrentGear 會造成 0.3.0 的自動降檔迴圈；
    -- 換檔時呼叫一次則是安全的：告知 GTA 進入新齒位使驅動力跟上，
    -- 不再每幀強制故 GTA 不會形成持續降檔→截油→迴圈。
    -- ATMT/MT 若不呼叫此行，GTA AT 不知道要換到新齒位，
    -- 仍以舊齒位驅動力計算，時速會卡在舊齒頂速無法繼續加速。
    SetVehicleCurrentGear(state.vehicle, toGear)
    EnforceTransmissionGearLimit(state.vehicle, {
        maxGear = GetActiveTransmissionMaxGear() or cfg.maxGear,
    })
    if cfg.type == GearboxConst.Type.MT then
        SetVehicleClutch(state.vehicle, 1.0 - GetEffectiveClutch())
    end

    -- 溫度上升
    if Config.Temperature.enabled then
        state.gearboxTemp = state.gearboxTemp + 0.3
    end

    -- 計算離合器磨損（鍵盤二元：未按離合鍵才算 bad shift）
    local isBadShift = needClutch and not state.clutchKeyDown
    WearClutchOnShift(isBadShift)

    -- 廣播換檔 RPM 給附近玩家（引擎音效同步）
    BroadcastShiftRpm(state.vehicleNetId, state.targetRpm, toGear)

    if cfg.type == GearboxConst.Type.AT then
        PrintATDebug(('shift_%d_to_%d'):format(fromGear, toGear), cfg,
            GetActiveTransmissionMaxGear() or cfg.maxGear,
            math.abs(GetVehicleThrottleOffset(state.vehicle)))
    end

    -- 渦輪洩壓音效（升檔時）
    if toGear > fromGear then
        PlayTurboBlowoff(state.vehicle)
    end

    -- 換檔延遲後解除鎖定
    CreateThread(function()
        Wait(delay)
        state.isShifting = false
        if Config.Debug then
            print(('[Gearbox] %d→%d rpm=%.2f delay=%dms'):format(fromGear, toGear, state.rpm, delay))
        end
    end)
end

-- ── 換檔失敗（MT 離合器不足）────────────────────────────────
function HandleBadShift()
    local state   = GearboxState
    local throttle = math.max(0.0, GetVehicleThrottleOffset(state.vehicle))

    -- 頓挫
    ApplyShiftJerk(state.vehicle, throttle, GetEffectiveClutch())

    -- 溫度上升
    if Config.Temperature.enabled then
        state.gearboxTemp = state.gearboxTemp + Config.Temperature.shiftAbuseRise
    end

    -- 嘗試熄火
    TryStallFromShiftAbuse()

    exports['sp_bridge']:Notify(GetLocale('ShiftFailed'), 'error')
end

-- ── 空檔切換 ────────────────────────────────────────────────
function ToggleNeutral()
    SetNeutral(not GearboxState.isNeutral)
end

function SetNeutral(toNeutral)
    local state = GearboxState
    if toNeutral == state.isNeutral then return end

    state.isNeutral = toNeutral
    state.currentGear = 1

    if toNeutral then
        state.clutchValue = 1.0
        if type(SetVehicleCurrentGear) == 'function' then
            SetVehicleCurrentGear(state.vehicle, 1)
        end
        if type(SetVehicleNextGear) == 'function' then
            SetVehicleNextGear(state.vehicle, 1)
        end
        SetVehicleClutch(state.vehicle, 0.0)  -- 0.0 = 切斷動力
        if Config.Debug then print('[Gearbox] → Neutral') end
    else
        if type(SetVehicleCurrentGear) == 'function' then
            SetVehicleCurrentGear(state.vehicle, 1)
        end
        if type(SetVehicleNextGear) == 'function' then
            SetVehicleNextGear(state.vehicle, 1)
        end
        SetVehicleClutch(state.vehicle, 1.0 - GetEffectiveClutch())
        if Config.Debug then print('[Gearbox] Neutral → 1st') end
    end
end
