-- ═══════════════════════════════════════════════════════════════
-- client/features/drift.lua
-- Drift / clutch-kick（feature layer）
-- traction 只透過 feature request 改寫。
-- ═══════════════════════════════════════════════════════════════

local KICK_ENGAGE_THRESHOLD  = 0.75
local KICK_RELEASE_THRESHOLD = 0.15
local KICK_TIME_WINDOW_MS    = 200
local TRACTION_REDUCE_RATIO  = 0.55
local TRACTION_RESTORE_MS    = 380
local KICK_COOLDOWN_MS       = 900

local _kickPressed       = false
local _kickPressTime     = 0
local _kickCooldown      = 0
local _tractionRestoreAt = 0

function UpdateDrift(dt)
    local state = GearboxState
    if not state.inVehicle or not state.cfg
        or state.cfg.type ~= GearboxConst.Type.MT
        or not Config.Drift.enabled
    then
        GB.Native.SetFeatureTractionScale('drift', nil)
        _tractionRestoreAt = 0
        return
    end

    local now = GetGameTimer()
    if _kickCooldown > 0 then
        _kickCooldown = math.max(0, _kickCooldown - dt * 1000)
    end

    if _tractionRestoreAt > 0 and now >= _tractionRestoreAt then
        GB.Native.SetFeatureTractionScale('drift', nil)
        _tractionRestoreAt = 0
    end

    local clutch = state.clutchAxis or state.clutchValue or 0.0

    if clutch >= KICK_ENGAGE_THRESHOLD and not _kickPressed then
        _kickPressed  = true
        _kickPressTime = now
    end

    if _kickPressed and clutch < KICK_RELEASE_THRESHOLD then
        local elapsed = now - _kickPressTime
        _kickPressed  = false

        if elapsed <= KICK_TIME_WINDOW_MS
            and _kickCooldown <= 0
            and not state.isNeutral
            and state.currentGear > 0
            and GetEntitySpeed(state.vehicle) > 5.0
        then
            ExecuteClutchKick(state.vehicle)
            _kickCooldown = KICK_COOLDOWN_MS
        end
    end
end

function ExecuteClutchKick(vehicle)
    GB.Native.SetFeatureTractionScale('drift', TRACTION_REDUCE_RATIO)
    _tractionRestoreAt = GetGameTimer() + TRACTION_RESTORE_MS

    local steer     = GetVehicleSteeringAngle(vehicle)
    local fwd       = GetEntityForwardVector(vehicle)
    local speed     = GetEntitySpeed(vehicle)
    local kickForce = math.min(speed * 0.045, 1.0) * Config.Drift.kickForce
    local dir       = (steer < 0) and 1 or -1

    ApplyForceToEntity(
        vehicle, 5,
        -fwd.y * kickForce * dir,
        fwd.x * kickForce * dir,
        0.0,
        0.0, 0.0, 0.0,
        false, false, true, true, false
    )

    if Config.Debug then
        print(('[Drift] Clutch kick! force=%.2f dir=%d steer=%.1f°'):format(kickForce, dir, steer))
    end
end
