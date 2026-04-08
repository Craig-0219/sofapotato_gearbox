-- ═══════════════════════════════════════════════════════════════
-- client/core/clutch_engine.lua
-- 離合器引擎
--
-- 職責：
--   - 每幀更新 clutchAxis（鍵盤二元 / 未來可擴展類比）
--   - 呼叫 GB.Native.SyncClutch + CutDriveForce + SyncTorqueCut
--   - 離合器磨損觸發（猛放、半離合累積）
--
-- 設計原則：
--   clutchAxis 語義：0.0 = 放開（動力接合），1.0 = 踩下（動力切斷）
--   GTA native 語義相反，轉換在 native_adapter 中完成
--
-- 未來擴展：
--   - 類比輸入：讀搖桿軸，0.0~1.0 連續值（替換 clutchKeyDown 邏輯）
--   - 半離合模擬：clutchAxis 0.3~0.7 時 driveForce = baseForce * (1.0 - axis)
-- ═══════════════════════════════════════════════════════════════

GB = GB or {}
GB.Clutch = {}

-- ─────────────────────────────────────────────────────────────
-- GB.Clutch.Tick(dt)
-- 每幀更新離合器狀態
-- ─────────────────────────────────────────────────────────────
function GB.Clutch.Tick(dt)
    local state = GB.State
    if not state.cfg then return end

    local vehicle = state.vehicle

    -- AT / ATMT：系統自動控制離合，玩家無需操作
    if not state:IsMTMode() then
        state.clutchAxis = 0.0  -- 永遠接合
        GB.Native.SyncTorqueCut(vehicle, false)
        GB.Native.CutDriveForce(vehicle, false)
        return
    end

    -- ── MT 模式 ──────────────────────────────────────────

    -- 封鎖 GTA 原生 INPUT_DUCK（Left Ctrl）
    -- 防止 GTA 在快速點按時消費 key-up 事件，導致 +gearbox_clutch 指令遺失
    DisableControlAction(0, 36, true)

    -- 看門狗：若 clutchKeyDown 為 true 但按鍵已放開，強制重設
    -- 只用於重設，不會誤觸設為 true
    if state.clutchKeyDown and not IsDisabledControlPressed(0, 36) then
        state.clutchKeyDown = false
    end

    -- 鍵盤為二元輸入：按下 = 1.0，放開 = 0.0
    -- 未來類比輸入：直接讀搖桿軸值（此處只需替換這一行）
    local prevAxis       = state.clutchAxis
    state.clutchAxis     = (state.isNeutral or state.clutchKeyDown) and 1.0 or 0.0

    -- ── 有效離合器軸位（考慮磨損）──────────────────────
    local effectiveAxis  = state:EffectiveClutchAxis()
    local clutchCut      = effectiveAxis >= 0.65  -- 超過此門檻才算真正切斷

    -- ── 同步到 GTA native ───────────────────────────────
    GB.Native.SyncClutch(vehicle, effectiveAxis)
    GB.Native.SyncTorqueCut(vehicle, clutchCut)
    GB.Native.CutDriveForce(vehicle, clutchCut)

    -- ── 磨損偵測：猛放離合器 ────────────────────────────
    -- 條件：上一幀完全踩下（1.0）→ 這幀放開（< 1.0）+ 車有在移動
    local wasDumped = prevAxis >= 1.0
        and state.clutchAxis < 1.0
        and not state.clutchKeyDown
        and state.vehicleSpeed > 1.0

    if wasDumped then
        GB.Clutch.Wear(Config.Clutch and Config.Clutch.wearDump or 0.50)
        if Config.Temperature and Config.Temperature.enabled then
            state.gearboxTemp = state.gearboxTemp + (Config.Temperature.shiftAbuseRise or 0.8)
        end
    end

    -- ── 鍵盤模式無半離合，清除累積 ────────────────────
    -- 未來類比模式：在這裡根據 0.3~0.7 範圍累積 clutchSlipSec
    state.clutchSlipSec = 0.0
end

-- ─────────────────────────────────────────────────────────────
-- GB.Clutch.Wear(amount)
-- 降低離合器耐久度
-- ─────────────────────────────────────────────────────────────
function GB.Clutch.Wear(amount)
    local state = GB.State
    state.clutchHealth = math.max(0.0, state.clutchHealth - amount)
    if Config.Debug then
        print(('[Clutch] Wear %.2f → health=%.1f'):format(amount, state.clutchHealth))
    end
end

-- ─────────────────────────────────────────────────────────────
-- GB.Clutch.WearOnShift(isBadShift)
-- 換檔時的磨損（由 gearbox_core.ExecuteShift 呼叫）
-- ─────────────────────────────────────────────────────────────
function GB.Clutch.WearOnShift(isBadShift)
    if not Config.Clutch then return end
    local amount = isBadShift
        and (Config.Clutch.wearHalf or 0.20)
        or  (Config.Clutch.wearNormal or 0.05)
    GB.Clutch.Wear(amount)
end

-- ─────────────────────────────────────────────────────────────
-- GB.Clutch.IsBroken()
-- ─────────────────────────────────────────────────────────────
function GB.Clutch.IsBroken()
    return GB.State.clutchHealth <= (GearboxConst.ClutchHealth.BROKEN or 0.0)
end

-- ─────────────────────────────────────────────────────────────
-- GB.Clutch.GetState()
-- 回傳離合器狀態枚舉（ENGAGED / SLIPPING / DISENGAGED）
-- ─────────────────────────────────────────────────────────────
function GB.Clutch.GetState()
    local axis = GB.State.clutchAxis
    if axis < 0.30 then
        return GearboxConst.ClutchState.ENGAGED
    elseif axis < 0.70 then
        return GearboxConst.ClutchState.SLIPPING
    else
        return GearboxConst.ClutchState.DISENGAGED
    end
end
