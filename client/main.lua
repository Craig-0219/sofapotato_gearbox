-- ═══════════════════════════════════════════════════════════════
-- client/main.lua
-- Client 入口：車輛偵測、主循環
--
-- 架構說明：
--   新核心（GB.*）負責 gear/rpm/clutch 的計算與 native 同步
--   舊模組（modules/）的 HUD、menu、sounds、drift、launch、damage、upgrade 繼續運作
--   GearboxState = GB.State（alias）確保舊模組的讀寫直接作用在 GB.State
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 相容性橋接：舊 API 路由到新核心
-- input.lua 呼叫 TriggerShift / ToggleNeutral，這裡重定向
-- ─────────────────────────────────────────────────────────────
function TriggerShift(direction)
    local state = GB.State
    local cfg   = state.cfg
    if not state.inVehicle or not cfg then return end
    if not state.engineOn then return end
    if state.isShifting   then return end

    if     cfg.type == GearboxConst.Type.ATMT then GB.ATMT.Shift(direction)
    elseif cfg.type == GearboxConst.Type.MT   then GB.MT.Shift(direction)
    -- AT 不接受手動換檔，無動作
    end
end

function ToggleNeutral()
    local state = GB.State
    if not state.inVehicle then return end
    local cfg = state.cfg
    if not cfg or cfg.type ~= GearboxConst.Type.MT then return end
    GB.Core.ToggleNeutral()
end

function SetNeutral(toNeutral)
    GB.Core.SetNeutral(toNeutral)
end

-- 舊 gearbox.lua 的 ChangeTransmission 路由
function ChangeTransmission(key)
    GB.Core.ChangeTransmission(key)
    -- 舊的持久化事件仍在 state 初始化/離車時觸發，不需要在這裡重複
end

-- 取得當前有效 cfg（舊模組呼叫）
function GetActiveTransmissionConfig()
    return GB.State.cfg
end

function GetActiveTransmissionMaxGear()
    return GB.State.cfg and GB.State.cfg.maxGear or nil
end

-- ─────────────────────────────────────────────────────────────
-- 車輛進入偵測（500ms 輪詢）
-- ─────────────────────────────────────────────────────────────
local _wasInVehicle = false

CreateThread(function()
    while true do
        Wait(500)
        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local inVehicle = vehicle ~= 0
            and GetPedInVehicleSeat(vehicle, -1) == ped

        if inVehicle and not GB.State.inVehicle then
            _OnEnterVehicle(vehicle)
        end

        _wasInVehicle = inVehicle
    end
end)

-- ─────────────────────────────────────────────────────────────
-- _OnEnterVehicle(vehicle)
-- ─────────────────────────────────────────────────────────────
function _OnEnterVehicle(vehicle)
    -- 初始化狀態（同時設定 GearboxState alias）
    GB.State.Init(vehicle)

    -- 讀取 handling snapshot
    GB.GearRatios.CaptureSnapshot(vehicle)

    -- 解析傳動型號
    local modelName = GB.State.modelName
    local transmKey = Config.VehicleTransmissions and Config.VehicleTransmissions[modelName]

    if transmKey and Config.Transmissions and Config.Transmissions[transmKey] then
        GB.Core.ChangeTransmission(transmKey)
    else
        -- STOCK：不套用自訂 handling
        GB.State.transmKey = 'STOCK'
        GB.State.cfg       = nil
    end

    -- 向 server 請求持久化資料
    TriggerServerEvent(GearboxConst.Events.LOAD_SETTINGS, {
        vehicleNetId = GB.State.vehicleNetId,
        modelName    = GB.State.modelName,
        vehiclePlate = GB.State.vehiclePlate,
    })

    if Config.Debug then
        print(('[Main] Entered vehicle %d | model=%s transm=%s')
            :format(vehicle, GB.State.modelName, GB.State.transmKey))
    end
end

-- ─────────────────────────────────────────────────────────────
-- _OnExitVehicle()
-- ─────────────────────────────────────────────────────────────
function _OnExitVehicle()
    local vehicle = GB.State.vehicle

    -- 清除 StateBag
    LocalPlayer.state:set('gearboxScriptGear', nil, false)

    -- 儲存設定到 server
    if GB.State.vehicleNetId ~= 0 then
        TriggerServerEvent(GearboxConst.Events.SAVE_SETTINGS, {
            vehicleNetId  = GB.State.vehicleNetId,
            vehicleModel  = GB.State.modelName,
            vehiclePlate  = GB.State.vehiclePlate,
            transmKey     = GB.State.transmKey,
            clutchHealth  = GB.State.clutchHealth,
        })
    end

    -- 還原 handling
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        GB.GearRatios.RestoreSnapshot(vehicle)
    end

    -- 重設 native_adapter 內部狀態
    GB.Native.Reset()

    -- 重設 state
    GB.State.Reset()

    if Config.Debug then print('[Main] Exited vehicle') end
