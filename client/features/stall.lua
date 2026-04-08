-- ═══════════════════════════════════════════════════════════════
-- client/features/stall.lua
-- 熄火偵測與執行（MT 專用）
-- ═══════════════════════════════════════════════════════════════

GB = GB or {}
GB.Stall = {}

local STALL_BUILD_MS    = 800   -- 持續滿足條件後多久真正熄火
local STALL_SPEED_LIMIT = 5.0   -- 行駛速度超過此值不觸發熄火

-- ─────────────────────────────────────────────────────────────
-- GB.Stall.Tick(dt)
-- ─────────────────────────────────────────────────────────────
function GB.Stall.Tick(dt)
    local state = GB.State
    if not state.inVehicle or not state.engineOn then return end
    if not state.cfg or not state:IsMTMode() then return end

    local stallRpm  = state.cfg.stallRpm or GearboxConst.Rpm.STALL
    local speed     = state.vehicleSpeed
    local clutchCut = state:ClutchDisengaged()
    local inGear    = not state.isNeutral and state.currentGear > 0

    -- 熄火條件：低轉 + 有負載（在檔 + 離合接合 + 低速）
    if state.rpm < stallRpm and inGear and not clutchCut and speed < STALL_SPEED_LIMIT then
        state.stallTimer = state.stallTimer + dt * 1000
        if state.stallTimer >= STALL_BUILD_MS then
            GB.Stall.Execute()
        end
    else
        -- 條件解除：計時器快速歸零
        state.stallTimer = math.max(0, state.stallTimer - dt * 1200)
    end
end

-- ─────────────────────────────────────────────────────────────
-- GB.Stall.Execute()
-- ─────────────────────────────────────────────────────────────
function GB.Stall.Execute()
    local state = GB.State
    if not state.engineOn then return end

    state.engineOn   = false
    state.stallTimer = 0
    state.rpm        = 0.0
    state.targetRpm  = 0.0

    GB.Native.SetEngineOn(state.vehicle, false)
    GB.Native.SyncRpm(state.vehicle, 0.0)

    if type(BroadcastStall) == 'function' then
        BroadcastStall(state.vehicleNetId)
    end

    if type(exports['sp_bridge']) == 'table' then
        exports['sp_bridge']:Notify(GetLocale('StallNotify'), 'error')
    end

    if Config.Debug then print('[Stall] Engine stalled.') end
end

-- ─────────────────────────────────────────────────────────────
-- GB.Stall.TryStallFromAbuse()
-- MT 未踩離合換檔 → 機率觸發熄火
-- ─────────────────────────────────────────────────────────────
function GB.Stall.TryStallFromAbuse()
    local state  = GB.State
    local chance = state.cfg and state.cfg.stallChance or 0.0
    if math.random() < chance then
        GB.Stall.Execute()
        return true
    end
    return false
end
