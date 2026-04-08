-- ─────────────────────────────────────────────────────
-- 離合器深度計算與磨損觸發
-- ─────────────────────────────────────────────────────

-- 線性插值
function Lerp(a, b, t)
    return a + (b - a) * math.min(1.0, t)
end

-- 每幀更新離合器狀態
function UpdateClutch(dt)
    local state = GearboxState
    if not state.cfg then return end

    -- AT / ATMT：系統自動控制，玩家無需操作
    if state.cfg.type ~= GearboxConst.Type.MT then
        state.clutchValue = 0.0
        UpdateManualClutchDriveForce(state.vehicle, false)
        UpdateManualClutchTorque(state.vehicle, false)
        return
    end

    -- MT：每幀封鎖 GTA 原生 INPUT_DUCK（Left Ctrl），
    -- 防止 GTA 在快速點按時消費 key-up 事件，導致 -gearbox_clutch 指令遺失而卡鍵。
    DisableControlAction(0, 36, true)

    -- 看門狗：若指令狀態為「按下」但實際按鍵已放開，強制重設。
    -- 僅用於重設，不用於設定——不會將 clutchKeyDown 誤觸設為 true。
    if state.clutchKeyDown and not IsDisabledControlPressed(0, 36) then
        state.clutchKeyDown = false
    end

    -- MT：鍵盤為數位輸入（0/1），直接設定離合器狀態
    local prevValue   = state.clutchValue
    state.clutchValue = (state.isNeutral or state.clutchKeyDown) and 1.0 or 0.0

    -- 套用到 GTA
    -- GTA native: 0.0 = 離合器切斷（無動力），1.0 = 離合器接合（全力）
    -- clutchValue 語意相反（1.0 = 踩到底），故需取反
    local effective = GetEffectiveClutch()
    if DoesEntityExist(state.vehicle) then
        SetVehicleClutch(state.vehicle, 1.0 - effective)
    end
    local clutchCut = state.isNeutral or state.clutchKeyDown
    UpdateManualClutchDriveForce(state.vehicle, clutchCut)
    UpdateManualClutchTorque(state.vehicle, clutchCut)

    -- 偵測猛放離合器（從踩下狀態直接放開且車輛在移動）
    local wasDumped = prevValue >= 1.0 and state.clutchValue < 1.0
        and not state.clutchKeyDown
        and GetEntitySpeed(state.vehicle) > 1.0
    if wasDumped then
        WearClutch(Config.Clutch.wearDump)
        if Config.Temperature.enabled then
            state.gearboxTemp = state.gearboxTemp + Config.Temperature.shiftAbuseRise
        end
    end

    -- 鍵盤無半離合，清除滑動累積
    state.clutchSlipAccum = 0.0
end

-- 取得有效離合器深度（磨損後效能衰退）
function GetEffectiveClutch()
    local healthFactor = GearboxState.clutchHealth / 100.0
    return GearboxState.clutchValue * healthFactor
end

-- 取得離合器狀態分類（鍵盤為二元狀態，無 SLIPPING 過渡）
function GetClutchStateEnum()
    if GearboxState.clutchValue < 1.0 then
        return GearboxConst.ClutchState.ENGAGED
    else
        return GearboxConst.ClutchState.DISENGAGED
    end
end
