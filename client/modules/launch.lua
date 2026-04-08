-- ─────────────────────────────────────────────────────
-- 起步控制（Launch Control）
-- 適用：AT / ATMT / MT
-- 啟動：AT/ATMT — 全油門 + 全煞車 + 靜止
--        MT     — 離合器踩下 + 全油門 + 全煞車 + 靜止
-- 觸發：鬆開煞車 → 爆發起步
-- MT 說明：MT 模式玩家自行控制離合器，就位後鬆煞車即觸發，
--          離合器放開時機由玩家決定（鬆離合器=全力輸出）
-- ─────────────────────────────────────────────────────

-- INPUT_VEH_BRAKE = 72
local BRAKE_CTRL   = 72
local _prepped     = false  -- 已就位等待起步
local _active      = false  -- 起步中
local _blazeEnd    = 0      -- 全力時間窗口結束時間（ms）

local function IsEligible()
    local state = GearboxState
    local cfg = GetActiveTransmissionConfig() or state.cfg
    if not cfg then return false end
    if not Config.Launch.enabled then return false end
    return cfg.type == GearboxConst.Type.AT
        or cfg.type == GearboxConst.Type.ATMT
        or cfg.type == GearboxConst.Type.MT
end

-- 每幀更新（由 main.lua 呼叫）
function UpdateLaunchControl(dt)
    local state   = GearboxState
    local vehicle = state.vehicle

    if not state.inVehicle or not IsEligible() then
        _prepped = false
        _active  = false
        state.launchActive  = false
        state.launchPrepped = false
        return
    end

    local now      = GetGameTimer()
    local speed    = GetEntitySpeed(vehicle)
    -- 備援：GetVehicleThrottleOffset 靜止時可能回傳 0（GTA 無法施力），
    -- 加入原始按鍵輸入取最大值，確保靜止狀態下能正確偵測油門輸入
    local throttle = math.max(0.0, GetVehicleThrottleOffset(vehicle), GetControlNormal(0, 71))
    local brakeOn  = IsControlPressed(0, BRAKE_CTRL)
    local isMT     = state.cfg and state.cfg.type == GearboxConst.Type.MT

    -- ── 就位條件 ──────────────────────────────────────
    -- AT/ATMT：全油門 + 全煞車 + 幾乎靜止
    -- MT：     離合器踩下 + 全油門 + 全煞車 + 幾乎靜止（離合器踩下才能預熱轉速不熄火）
    if not _prepped and not _active then
        local armCondition = throttle > 0.90 and brakeOn and speed < 1.5 and state.engineOn
        local clutchReady  = not isMT or state.clutchKeyDown
        if armCondition and clutchReady then
            _prepped = true
            if Config.Debug then
                print('[Launch] Armed' .. (isMT and ' (MT)' or ''))
            end
        end
    end

    -- ── 鎖定起步 RPM ──────────────────────────────────
    if _prepped and not _active then
        local lrpm = Config.Launch.launchRpm
        SetVehicleCurrentRpm(vehicle, lrpm)
        state.rpm       = lrpm
        state.targetRpm = lrpm

        -- 鬆煞車 → 發射
        if not brakeOn then
            _prepped  = false
            _active   = true
            _blazeEnd = now + Config.Launch.blazeWindowMs
            if Config.Debug then print('[Launch] LAUNCH!') end
        end

        -- 鬆油門取消
        if throttle < 0.50 then
            _prepped = false
            if Config.Debug then print('[Launch] Aborted (throttle released)') end
        end

        -- MT：離合器放開取消（離合器放開會讓引擎帶動傳動，無法維持就位狀態）
        if isMT and not state.clutchKeyDown then
            _prepped = false
            if Config.Debug then print('[Launch] Aborted (MT clutch released)') end
        end
    end

    -- ── 起步爆發窗口：鎖住 1 檔全力 ─────────────────
    if _active then
        if now <= _blazeEnd and state.engineOn then
            -- 確保在 1 檔
            if state.currentGear ~= 1 and not state.isShifting then
                state.currentGear = 1
                SetVehicleCurrentGear(vehicle, 1)
            end
        else
            _active = false
        end

        -- 速度過高或引擎熄火則退出
        if speed > 25.0 or not state.engineOn then
            _active = false
        end
    end

    -- 同步到 State（供 HUD 讀取）
    state.launchActive  = _active
    state.launchPrepped = _prepped
end

-- 手動取消
RegisterCommand('gearbox_launch_cancel', function()
    _prepped = false
    _active  = false
    GearboxState.launchActive  = false
    GearboxState.launchPrepped = false
end, false)

RegisterKeyMapping('gearbox_launch_cancel', Config.Keys.LaunchCancel.label,
    'keyboard', Config.Keys.LaunchCancel.default)
