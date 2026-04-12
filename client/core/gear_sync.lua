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
    -- [HRSGears] GTA 的內部 gear 永遠鎖在 1，highGear 也設為 1。
    --
    -- 原理：GTA AT 的油門切斷條件是「currentGear < highGear 且 naturalRpm 過低」。
    -- currentGear = highGear = 1 → 條件永遠 false → 油門切斷永不觸發。
    --
    -- 各檔的扭力差異由 ApplyGearSpeedLimit（每次換檔）設定
    -- fInitialDriveForce = snapshot.driveForce × torqueScale，
    -- 取代原本依賴 SetVehicleEngineTorqueMultiplier 的 SyncGearTorque 方案。
    --
    -- naturalRpm = speed / (fInitialDriveMaxFlatVel × ratio[1]/ratio[1])
    --            = speed / fInitialDriveMaxFlatVel = speed / topSpeedMps[scriptGear]
    -- → 在各檔頂速時 naturalRpm → 1.0，驅動力自然衰減 ✓
    GB.Native.SyncGear(vehicle, 1)

    if type(SetVehicleHighGear) == 'function' then
        SetVehicleHighGear(vehicle, 1)
    end
end
