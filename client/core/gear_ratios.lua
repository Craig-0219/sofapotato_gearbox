-- ═══════════════════════════════════════════════════════════════
-- client/core/gear_ratios.lua
-- 齒比系統：計算、套用、快取每檔物理數值
--
-- 職責：
--   1. 從 Config 讀取齒比，套用到 GTA handling（進車時一次）
--   2. 計算每檔頂速、扭力倍率，快取到 GB.State.perGearCache
--   3. 提供 API：GetGearTopSpeed(gear)、GetGearTorqueScale(gear)
--   4. 處理 handlingSnapshot 的讀取與備份
--
-- 不負責：每幀修改 handling（明確禁止）
-- ═══════════════════════════════════════════════════════════════

GB = GB or {}
GB.GearRatios = {}

-- ═══════════════════════════════════════════════════════════════
-- 本模組的 native 欄位名稱映射
-- ═══════════════════════════════════════════════════════════════
local RATIO_FIELD_NAMES = {
    'fGearRatioFirst', 'fGearRatioSecond', 'fGearRatioThird',
    'fGearRatioFourth', 'fGearRatioFifth', 'fGearRatioSixth',
    'fGearRatioSeventh', 'fGearRatioEighth',
}

-- ─────────────────────────────────────────────────────────────
-- GB.GearRatios.CaptureSnapshot(vehicle)
-- 進車時讀取原廠 handling 數值並存入 GB.State.handlingSnapshot
-- 讀取優先順序：Config.VehicleStockHandling > GetVehicleModelMaxSpeed > StateBag > Entity
-- ─────────────────────────────────────────────────────────────
function GB.GearRatios.CaptureSnapshot(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end

    local existing = GB.State.handlingSnapshot
    if existing and existing.vehicle == vehicle then
        return existing
    end

    local modelName = GB.State.modelName

    -- ── 原廠極速解析（km/h）──────────────────────────────────
    local maxFlatVelKmh = nil

    -- 優先：管理員手動填入的 Config
    local stockCfg = Config.VehicleStockHandling and Config.VehicleStockHandling[modelName]
    if stockCfg and type(stockCfg.maxFlatVel) == 'number' and stockCfg.maxFlatVel > 0 then
        maxFlatVelKmh = stockCfg.maxFlatVel
        -- 同步寫入 StateBag 以清除舊的損壞值
        Entity(vehicle).state:set('gbOrigMaxFlatVel', maxFlatVelKmh, false)
    end

    -- 次優：GetVehicleModelMaxSpeed（從模型資料讀，不受執行期修改影響）
    if not maxFlatVelKmh and type(GetVehicleModelMaxSpeed) == 'function' then
        local ms = GetVehicleModelMaxSpeed(GetEntityModel(vehicle))
        if type(ms) == 'number' and ms > 0 then
            maxFlatVelKmh = ms * 3.6
        end
    end

    -- StateBag 備援：驗證合理性後使用
    if not maxFlatVelKmh then
        local sb = Entity(vehicle).state['gbOrigMaxFlatVel']
        if type(sb) == 'number' and sb > 0 then
            maxFlatVelKmh = sb
        end
    end

    -- 最後備援：直接從 entity 讀（只在首次進車時可靠）
    if not maxFlatVelKmh and type(GetVehicleHandlingFloat) == 'function' then
        local raw = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel')
        if type(raw) == 'number' and raw > 0 then
            maxFlatVelKmh = raw * 3.6
        end
    end

    -- ── 原廠驅動力 ────────────────────────────────────────────
    local driveForce = nil
    if stockCfg and type(stockCfg.driveForce) == 'number' and stockCfg.driveForce > 0 then
        driveForce = stockCfg.driveForce
    end
    if not driveForce then
        local sb = Entity(vehicle).state['gbOrigDriveForce']
        if type(sb) == 'number' and sb > 0 then
            driveForce = sb
        end
    end
    if not driveForce and type(GetVehicleHandlingFloat) == 'function' then
        local raw = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce')
        if type(raw) == 'number' and raw > 0 then
            driveForce = raw
        end
    end

    -- ── 原廠齒比 ─────────────────────────────────────────────
    local nativeRatios = {}
    if type(GetVehicleGearRatio) == 'function' then
        for i = 0, 8 do
            nativeRatios[i] = GetVehicleGearRatio(vehicle, i)
        end
    end

    -- ── 原廠 highGear ────────────────────────────────────────
    local highGear = type(GetVehicleHighGear) == 'function'
        and GetVehicleHighGear(vehicle) or nil
    local driveGears = type(GetVehicleHandlingInt) == 'function'
        and GetVehicleHandlingInt(vehicle, 'CHandlingData', 'nInitialDriveGears') or nil

    local snapshot = {
        vehicle      = vehicle,
        maxFlatVelKmh = maxFlatVelKmh,  -- km/h，原廠頂速
        driveForce   = driveForce,
        gearRatios   = nativeRatios,    -- 0-indexed（GTA native）
        highGear     = highGear,
        driveGears   = driveGears,
    }

    GB.State.handlingSnapshot = snapshot

    if Config.Debug then
        print(('[GearRatios] Snapshot: model=%s maxFlatVel=%.1fkm/h driveForce=%.4f highGear=%s')
            :format(modelName, maxFlatVelKmh or -1, driveForce or -1, tostring(highGear)))
    end

    return snapshot
end

-- ─────────────────────────────────────────────────────────────
-- GB.GearRatios.BuildPerGearCache(cfg, snapshot)
-- 預算每檔頂速和扭力倍率，存入 GB.State.perGearCache
-- 只在進車或換檔型號時呼叫，不在每幀呼叫
--
-- perGearCache[gear] = {
--   topSpeedMps   : 該檔理論頂速（m/s）
--   topSpeedKmh   : 同上但 km/h（方便 debug）
--   torqueScale   : 相對於 maxGear 的扭力倍率（用於 SetVehicleEngineTorqueMultiplier）
-- }
-- ─────────────────────────────────────────────────────────────
function GB.GearRatios.BuildPerGearCache(cfg, snapshot)
    if not cfg or not cfg.gearRatios or not snapshot then
        GB.State.perGearCache = nil
        return
    end

    local baseTopKmh = snapshot.maxFlatVelKmh
    if not baseTopKmh or baseTopKmh <= 0 then
        GB.State.perGearCache = nil
        return
    end

    local ratios   = cfg.gearRatios
    local maxGear  = cfg.maxGear
    local topRatio = ratios[maxGear] or ratios[1] or 1.0

    -- 計算有效頂速的 base
    -- realistic mode: 依據 maxSpeedRatio（設定中明確指定的極速倍率）
    local effectiveTopKmh = baseTopKmh
    if type(cfg.maxSpeedRatio) == 'number' then
        -- 下限不低於原廠，避免降速
        effectiveTopKmh = baseTopKmh * math.max(1.0, cfg.maxSpeedRatio)
    end

    local cache = {}
    for g = 1, maxGear do
        local ratio = ratios[g] or 1.0
        -- 頂速公式：topGear 能跑 effectiveTopKmh，其他檔按齒比比例縮放
        -- topSpeed[g] = effectiveTopKmh × (topRatio / ratio[g])
        local gearTopKmh = effectiveTopKmh * (topRatio / ratio)
        cache[g] = {
            topSpeedKmh = gearTopKmh,
            topSpeedMps = gearTopKmh / 3.6,
            -- 扭力倍率：低檔（大齒比）扭力大
            -- GTA 的計算：torque = baseForce × ratio[g] / ratio[highGear]
            -- 但我們設 highGear = maxGear，所以 torqueScale = ratio[g] / ratio[maxGear]
            torqueScale = ratio / topRatio,
        }
    end

    GB.State.perGearCache = cache

    if Config.Debug then
        for g = 1, maxGear do
            local c = cache[g]
            print(('[GearRatios] gear=%d topSpeed=%.1fkm/h torqueScale=%.2f ratio=%.3f')
                :format(g, c.topSpeedKmh, c.torqueScale, ratios[g]))
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- GB.GearRatios.GetGearTopSpeed(gear)
-- 回傳指定檔位頂速 m/s，找不到時回傳 nil
-- ─────────────────────────────────────────────────────────────
function GB.GearRatios.GetGearTopSpeed(gear)
    local cache = GB.State.perGearCache
    if not cache then return nil end
    local entry = cache[gear]
    return entry and entry.topSpeedMps or nil
end

-- ─────────────────────────────────────────────────────────────
-- GB.GearRatios.GetGearTorqueScale(gear)
-- 回傳指定檔位的扭力倍率（相對 maxGear）
-- ─────────────────────────────────────────────────────────────
function GB.GearRatios.GetGearTorqueScale(gear)
    local cache = GB.State.perGearCache
    if not cache then return 1.0 end
    local entry = cache[gear]
    return entry and entry.torqueScale or 1.0
end

-- ─────────────────────────────────────────────────────────────
-- GB.GearRatios.ApplyToVehicle(vehicle, cfg)
-- 將 cfg 的齒比套用到 GTA（進車或換型號時呼叫，不在每幀呼叫）
-- 會修改：nInitialDriveGears、fGearRatioXxx、fInitialDriveForce、
--         fInitialDriveMaxFlatVel、SetVehicleHighGear
-- ─────────────────────────────────────────────────────────────
function GB.GearRatios.ApplyToVehicle(vehicle, cfg)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if not cfg then return end

    local snapshot = GB.State.handlingSnapshot
    if not snapshot then
        GB.GearRatios.CaptureSnapshot(vehicle)
        snapshot = GB.State.handlingSnapshot
    end

    local maxGear = cfg.maxGear
    local ratios  = cfg.gearRatios

    -- ── 1. 設定檔數 ──────────────────────────────────────────
    if type(SetVehicleHandlingInt) == 'function' then
        SetVehicleHandlingInt(vehicle, 'CHandlingData', 'nInitialDriveGears', maxGear)
    end

    -- ── 2. 設定各檔齒比 ─────────────────────────────────────
    if type(SetVehicleGearRatio) == 'function' then
        for i, ratio in ipairs(ratios) do
            SetVehicleGearRatio(vehicle, i, ratio)
        end
    end

    -- ── 3. 初始 highGear = maxGear ───────────────────────────────
    --   [FIX-D 說明] ATMT/MT 模式下，ApplyManualTruth 每幀會覆寫 highGear = currentGear，
    --   以防止 GTA AT 邏輯在「高檔低速」時把 throttleOffset 鎖為 0。
    --   AT 模式仍在 ExecuteShift → SyncATHighGear 中設定 highGear = scriptGear。
    --   此處設 maxGear 為初始值；ATMT/MT 進入第一幀 ApplyManualTruth 後即被覆蓋。
    if type(SetVehicleHighGear) == 'function' then
        SetVehicleHighGear(vehicle, maxGear)
    end

    -- ── 4. 計算並套用 fInitialDriveMaxFlatVel（固定為頂擋頂速，不按換檔縮小）──
    --   [FIX-C] 保持在 maxGear 頂速，確保任何檔位低速時 GTA naturalRpm 充足。
    --   per-gear 速度限制改由 ApplyGearSpeedLimit → SetVehicleMaxSpeed 負責。
    local cache = GB.State.perGearCache
    if not cache then
        GB.GearRatios.BuildPerGearCache(cfg, snapshot)
        cache = GB.State.perGearCache
    end

    if cache and cache[maxGear] and type(SetVehicleHandlingFloat) == 'function' then
        local topSpeedMps = cache[maxGear].topSpeedMps
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel', topSpeedMps)
        -- SetVehicleMaxSpeed 初始設為頂擋頂速；ApplyGearSpeedLimit 隨即依當前檔覆蓋
        if type(SetVehicleMaxSpeed) == 'function' then
            SetVehicleMaxSpeed(vehicle, topSpeedMps)
        end
    end

    -- ── 5. 計算並套用 fInitialDriveForce ────────────────────
    if snapshot and snapshot.driveForce and type(SetVehicleHandlingFloat) == 'function' then
        local baseForce = snapshot.driveForce

        -- realistic mode：依首檔齒比縮放驅動力
        local stockFirstRatio = snapshot.gearRatios and snapshot.gearRatios[1]
        local newFirstRatio   = ratios and ratios[1]
        local stockFinalDrive = tonumber(cfg.finalDrive) or 1.0
        local scaledForce     = baseForce

        if stockFirstRatio and stockFirstRatio > 0
            and newFirstRatio and newFirstRatio > 0
        then
            local scale = math.clamp(
                (newFirstRatio * stockFinalDrive) / (stockFirstRatio * stockFinalDrive),
                0.75, 1.45
            )
            scaledForce = baseForce * scale
        end

        SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce', scaledForce)
        -- 記錄供 clutch 切斷時還原用
        GB.State._appliedDriveForce = scaledForce
    end

    -- StateBag 廣播原廠值（跨資源重啟保護）
    if snapshot and snapshot.maxFlatVelKmh and snapshot.maxFlatVelKmh > 0 then
        Entity(vehicle).state:set('gbOrigMaxFlatVel', snapshot.maxFlatVelKmh, false)
    end
    if snapshot and snapshot.driveForce and snapshot.driveForce > 0 then
        Entity(vehicle).state:set('gbOrigDriveForce', snapshot.driveForce, false)
    end

    -- ── 6. 換檔後的 per-gear 速度限制（初始：依當前 gear）─
    GB.GearRatios.ApplyGearSpeedLimit(vehicle, GB.State.currentGear)

    if Config.Debug then
        print(('[GearRatios] Applied to vehicle %d | maxGear=%d | type=%s')
            :format(vehicle, maxGear, cfg.type))
    end
end

-- ─────────────────────────────────────────────────────────────
-- GB.GearRatios.ApplyGearSpeedLimit(vehicle, gear)
-- 換檔後呼叫一次，設定當前檔位的頂速限制
-- 不應在每幀呼叫
-- ─────────────────────────────────────────────────────────────
function GB.GearRatios.ApplyGearSpeedLimit(vehicle, gear)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local cache = GB.State.perGearCache
    if not cache or not cache[gear] then return end

    local topSpeedMps = cache[gear].topSpeedMps
    local cfg = GB.State.cfg

    -- [FIX-C] fInitialDriveMaxFlatVel 不再按檔位縮小。
    --
    -- 舊做法：每次換檔把 fInitialDriveMaxFlatVel 設成「當前檔頂速」（低檔 → 很小的值）。
    -- 問題：GTA 內部用 naturalRpm = speed / fInitialDriveMaxFlatVel 來計算驅動力。
    --       3 檔頂速 ≈ 88 km/h（24.4 m/s），在 20 km/h 時 naturalRpm = 0.228，
    --       低於 GTA 扭矩曲線有效區間，導致驅動力幾乎為零 → 車子無法加速。
    --       2 檔頂速 ≈ 61 km/h（16.9 m/s），同樣 20 km/h 時 naturalRpm = 0.330，
    --       剛好在有效區間內，所以 2 檔可以加速。這就是「2 檔沒問題、3 檔以上不行」的根本原因。
    --
    -- 新做法：fInitialDriveMaxFlatVel 固定在 maxGear 頂速（由 ApplyToVehicle 設定後不再改動）。
    --         這樣任何檔位在任何速度都有足夠的 naturalRpm，GTA 能正常輸出驅動力。
    --         每檔頂速改用 SetVehicleMaxSpeed 硬限制。
    --         （不在此處修改 fInitialDriveMaxFlatVel）

    -- SetVehicleMaxSpeed：每檔頂速硬限制（取代舊的 fInitialDriveMaxFlatVel 自然衰減）
    if type(SetVehicleMaxSpeed) == 'function' then
        SetVehicleMaxSpeed(vehicle, topSpeedMps)
    end

    -- [FIX-B] 重新確認 fInitialDriveForce（防止 GTA 或外部資源靜默修改）
    -- 只在離合器未切斷時重設，避免與 CutDriveForce(cut=true) 的 0.0001 值衝突
    local appliedForce = GB.State._appliedDriveForce
    if appliedForce and appliedForce > 0
        and not GB.State:ClutchDisengaged()
        and type(SetVehicleHandlingFloat) == 'function'
    then
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce', appliedForce)
    end

    -- 清除 dirty flag
    GB.State.speedLimitDirty = false
end

-- ─────────────────────────────────────────────────────────────
-- GB.GearRatios.RestoreSnapshot(vehicle)
-- 離車時還原 handling 到原廠值
-- ─────────────────────────────────────────────────────────────
function GB.GearRatios.RestoreSnapshot(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local snapshot = GB.State.handlingSnapshot
    if not snapshot then return end

    -- 還原 driveForce
    if snapshot.driveForce and type(SetVehicleHandlingFloat) == 'function' then
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce', snapshot.driveForce)
    end

    -- 還原 maxFlatVel
    if snapshot.maxFlatVelKmh and type(SetVehicleHandlingFloat) == 'function' then
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel',
            snapshot.maxFlatVelKmh / 3.6)
    end

    -- 還原 highGear
    if snapshot.highGear and type(SetVehicleHighGear) == 'function' then
        SetVehicleHighGear(vehicle, snapshot.highGear)
    end

    -- 還原 nInitialDriveGears
    if snapshot.driveGears and type(SetVehicleHandlingInt) == 'function' then
        SetVehicleHandlingInt(vehicle, 'CHandlingData', 'nInitialDriveGears', snapshot.driveGears)
    end

    -- 還原齒比
    if snapshot.gearRatios and type(SetVehicleGearRatio) == 'function' then
        for i, ratio in ipairs(snapshot.gearRatios) do
            SetVehicleGearRatio(vehicle, i, ratio)
        end
    end

    -- 清除 maxSpeed 限制
    if type(SetVehicleMaxSpeed) == 'function' then
        SetVehicleMaxSpeed(vehicle, 0.0)  -- 0 = 無限制
    end
end
