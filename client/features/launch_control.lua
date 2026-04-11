-- ═══════════════════════════════════════════════════════════════
-- client/features/launch_control.lua
-- Launch Control（feature layer）
-- 只提交 request，不直接寫 drivetrain native。
-- ═══════════════════════════════════════════════════════════════

local BRAKE_CTRL   = 72
local _prepped     = false
local _active      = false
local _blazeEnd    = 0

local function IsEligible()
    local state = GearboxState
    local cfg = GetActiveTransmissionConfig() or state.cfg
    if not cfg then return false end
    if not Config.Launch.enabled then return false end
    return cfg.type == GearboxConst.Type.AT
        or cfg.type == GearboxConst.Type.ATMT
        or cfg.type == GearboxConst.Type.MT
end

function UpdateLaunchControl(dt)
    local state   = GearboxState
    local vehicle = state.vehicle

    if not state.inVehicle or not IsEligible() then
        _prepped = false
        _active  = false
        state.launchActive  = false
        state.launchPrepped = false
        GB.Native.SetFeatureRpmOverride('launch', nil)
        GB.Native.SetFeatureGearLock('launch', nil)
        return
    end

    local now      = GetGameTimer()
    local speed    = GetEntitySpeed(vehicle)
    local throttle = math.max(0.0, GetVehicleThrottleOffset(vehicle), GetControlNormal(0, 71))
    local brakeOn  = IsControlPressed(0, BRAKE_CTRL)
    local isMT     = state.cfg and state.cfg.type == GearboxConst.Type.MT

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

    if _prepped and not _active then
        GB.Native.SetFeatureRpmOverride('launch', Config.Launch.launchRpm)

        if not brakeOn then
            _prepped  = false
            _active   = true
            _blazeEnd = now + Config.Launch.blazeWindowMs
            if Config.Debug then print('[Launch] LAUNCH!') end
        end

        if throttle < 0.50 then
            _prepped = false
            if Config.Debug then print('[Launch] Aborted (throttle released)') end
        end

        if isMT and not state.clutchKeyDown then
            _prepped = false
            if Config.Debug then print('[Launch] Aborted (MT clutch released)') end
        end
    end

    if _active then
        if now <= _blazeEnd and state.engineOn then
            if state.currentGear ~= 1 and not state.isShifting then
                state.currentGear = 1
                GB.Native.SetFeatureGearLock('launch', 1)
            end
        else
            _active = false
        end

        if speed > 25.0 or not state.engineOn then
            _active = false
        end
    end

    state.launchActive  = _active
    state.launchPrepped = _prepped

    if not _prepped then
        GB.Native.SetFeatureRpmOverride('launch', nil)
    end
    if not _active then
        GB.Native.SetFeatureGearLock('launch', nil)
    end
end

RegisterCommand('gearbox_launch_cancel', function()
    _prepped = false
    _active  = false
    GearboxState.launchActive  = false
    GearboxState.launchPrepped = false
    GB.Native.SetFeatureRpmOverride('launch', nil)
    GB.Native.SetFeatureGearLock('launch', nil)
end, false)

RegisterKeyMapping('gearbox_launch_cancel', Config.Keys.LaunchCancel.label,
    'keyboard', Config.Keys.LaunchCancel.default)