end

-- ─────────────────────────────────────────────────────────────
-- 資源停止時還原 handling
-- ─────────────────────────────────────────────────────────────
AddEventHandler('onClientResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    local vehicle = GB.State.vehicle
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        GB.GearRatios.RestoreSnapshot(vehicle)
    end
end)

-- ─────────────────────────────────────────────────────────────
-- 主循環
-- ─────────────────────────────────────────────────────────────
local _lastFrameTime    = GetGameTimer()
local _notInSeatSince   = 0
local NOT_IN_SEAT_DEBOUNCE_MS = 1000

local function SafeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then print('[Gearbox][ERROR] ' .. tostring(err)) end
end

CreateThread(function()
    while true do
        local now = GetGameTimer()

        if GB.State.inVehicle then
            local ped    = PlayerPedId()
            local inSeat = DoesEntityExist(GB.State.vehicle)
                and GetPedInVehicleSeat(GB.State.vehicle, -1) == ped

            if not inSeat then
                -- 防抖離座偵測
                if _notInSeatSince == 0 then
                    _notInSeatSince = now
                elseif (now - _notInSeatSince) >= NOT_IN_SEAT_DEBOUNCE_MS then
                    _notInSeatSince = 0
                    _OnExitVehicle()
                end
                _lastFrameTime = now
                Wait(50)

            elseif GB.State.cfg then
                -- 在座 + 有變速箱設定：每幀物理更新
                _notInSeatSince = 0
                local dt = math.min((now - _lastFrameTime) / 1000.0, 0.10)
                _lastFrameTime = now

                -- ── 1. 讀取所有輸入 ────────────────────────
                SafeCall(GB.State.ReadInputs)

                -- ── 2. 離合器 ──────────────────────────────
                SafeCall(GB.Clutch.Tick, dt)

                -- ── 3. RPM 引擎 ────────────────────────────
                -- AT：直讀 native（不寫回）
                -- ATMT/MT：計算 + SetVehicleCurrentRpm
                SafeCall(GB.RPM.Tick, dt)

                -- ── 4. 核心 Tick（gear 同步 + dirty flags）
                SafeCall(GB.Core.Tick, dt)

                -- ── 5. 模式邏輯 ────────────────────────────
                local cfg = GB.State.cfg
                if cfg then
                    if cfg.type == GearboxConst.Type.AT then
                        SafeCall(GB.AT.Tick, dt)
                    elseif cfg.type == GearboxConst.Type.ATMT then
                        SafeCall(GB.ATMT.Tick, dt)
                    elseif cfg.type == GearboxConst.Type.MT then
                        SafeCall(GB.MT.Tick, dt)
                    end
                end

                -- ── 6. 功能模組 ────────────────────────────
                SafeCall(GB.Stall.Tick, dt)
                SafeCall(GB.EngineBrake.Tick, dt)

                -- 舊功能模組（仍使用 GearboxState，但 alias 指向 GB.State）
                SafeCall(UpdateTemperature, dt)  -- modules/damage.lua
                SafeCall(UpdateDrift, dt)        -- modules/drift.lua
                SafeCall(UpdateLaunchControl, dt) -- modules/launch.lua

                -- ── 7. StateBag 廣播（ATMT/MT 的腳本檔位給外部 HUD）
                if cfg and (cfg.type == GearboxConst.Type.ATMT
                    or cfg.type == GearboxConst.Type.MT)
                then
                    LocalPlayer.state:set('gearboxScriptGear', GB.State.currentGear, false)
                else
                    -- AT/STOCK：清除覆蓋，讓外部 HUD 讀原生
                    if LocalPlayer.state.gearboxScriptGear ~= nil then
                        LocalPlayer.state:set('gearboxScriptGear', nil, false)
                    end
                end

                Wait(0)

            else
                -- 在座 + STOCK 模式：只監控離座
                _notInSeatSince = 0
                _lastFrameTime  = now
                Wait(100)
            end

        else
            _notInSeatSince = 0
            _lastFrameTime  = now
            Wait(500)
        end
    end
end)

-- ─────────────────────────────────────────────────────────────
-- HUD 繪製循環（獨立 Thread）
-- ─────────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(0)
        if GB.State.inVehicle then
            -- DrawGearboxHUD 仍讀 GearboxState（= GB.State），無需修改
            if type(DrawGearboxHUD) == 'function' then
                DrawGearboxHUD()
            end
        end
    end
end)
