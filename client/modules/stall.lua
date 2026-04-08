-- ─────────────────────────────────────────────────────
-- 熄火偵測與恢復（MT 專用）
-- ─────────────────────────────────────────────────────

local STALL_BUILD_MS    = 800   -- 持續滿足熄火條件後多久真正熄火
local STALL_SPEED_LIMIT = 5.0   -- 行駛速度超過此值不觸發熄火

-- 每幀偵測熄火條件
function UpdateStall(dt)
    local state = GearboxState
    if not state.inVehicle or not state.engineOn then return end
    if not state.cfg then return end
    if state.cfg.type ~= GearboxConst.Type.MT then return end

    local stallRpm = state.cfg.stallRpm or GearboxConst.Rpm.STALL
    local speed    = GetEntitySpeed(state.vehicle)
    local clutchCut = GetEffectiveClutch() > 0.65
    local inGear    = not state.isNeutral and state.currentGear > 0

    -- 熄火條件：轉速極低 + 有負載（在檔 + 離合器接合 + 低速）
    if state.rpm < stallRpm and inGear and not clutchCut and speed < STALL_SPEED_LIMIT then
        state.stallTimer = state.stallTimer + dt * 1000
        if state.stallTimer >= STALL_BUILD_MS then
            ExecuteStall()
        end
    else
        -- 條件解除：計時器快速歸零
        state.stallTimer = math.max(0, state.stallTimer - dt * 1200)
    end
end

-- 執行熄火
function ExecuteStall()
    local state = GearboxState
    if not state.engineOn then return end

    state.engineOn   = false
    state.stallTimer = 0
    state.rpm        = 0.0
    state.targetRpm  = 0.0

    SetVehicleEngineOn(state.vehicle, false, true, false)
    SetVehicleCurrentRpm(state.vehicle, 0.0)

    -- 廣播熄火給附近玩家
    BroadcastStall(state.vehicleNetId)

    exports['sp_bridge']:Notify(GetLocale('StallNotify'), 'error')

    if Config.Debug then
        print('[Stall] Engine stalled.')
    end
end

-- MT 未踩離合換檔→嘗試觸發熄火（由 gearbox.lua 呼叫）
-- 回傳 true 代表已熄火（換檔流程應中止）
function TryStallFromShiftAbuse()
    local state = GearboxState
    if not state.cfg then return false end

    local chance = state.cfg.stallChance or 0.0
    if math.random() < chance then
        ExecuteStall()
        return true
    end
    return false
end
