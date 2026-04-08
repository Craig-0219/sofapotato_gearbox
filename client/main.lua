-- ─────────────────────────────────────────────────────
-- Client 入口：車輛偵測、主循環、HUD 循環
-- ─────────────────────────────────────────────────────

-- ── 車輛進入偵測（輪詢，500ms 間隔）─────────────────────
-- 注意：離車偵測由主循環負責（帶 debounce），此處只處理進車。
local _wasInVehicle = false

CreateThread(function()
    while true do
        Wait(500)
        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local inVehicle = vehicle ~= 0
            and GetPedInVehicleSeat(vehicle, -1) == ped  -- 確認是駕駛座

        if inVehicle and not GearboxState.inVehicle then
            OnEnterVehicle(vehicle)
        end

        _wasInVehicle = inVehicle
    end
end)

function OnEnterVehicle(vehicle)
    GearboxStateInit(vehicle)
    -- 向 server 請求持久化資料（帶入 model 名稱讓 server 查表）
    TriggerServerEvent(GearboxConst.Events.LOAD_SETTINGS, {
        vehicleNetId = GearboxState.vehicleNetId,
        modelName    = GearboxState.modelName,
        vehiclePlate = GearboxState.vehiclePlate,
    })
    if Config.Debug then
        print(('[Main] Entered vehicle %d | transm=%s'):format(vehicle, GearboxState.transmKey))
    end
end

function OnExitVehicle()
    local vehicle = GearboxState.vehicle
    LocalPlayer.state:set('gearboxScriptGear', nil, false)

    if GearboxState.vehicleNetId ~= 0 then
        TriggerServerEvent(GearboxConst.Events.SAVE_SETTINGS, {
            vehicleNetId = GearboxState.vehicleNetId,
            vehicleModel = GearboxState.modelName,
            vehiclePlate = GearboxState.vehiclePlate,
            transmKey    = GearboxState.transmKey,
            clutchHealth = GearboxState.clutchHealth,
            handlingOverrides = GearboxState.handlingOverrides,
        })
    end

    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        RestoreVehicleGearHandling(vehicle)
    end

    GearboxStateReset()
    if Config.Debug then
        print('[Main] Exited vehicle')
    end
end

-- ── 資源停止時還原 handling ───────────────────────────
-- 資源重啟時若不還原，GTA 會保留已修改的 handling 值；
-- 下次進車 CaptureVehicleHandlingBackup 就捕捉到壞掉的 fInitialDriveMaxFlatVel。
AddEventHandler('onClientResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    local vehicle = GearboxState.vehicle
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        RestoreVehicleGearHandling(vehicle)
    end
end)

-- ── 主循環 ────────────────────────────────────────────
-- 離車偵測集中在此（帶 1000ms debounce），避免 500ms 輪詢在
-- 按下離合器的瞬間誤判短暫離座（GTA 物理/動畫抖動）而重置狀態。
local _lastFrameTime = GetGameTimer()
local _notInSeatSince = 0
local NOT_IN_SEAT_DEBOUNCE_MS = 1000  -- 持續離座 1 秒才視為真正離車

-- 安全呼叫包裝：任何模組更新拋出 Lua runtime error 時，
-- 只記錄錯誤並跳過當幀，不讓整個主執行緒崩潰死亡。
local function SafeUpdate(fn, dt)
    local ok, err = pcall(fn, dt)
    if not ok then
        print('[Gearbox][ERROR] ' .. tostring(err))
    end
end

