-- ─────────────────────────────────────────────────────
-- 漂移模式：Clutch Kick 偵測（MT 專用）
-- 離合器迅速踩下再快放 → 觸發側向衝力 + 短暫降低牽引力
-- ─────────────────────────────────────────────────────

local KICK_ENGAGE_THRESHOLD  = 0.75   -- 踩離合觸發門檻
local KICK_RELEASE_THRESHOLD = 0.15   -- 快速釋放門檻
local KICK_TIME_WINDOW_MS    = 200    -- 踩→放必須在此時間內（ms）
local TRACTION_REDUCE_RATIO  = 0.55   -- 牽引力縮至原始值的比例
local TRACTION_RESTORE_MS    = 380    -- ms 後恢復牽引力
local KICK_COOLDOWN_MS       = 900    -- 兩次 kick 最短間隔

local _kickPressed    = false
local _kickPressTime  = 0
local _kickCooldown   = 0
local _origTraction   = nil   -- 記錄原始牽引力，用於恢復

-- 每幀偵測（由 main.lua 呼叫）
function UpdateDrift(dt)
    local state = GearboxState
    if not state.inVehicle or not state.cfg then return end
    if state.cfg.type ~= GearboxConst.Type.MT then return end
    if not Config.Drift.enabled then return end

    local now = GetGameTimer()

    -- 冷卻計時
    if _kickCooldown > 0 then
        _kickCooldown = math.max(0, _kickCooldown - dt * 1000)
    end

    local clutch = state.clutchValue

    -- 偵測離合器踩下
    if clutch >= KICK_ENGAGE_THRESHOLD and not _kickPressed then
        _kickPressed  = true
        _kickPressTime = now
    end

    -- 偵測快速釋放
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
    -- 保存原始牽引力
    if not _origTraction then
        local val = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fTractionCurveLateral')
        if not val or val <= 0 then return end  -- GetVehicleHandlingFloat 可能返回 nil，防止 nil 運算崩潰
        _origTraction = val
    end

    -- 降低橫向牽引力（模擬輪胎滑移）
    local reduced = _origTraction * TRACTION_REDUCE_RATIO
    SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fTractionCurveLateral', reduced)

    -- 依轉向角決定施力方向（促進甩尾）
    -- 右向量 = 前向量旋轉 90°：(-fwd.y, fwd.x)，FiveM 無 GetEntityRightVector 原生
    local steer     = GetVehicleSteeringAngle(vehicle)
    local fwd       = GetEntityForwardVector(vehicle)
    local speed     = GetEntitySpeed(vehicle)
    local kickForce = math.min(speed * 0.045, 1.0) * Config.Drift.kickForce
    local dir       = (steer < 0) and 1 or -1  -- 反轉向角方向增強甩尾

    ApplyForceToEntity(
        vehicle, 5,
        -fwd.y * kickForce * dir,
        fwd.x * kickForce * dir,
        0.0,
        0.0, 0.0, 0.0,
        false, false, true, true, false
    )

    -- 恢復牽引力
    local origRef = _origTraction
    _origTraction = nil
    CreateThread(function()
        Wait(TRACTION_RESTORE_MS)
        if DoesEntityExist(vehicle) then
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fTractionCurveLateral', origRef)
        end
    end)

    if Config.Debug then
        print(('[Drift] Clutch kick! force=%.2f dir=%d steer=%.1f°'):format(kickForce, dir, steer))
    end
end
