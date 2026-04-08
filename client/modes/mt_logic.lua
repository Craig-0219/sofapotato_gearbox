-- ═══════════════════════════════════════════════════════════════
-- client/modes/mt_logic.lua
-- MT 手排完整流程
--
-- 職責：
--   - ShiftMT(direction)：玩家換檔入口（含離合器驗證）
--   - HandleNeutral()：空檔切換
--   - Tick(dt)：每幀更新（熄火檢測委託 stall.lua）
--
-- MT 換檔流程：
--   1. 驗證離合器健康 + 離合鍵
--   2. 降檔補油（rev match）
--   3. 呼叫 GB.Core.ExecuteShift
--
-- gear authority：腳本完全掌控（gearbox_core.Tick 每幀 SyncGear）
-- ═══════════════════════════════════════════════════════════════

GB = GB or {}
GB.MT = {}

-- ─────────────────────────────────────────────────────────────
-- GB.MT.Shift(direction)
-- 玩家按升/降檔鍵時呼叫
-- ─────────────────────────────────────────────────────────────
function GB.MT.Shift(direction)
    local state = GB.State
    local cfg   = state.cfg
    if not cfg or cfg.type ~= GearboxConst.Type.MT then return end
    if not state.inVehicle then return end
    if not state.engineOn  then return end
    if state.isShifting    then return end

    -- ── 離合器故障：完全無法換檔 ──────────────────────
    if GB.Clutch.IsBroken() then
        if type(exports['sp_bridge']) == 'table' then
            exports['sp_bridge']:Notify(GetLocale('ClutchBroken'), 'error')
        end
        return
    end

    -- ── 離合鍵未按：bad shift ──────────────────────────
    if not state.clutchKeyDown then
        GB.Core._HandleBadShift()
        return
    end

    local maxGear = cfg.maxGear
    local newGear = state.currentGear + direction

    -- ── 降到 1 檔以下 → 進空檔 ────────────────────────
    if direction == GearboxConst.ShiftDir.DOWN and newGear < 1 then
        if not state.isNeutral then
            GB.Core.SetNeutral(true)
        end
        return
    end

    -- ── 從空檔升檔 → 接回 1 檔 ───────────────────────
    if state.isNeutral and direction == GearboxConst.ShiftDir.UP then
        GB.Core.SetNeutral(false)
        newGear = 1
    end

    -- 邊界
    if newGear < 1 or newGear > maxGear then return end

    -- ── 降檔補油（rev match assist）─────────────────────
    if direction == GearboxConst.ShiftDir.DOWN then
        GB.RPM.DoRevMatch(state.currentGear, newGear, cfg)
    end

    -- ── 執行換檔 ──────────────────────────────────────
    GB.Core.ExecuteShift(state.currentGear, newGear, { needClutch = true })
end

-- ─────────────────────────────────────────────────────────────
-- GB.MT.Tick(dt)
-- MT 模式每幀任務（輕量）
-- 熄火偵測由 GB.Stall.Tick 負責（在主循環中呼叫）
-- ─────────────────────────────────────────────────────────────
function GB.MT.Tick(dt)
    -- gear 同步：gearbox_core.Tick 已處理
    -- clutch：clutch_engine.Tick 已處理
    -- RPM：rpm_engine.Tick 已處理
    -- stall：stall.Tick 已處理
    -- 預留：drift kick、launch control 的 MT 專屬邏輯
end
