-- Server 主入口
-- 目前邏輯集中在 server/modules/persistence.lua
-- 此檔案供未來擴展（換檔音效廣播等）

RegisterNetEvent(GearboxConst.Events.NET_SYNC_RPM, function(vehicleNetId, newRpm, newGear)
    TriggerClientEvent(GearboxConst.Events.NET_SYNC_RPM, -1, vehicleNetId, newRpm, newGear)
end)

RegisterNetEvent(GearboxConst.Events.NET_SYNC_STALL, function(vehicleNetId)
    TriggerClientEvent(GearboxConst.Events.NET_SYNC_STALL, -1, vehicleNetId)
end)

print('[sofapotato_gearbox] Server started.')
