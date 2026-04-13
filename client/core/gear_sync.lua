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

    -- 每幀把 GTA 內部 gear 鎖成 scriptGear（防止 GTA AT 覆蓋腳本檔位）
    GB.Native.SyncGear(vehicle, gear)

    -- [FIX-D] highGear = currentGear 每幀鎖定。
    --
    -- GTA AT 的油門切斷條件：currentGear < highGear 且 naturalRpm 過低。
    -- highGear = currentGear → 條件永遠 false → 油門不被切斷 ✓
    --
    -- 為何用 highGear=currentGear 而非 highGear=1（HRSGears 方案）：
    -- 本 codebase 有多個模組讀取 GetVehicleCurrentGear（gearbox.lua AT 邏輯、
    -- state.lua、modules/physics.lua 等）。若鎖成 gear 1，這些模組會把
    -- state.currentGear 覆蓋成 1，導致 ApplyGearSpeedLimit 永遠拿到 gear=1。
    --
    -- highGear=currentGear 讓 GTA 看到正確檔位，各模組讀值一致，
    -- 同時消除 throttle cut 問題。
    --
    -- torqueScale 補償：由 ApplyGearSpeedLimit 在每次換檔時設定
    -- fInitialDriveForce = snapshot.driveForce × torqueScale，
    -- 不依賴 SyncGearTorque（SetVehicleEngineTorqueMultiplier 可能有 > 1 截斷問題）。
    if type(SetVehicleHighGear) == 'function' then
        SetVehicleHighGear(vehicle, gear)
    end
end
