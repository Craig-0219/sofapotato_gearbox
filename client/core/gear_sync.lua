-- ═══════════════════════════════════════════════════════════════
-- client/core/gear_sync.lua
-- Drivetrain authority / gear sync policy
--
-- Truth source:
--   - currentGear / desiredGear / isNeutral / clutchAxis / rpm(target)
--       => script truth (GB.State)
--   - nativeGear
--       => reference only（AT 觀測用，不可反向覆蓋 manual 模式真相）
--
-- Mode policy:
--   - AT   : script 決策檔位，並觀測 nativeGear 校正（受 maxGear 限制）
--   - ATMT : script truth；native 只接收 SyncGear
--   - MT   : script truth；native 只接收 SyncGear + clutch/rpm 輸出
-- ═══════════════════════════════════════════════════════════════

GB = GB or {}
GB.GearSync = {}

function GB.GearSync.PullATReference(vehicle, maxGear)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end

    local nativeGear = GetVehicleCurrentGear(vehicle)
    if not nativeGear or nativeGear <= 0 then return nil end

    if maxGear and nativeGear > maxGear then
        nativeGear = maxGear
        GB.Native.SetCurrentGear(vehicle, maxGear)
        GB.Native.SetNextGear(vehicle, maxGear)
    end

    GB.State.nativeGear = nativeGear
    return nativeGear
end

function GB.GearSync.ApplyManualTruth(vehicle)
    local state = GB.State
    local gear = math.max(1, math.min(state.currentGear or 1, state:MaxGear()))
    GB.Native.SyncGear(vehicle, gear)
end