CreateThread(function()
    while true do
        local now = GetGameTimer()

        if GearboxState.inVehicle then
            -- 確認車輛仍然有效，玩家仍在駕駛座
            local ped = PlayerPedId()
            local inSeat = DoesEntityExist(GearboxState.vehicle)
                and GetPedInVehicleSeat(GearboxState.vehicle, -1) == ped

            if not inSeat then
                -- 防抖：短暫離座不立即觸發（碰撞彈出、輸入動畫、物理抖動）
                if _notInSeatSince == 0 then
                    _notInSeatSince = now
                elseif (now - _notInSeatSince) >= NOT_IN_SEAT_DEBOUNCE_MS then
                    _notInSeatSince = 0
                    OnExitVehicle()
                end
                _lastFrameTime = now
                Wait(50)

            elseif GearboxState.cfg then
                -- 在座 + 有變速箱設定：每幀執行物理更新
                _notInSeatSince = 0
                local dt = math.min((now - _lastFrameTime) / 1000.0, 0.10)
                _lastFrameTime = now

                -- 同步 GTA 引擎狀態
                GearboxState.engineOn = IsVehicleEngineOn(GearboxState.vehicle)

                -- 不只限制 Lua 狀態，也要每幀限制 GTA 原生實際檔位
                EnforceTransmissionGearLimit(GearboxState.vehicle, {
                    maxGear = GetActiveTransmissionMaxGear() or GearboxState.cfg.maxGear,
                })

                -- 各模組更新（pcall 保護：任一錯誤只影響當幀，不殺死執行緒）
                SafeUpdate(UpdateClutch, dt)
                SafeUpdate(UpdatePhysics, dt)
                SafeUpdate(UpdateStall, dt)
                SafeUpdate(UpdateTemperature, dt)
                SafeUpdate(UpdateDrift, dt)
                SafeUpdate(UpdateLaunchControl, dt)

                -- AT 自動換檔
                local activeCfg = GetActiveTransmissionConfig() or GearboxState.cfg
                if activeCfg and activeCfg.type == GearboxConst.Type.AT then
                    SafeUpdate(UpdateAT, dt)
                elseif activeCfg and (
                    activeCfg.type == GearboxConst.Type.ATMT
                    or activeCfg.type == GearboxConst.Type.MT
                ) then
                    local ok, err = pcall(ApplyManualTransmissionLock, GearboxState.vehicle)
                    if not ok then print('[Gearbox][ERROR] ' .. tostring(err)) end
                end

                -- GTA 自動切換了檔位時（例如倒退、GTA 引擎行為），同步回狀態
                if activeCfg
                    and activeCfg.type == GearboxConst.Type.AT
                    and not GearboxState.isShifting
                    and not GearboxState.isNeutral
                then
                    local gtaGear = GetVehicleCurrentGear(GearboxState.vehicle)
                    local maxGear = GetActiveTransmissionMaxGear()
                    if maxGear and gtaGear > maxGear then
                        EnforceTransmissionGearLimit(GearboxState.vehicle, { maxGear = maxGear })
                        gtaGear = maxGear
                    end

                    -- AT scripted 模式下，不強制把 GTA 原生換檔打回舊檔。
                    -- 強制鎖檔已移至 UpdateAT 的換檔冷卻期間（shiftTimer），
                    -- 平時讓 GTA 物理自由加速，避免驅動力被鎖死在低檔。
                    if gtaGear > 0 and gtaGear ~= GearboxState.currentGear then
                        GearboxState.currentGear = gtaGear
                    end
                end

                -- ATMT/MT：通知外部 HUD（如 jg-hud）目前的腳本檔位
                -- GTA 原生 GetVehicleCurrentGear 因齒比鎖定而固定回傳 1，
                -- 透過 StateBag 讓 HUD 讀到正確的腳本檔位。
                if activeCfg and (
                    activeCfg.type == GearboxConst.Type.ATMT
                    or activeCfg.type == GearboxConst.Type.MT
                ) then
                    LocalPlayer.state:set('gearboxScriptGear', GearboxState.currentGear, false)
                else
                    -- AT / STOCK：GTA 原生檔位正確，清除覆蓋
                    if LocalPlayer.state.gearboxScriptGear ~= nil then
                        LocalPlayer.state:set('gearboxScriptGear', nil, false)
                    end
                end

                Wait(0)

            else
                -- 在座 + STOCK 模式（無變速箱設定）：僅監控離座，降低 CPU 占用
                _notInSeatSince = 0
                _lastFrameTime = now
                Wait(100)
            end

        else
            -- 不在車上：重設計時器，降低 CPU 占用
            _notInSeatSince = 0
            _lastFrameTime = now
            Wait(500)
        end
    end
end)

-- ── HUD 繪製循環（Wait(0) 每幀執行，獨立 Thread）─────────
CreateThread(function()
    while true do
        Wait(0)
        if GearboxState.inVehicle then
            DrawGearboxHUD()
        end
    end
end)
