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

    -- 同步 currentGear + nextGear（防止 GTA AT 覆蓋腳本檔位）
    GB.Native.SyncGear(vehicle, gear)

    -- [FIX-D] 每幀把 highGear 鎖成 currentGear（而非 maxGear）。
    --
    -- 問題根源：GTA 的 AT 邏輯每幀計算 naturalRpm = speed / fInitialDriveMaxFlatVel。
    -- 當它看到「currentGear < highGear 且 naturalRpm 過低」時，判斷「你不應該在這檔」，
    -- 於是每幀把內部 throttleOffset 鎖為 0 → 輪軸扭力歸零 → 車子在高檔低速時無法加速。
    -- 解法：highGear = currentGear，讓 GTA 始終認為「已在最高檔」，停止介入油門。
    --
    -- 副作用：highGear = currentGear 使 GTA 內部的 torqueMultiplier（ratio[cur]/ratio[high]）
    -- 恆等於 1.0，喪失齒比扭力差異。以下用 SyncGearTorque 手動補回。
    if type(SetVehicleHighGear) == 'function' then
        SetVehicleHighGear(vehicle, gear)
    end

    -- 齒比扭力補償（等效於舊 highGear=maxGear 時 GTA 自己算的 ratio[cur]/ratio[max]）
    local cache      = state.perGearCache
    local torqueScale = (cache and cache[gear] and cache[gear].torqueScale) or 1.0
    GB.Native.SyncGearTorque(vehicle, torqueScale)
end
