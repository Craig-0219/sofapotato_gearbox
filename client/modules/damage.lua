-- ─────────────────────────────────────────────────────
-- 離合器磨損 & 溫度系統
-- ─────────────────────────────────────────────────────

-- 磨損離合器（通用入口）
function WearClutch(amount)
    local state = GearboxState
    state.clutchHealth = math.max(0.0, state.clutchHealth - amount)

    if Config.Debug then
        print(('[Damage] Clutch health: %.1f%%'):format(state.clutchHealth))
    end
end

-- 換檔後的磨損（由 gearbox.lua 呼叫）
-- isBadShift = 離合器未完全踩下的換檔
function WearClutchOnShift(isBadShift)
    WearClutch(isBadShift and Config.Clutch.wearHalf or Config.Clutch.wearNormal)
end

-- 每幀更新溫度冷卻
function UpdateTemperature(dt)
    if not Config.Temperature.enabled then return end

    local state = GearboxState
    local speed = DoesEntityExist(state.vehicle)
        and GetEntitySpeed(state.vehicle) or 0.0

    local cooling = (Config.Temperature.cooldownRate
        + speed * Config.Temperature.speedCooldownBonus) * dt

    state.gearboxTemp = math.max(20.0, state.gearboxTemp - cooling)

    -- 過熱警告（每 10 秒通知一次，避免洗版）
    if state.gearboxTemp >= GearboxConst.Temp.OVERHEAT then
        local timer = math.floor(GetGameTimer() / 10000)
        if not GearboxState._lastTempWarn or GearboxState._lastTempWarn ~= timer then
            GearboxState._lastTempWarn = timer
            exports['sp_bridge']:Notify(GetLocale('TempHot'), 'warning')
        end
    end
end

-- 取得換檔延遲（考慮溫度加成懲罰）
function GetEffectiveShiftDelay()
    local state   = GearboxState
    local base    = state.cfg and state.cfg.shiftDelay or 150
    if Config.Temperature.enabled
        and state.gearboxTemp >= GearboxConst.Temp.OVERHEAT then
        return base + Config.Temperature.overheatShiftPenalty
    end
    return base
end

-- Server 同步後更新本地狀態（從持久化資料恢復）
RegisterNetEvent(GearboxConst.Events.SYNC_SETTINGS)
AddEventHandler(GearboxConst.Events.SYNC_SETTINGS, function(data)
    if not data then return end

    if data.clutchHealth and not IsStockTransmissionKey(data.transmKey) then
        GearboxState.clutchHealth = math.clamp(data.clutchHealth, 0.0, 100.0)
    elseif IsStockTransmissionKey(data.transmKey) then
        GearboxState.clutchHealth = 100.0
    end

    if data.transmKey then
        if GearboxState.inVehicle and DoesEntityExist(GearboxState.vehicle) then
            ApplyTransmissionState(GearboxState.vehicle, data.transmKey, data.handlingOverrides)
            if GetEntitySpeed(GearboxState.vehicle) <= 1.0 then
                ApplyManualNeutralStartIfNeeded(GearboxState.vehicle)
            end
        else
            GearboxState.transmKey = data.transmKey
            GearboxState.cfg = Config.Transmissions[data.transmKey]
            GearboxState.handlingOverrides = data.handlingOverrides
            RefreshActiveTransmissionRuntimeConfig()
        end
    end

    -- 同步已解鎖變速箱清單
    if type(data.unlockedTransmissions) == 'table' then
        GearboxState.unlockedTransmissions = data.unlockedTransmissions
    end

    if Config.Debug then
        print(('[Damage] Synced from server: clutch=%.1f transmKey=%s unlocks=%d')
            :format(data.clutchHealth or -1, data.transmKey or 'n/a',
                    #(data.unlockedTransmissions or {})))
    end
end)

-- 維修結果回傳
RegisterNetEvent(GearboxConst.Events.REPAIR_RESULT)
AddEventHandler(GearboxConst.Events.REPAIR_RESULT, function(success, reason)
    if success then
        GearboxState.clutchHealth = 100.0
        exports['sp_bridge']:Notify(GetLocale('RepairSuccess'), 'success')
    else
        local msg = reason == 'insufficient_funds'
            and GetLocale('RepairFailed')
            or  GetLocale('RepairFailed')
        exports['sp_bridge']:Notify(msg, 'error')
    end
end)
