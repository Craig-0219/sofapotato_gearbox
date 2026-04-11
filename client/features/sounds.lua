-- ═══════════════════════════════════════════════════════════════
-- client/features/sounds.lua
-- Audio sync feature
-- 僅做事件廣播/接收，不直接寫 remote drivetrain native。
-- ═══════════════════════════════════════════════════════════════

function BroadcastShiftRpm(vehicleNetId, newRpm, newGear)
    if not Config.Sounds.broadcastEnabled then return end
    TriggerServerEvent(GearboxConst.Events.NET_SYNC_RPM, vehicleNetId, newRpm, newGear)
end

function BroadcastStall(vehicleNetId)
    if not Config.Sounds.broadcastEnabled then return end
    TriggerServerEvent(GearboxConst.Events.NET_SYNC_STALL, vehicleNetId)
end

RegisterNetEvent(GearboxConst.Events.NET_SYNC_RPM, function(vehicleNetId, newRpm, newGear)
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehicle) then return end

    local localVeh = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == localVeh then return end

    Entity(vehicle).state:set('gbRemoteShiftRpm', {
        rpm = newRpm,
        gear = newGear,
        at = GetGameTimer(),
    }, false)
end)

RegisterNetEvent(GearboxConst.Events.NET_SYNC_STALL, function(vehicleNetId)
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehicle) then return end

    local localVeh = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == localVeh then return end

    Entity(vehicle).state:set('gbRemoteStallAt', GetGameTimer(), false)
end)

function PlayTurboBlowoff(vehicle)
    if not Config.Turbo.enabled then return end
    local cfg = GetActiveTransmissionConfig() or GearboxState.cfg
    if not cfg or not cfg.turbo then return end
end
