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
-- Debug Dump（Step 2）
--
-- 手動：F8 輸入 gearbox_debug_dump
-- 自動：Config.F8GearDebug = true 且 gear >= 3、低速、油門 > 0.3
--        每 2 秒最多輸出一次（throttle），避免 log 洗版
-- ─────────────────────────────────────────────────────────────
local _debugLastDumpTime = 0

local function _GearboxDebugDump(label)
    local state   = GB.State
    local vehicle = state.vehicle
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        print('[GearboxDebug] No vehicle')
        return
    end

    local nativeState = GB.Native.GetDebugState()
    local driveForce  = type(GetVehicleHandlingFloat) == 'function'
        and GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce') or -1
    local maxFlatVel  = type(GetVehicleHandlingFloat) == 'function'
        and GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel') or -1
    local nativeGear  = type(GetVehicleCurrentGear) == 'function'
        and GetVehicleCurrentGear(vehicle) or -1
    local highGear    = type(GetVehicleHighGear) == 'function'
        and GetVehicleHighGear(vehicle) or -1
    local rpmNative   = type(GetVehicleCurrentRpm) == 'function'
        and GetVehicleCurrentRpm(vehicle) or -1
    local throttleNative = type(GetVehicleThrottleOffset) == 'function'
        and GetVehicleThrottleOffset(vehicle) or -1

    local cache    = state.perGearCache
    local g        = state.currentGear or 0
    local gearTop  = (cache and cache[g]) and (cache[g].topSpeedKmh) or -1

    print(('[GearboxDebug][%s] ── gear state ─────────────────'):format(label or 'auto'))
    print(('  scriptGear=%d  nativeGear=%d  highGear=%d  isNeutral=%s  isShifting=%s')
        :format(g, nativeGear, highGear, tostring(state.isNeutral), tostring(state.isShifting)))
    print(('  rpm_state=%.3f  rpm_native=%.3f  targetRpm=%.3f')
        :format(state.rpm or 0, rpmNative, state.targetRpm or 0))
    print(('  throttle_state=%.3f  throttle_native=%.3f  speed=%.1fkm/h  gearTopSpeed=%.1fkm/h')
        :format(state.throttleInput or 0, throttleNative, (state.vehicleSpeed or 0) * 3.6, gearTop))
    print(('  clutchKeyDown=%s  clutchAxis=%.3f  clutchDisengaged=%s')
        :format(tostring(state.clutchKeyDown), state.clutchAxis or 0, tostring(state:ClutchDisengaged())))
    print(('  driveForceCut=%s  torqueCut=%s  savedDriveForce=%s')
        :format(tostring(nativeState.clutchForceCutActive), tostring(nativeState.torqueCutActive),
                tostring(nativeState.savedDriveForce)))
    print(('  fInitialDriveForce=%.5f  _appliedDriveForce=%s  fInitialDriveMaxFlatVel=%.3fm/s(%.1fkm/h)')
        :format(driveForce, tostring(state._appliedDriveForce), maxFlatVel, maxFlatVel * 3.6))
    print(('  transmKey=%s  engineOn=%s  reversing=%s')
        :format(tostring(state.transmKey), tostring(state.engineOn), tostring(state.reversing)))
    print('[GearboxDebug] ─────────────────────────────────────')
end

-- 手動 F8 指令
RegisterCommand('gearbox_debug_dump', function()
    _GearboxDebugDump('manual')
end, false)

-- 自動觸發：低速 + 高檔 + 油門 → 每 2 秒輸出一次
local function _MaybeAutoDebug()
    if not Config.F8GearDebug then return end
    local state = GB.State
    if not state.inVehicle or not state.cfg then return end

    local gear  = state.currentGear or 0
    local speed = (state.vehicleSpeed or 0) * 3.6  -- km/h
    local thr   = state.throttleInput or 0

    if gear >= 3 and speed < 60 and thr > 0.3 then
        local now = GetGameTimer()
        if (now - _debugLastDumpTime) >= 2000 then
            _debugLastDumpTime = now
            _GearboxDebugDump(('gear%d_%.0fkmh'):format(gear, speed))
        end
    end
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

                -- ── 6.5 功能請求統一輸出（launch / drift 等）──────
                SafeCall(GB.Native.ApplyFeatureRequests, GB.State.vehicle)

                -- ── 6.6 Debug 自動觸發（Config.F8GearDebug = true 時）──
                SafeCall(_MaybeAutoDebug)

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
