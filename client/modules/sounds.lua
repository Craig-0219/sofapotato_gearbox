-- ─────────────────────────────────────────────────────
-- 換檔 RPM 廣播：讓附近玩家也能聽到引擎音效變化
-- GTA 引擎音效由 RPM 驅動，同步 RPM = 同步音效
-- ─────────────────────────────────────────────────────

-- 廣播換檔後的 RPM 與檔位給附近玩家
function BroadcastShiftRpm(vehicleNetId, newRpm, newGear)
    if not Config.Sounds.broadcastEnabled then return end
    TriggerServerEvent(GearboxConst.Events.NET_SYNC_RPM, vehicleNetId, newRpm, newGear)
end

-- 廣播熄火
function BroadcastStall(vehicleNetId)
    if not Config.Sounds.broadcastEnabled then return end
    TriggerServerEvent(GearboxConst.Events.NET_SYNC_STALL, vehicleNetId)
end

-- ── 接收其他玩家的換檔 RPM 同步 ──────────────────────
RegisterNetEvent(GearboxConst.Events.NET_SYNC_RPM, function(vehicleNetId, newRpm, newGear)
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehicle) then return end

    -- 不處理自己的駕駛車輛
    local localVeh = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == localVeh then return end

    -- 套用 RPM 讓引擎音效短暫反映換檔動作
    SetVehicleCurrentRpm(vehicle, newRpm)
    if newGear and newGear > 0 then
        SetVehicleCurrentGear(vehicle, newGear)
    end
end)

-- 接收熄火同步
RegisterNetEvent(GearboxConst.Events.NET_SYNC_STALL, function(vehicleNetId)
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehicle) then return end

    local localVeh = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == localVeh then return end

    SetVehicleCurrentRpm(vehicle, 0.0)
end)

-- ── 渦輪洩壓音效（本地播放，換檔後呼叫）─────────────
-- GTA V 車輛渦輪音效透過 RPM 下降自然產生
-- 若日後加入自訂音效，在此函數內呼叫 PlaySoundFromEntity
function PlayTurboBlowoff(vehicle)
    if not Config.Turbo.enabled then return end
    local cfg = GetActiveTransmissionConfig() or GearboxState.cfg
    if not cfg or not cfg.turbo then return end
    -- TODO: 自訂音效檔時，在此加入 PlaySoundFromEntity
end
