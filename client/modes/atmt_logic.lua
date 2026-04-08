-- ═══════════════════════════════════════════════════════════════
-- client/modes/atmt_logic.lua
-- ATMT 手自排邏輯
--
-- 職責：
--   - ShiftATMT(direction)：接收玩家手動換檔請求
--   - Tick(dt)：每幀維持 gear 鎖定（SyncGear 已由 gearbox_core.Tick 處理）
--
-- 說明：
--   ATMT 模式的 gear 同步由 gearbox_core.Tick() 的 SyncGear 負責
--   本模組只負責決定何時換檔
-- ═══════════════════════════════════════════════════════════════

GB = GB or {}
GB.ATMT = {}

-- ─────────────────────────────────────────────────────────────
-- GB.ATMT.Shift(direction)
-- 玩家按升/降檔鍵時呼叫（由 input.lua 的 TriggerShift 路由過來）
-- direction: 1 = 升, -1 = 降
-- ─────────────────────────────────────────────────────────────
function GB.ATMT.Shift(direction)
    local state = GB.State
    local cfg   = state.cfg
    if not cfg or cfg.type ~= GearboxConst.Type.ATMT then return end
    if not state.inVehicle then return end
    if not state.engineOn  then return end
    if state.isShifting    then return end

    local maxGear = cfg.maxGear
    local newGear = state.currentGear + direction

    -- 邊界檢查
    if direction == GearboxConst.ShiftDir.UP   and newGear > maxGear then return end
    if direction == GearboxConst.ShiftDir.DOWN and newGear < 1       then return end

    GB.Core.ExecuteShift(state.currentGear, newGear, { needClutch = false })
end

-- ─────────────────────────────────────────────────────────────
-- GB.ATMT.Tick(dt)
-- ATMT 模式的每幀任務（目前 gear 鎖定由 gearbox_core.Tick 負責）
-- ─────────────────────────────────────────────────────────────
function GB.ATMT.Tick(dt)
    -- gearbox_core.Tick() 已處理：
    --   - SyncGear(vehicle, currentGear)  → 每幀強制同步
    --   - speedLimitDirty → ApplyGearSpeedLimit
    -- 本模組目前無額外每幀邏輯
    -- 預留 hook：
    --   - 未來可加 ATMT 特有的自動保護降檔（例如即將熄火時自動降一檔）
end
