-- ═══════════════════════════════════════════════════════════════
-- client/features/engine_braking.lua
-- 引擎煞車（用力模擬，不設 SetVehicleBrake 以避免卡煞車感）
-- ═══════════════════════════════════════════════════════════════

GB = GB or {}
GB.EngineBrake = {}

local COOLDOWN_MS = 250
local _lastBrakeReleaseAt = 0
local _wasBrakePressed    = false

-- ─────────────────────────────────────────────────────────────
-- GB.EngineBrake.Tick(dt)
-- ─────────────────────────────────────────────────────────────
function GB.EngineBrake.Tick(dt)
    local state  = GB.State
    local cfg    = state.cfg
    if not cfg then return end

    local vehicle  = state.vehicle
    local gear     = state.currentGear
    local speed    = state.vehicleSpeed
    local throttle = state.throttleInput
    local brakeOn  = state.brakeInput
    local now      = GetGameTimer()

    -- 更新煞車釋放計時
    if brakeOn then
        _wasBrakePressed = true
    elseif _wasBrakePressed then
        _wasBrakePressed = false
        _lastBrakeReleaseAt = now
    end

    -- 不套用引擎煞車的條件
    local skip = brakeOn
        or state.reversing
        or throttle > 0.05
        or speed < 2.0
        or state.isNeutral
        or state:ClutchDisengaged()
        or (now - _lastBrakeReleaseAt) < COOLDOWN_MS
        or (Config.EngineBrakingStrength or 0) <= 0

    if skip then return end

    -- 引擎煞車力：低檔（大齒比）煞車強
    local ratios   = cfg.gearRatios
    local topRatio = ratios and ratios[cfg.maxGear] or 1.0
    local gearRatio = ratios and ratios[gear] or 1.0

    local brakingNorm  = math.clamp(gearRatio / (topRatio * 3.5), 0.0, 1.0)
    local brakingForce = brakingNorm * (Config.EngineBrakingStrength or 0.35) * 0.06
    local forward      = GetEntityForwardVector(vehicle)

    ApplyForceToEntity(vehicle, 5,
        -forward.x * brakingForce, -forward.y * brakingForce, 0.0,
        0.0, 0.0, 0.0, false, false, true, true, false)
end
