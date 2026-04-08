-- ─────────────────────────────────────────────────────
-- 全域狀態表（所有 client 模組共用同一 Lua 狀態）
-- ─────────────────────────────────────────────────────

-- math.clamp 不在 Lua 5.4 標準庫，這裡補上
math.clamp = math.clamp or function(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

GearboxState = {
    -- 車輛
    vehicle       = 0,
    vehicleNetId  = 0,
    modelName     = '',
    vehiclePlate  = '*',
    inVehicle     = false,

    -- 變速箱設定
    transmKey     = '',
    cfg           = nil,
    runtimeCfg    = nil,

    -- 檔位
    currentGear   = 1,
    isNeutral     = false,
    isShifting    = false,
    shiftTimer    = 0,

    -- 離合器
    clutchKeyDown = false,
    clutchValue   = 0.0,   -- 0.0=放開 1.0=完全踩下
    clutchHealth  = 100.0, -- 0 ~ 100
    clutchSlipAccum = 0.0, -- 半離合累積秒數（計算磨損用）

    -- 轉速
    rpm           = 0.12,
    targetRpm     = 0.12,

    -- 引擎
    engineOn      = false,
    stallTimer    = 0,     -- 熄火風險累積 ms

    -- 物理追蹤
    lastThrottle  = 0.0,
    lastSpeed     = 0.0,

    -- 溫度
    gearboxTemp   = 20.0,  -- °C

    -- 渦輪
    turboBoost    = 0.0,

    -- 輔助功能（玩家可切換）
    antiStall     = false,
    revMatch      = false,
    driftEnabled  = true,   -- Clutch Kick 漂移模式（MT 預設開）

    -- 起步控制（由 launch.lua 寫入，hud.lua 讀取）
    launchActive  = false,
    launchPrepped = false,

    -- 解鎖的變速箱型號清單（從 server 載入）
    unlockedTransmissions = {},

    -- 原始 Handling 備份（進車後覆蓋、離車時還原）
    handlingBackup = nil,
    handlingOverrides = nil,
    driveForceCutActive = false,
    torqueCutActive = false,
}

-- ─────────────────────────────────────────────────────
-- 齒比對應的 Handling 欄位名稱
-- ─────────────────────────────────────────────────────
local GEAR_RATIO_FIELDS = {
    'fGearRatioFirst', 'fGearRatioSecond', 'fGearRatioThird',
    'fGearRatioFourth', 'fGearRatioFifth', 'fGearRatioSixth',
    'fGearRatioSeventh', 'fGearRatioEighth',
}
local FLOAT_HANDLING_FIELDS = {
    'fInitialDriveMaxFlatVel',
    'fInitialDriveForce',
}

local MAX_GEAR_RATIO_SLOTS = 8
local STOCK_TRANSMISSION_KEY = 'STOCK'
local SET_VEHICLE_MAX_GEAR_NATIVE = 2300828994
local SET_VEHICLE_HIGH_GEAR_NATIVE = 977626868
local GEAR_RATIO_FIELD_INDEX = {}
local FLOAT_HANDLING_FIELD_SET = {}
local NormalizeHandlingOverrides
local CaptureVehicleHandlingBackup

for index, fieldName in ipairs(GEAR_RATIO_FIELDS) do
    GEAR_RATIO_FIELD_INDEX[fieldName] = index
end

for _, fieldName in ipairs(FLOAT_HANDLING_FIELDS) do
    FLOAT_HANDLING_FIELD_SET[fieldName] = true
end

function GetStockTransmissionKey()
    return STOCK_TRANSMISSION_KEY
end

function IsStockTransmissionKey(transmKey)
    if transmKey == nil then return false end
    return tostring(transmKey) == STOCK_TRANSMISSION_KEY
end

function NormalizeVehiclePlate(plate)
    if type(plate) ~= 'string' then
        return '*'
    end

    local normalized = plate:gsub('^%s+', ''):gsub('%s+$', '')
    if normalized == '' then
        return '*'
    end

    return string.upper(normalized)
end

local function GetTransmissionMaxGear(cfg, handlingOverrides)
    local overrideMaxGear = type(handlingOverrides) == 'table'
        and tonumber(handlingOverrides.nInitialDriveGears)
        or nil
    if overrideMaxGear and overrideMaxGear > 0 then
        return math.floor(overrideMaxGear)
    end

    if type(cfg) == 'table' and type(cfg.maxGear) == 'number' then
        return cfg.maxGear
    end

    return nil
end

function GetActiveTransmissionMaxGear()
    return GetTransmissionMaxGear(
        GearboxState.runtimeCfg or GearboxState.cfg,
        GearboxState.handlingOverrides
    )
end

local function BuildRuntimeTransmissionConfig(cfg, handlingOverrides)
    if type(cfg) ~= 'table' then
        return nil
    end

    local runtimeCfg = {}
    for key, value in pairs(cfg) do
        runtimeCfg[key] = value
    end

    local normalizedOverrides = NormalizeHandlingOverrides(cfg, handlingOverrides)
    runtimeCfg.maxGear = GetTransmissionMaxGear(cfg, normalizedOverrides) or cfg.maxGear

    local gearRatios = {}
    for index, fieldName in ipairs(GEAR_RATIO_FIELDS) do
        local overrideRatio = normalizedOverrides and tonumber(normalizedOverrides[fieldName]) or nil
        gearRatios[index] = overrideRatio or ((cfg.gearRatios or {})[index] or 0.0)
    end
    runtimeCfg.gearRatios = gearRatios

    return runtimeCfg
end

local function ResolveReferenceTransmissionConfig(cfg, modelName)
    if type(cfg) ~= 'table' then
        return nil
    end

    if type(modelName) == 'string' and modelName ~= '' then
        local mappedKey = Config.VehicleTransmissions and Config.VehicleTransmissions[string.lower(modelName)]
        local mappedCfg = mappedKey and Config.Transmissions[mappedKey] or nil
        if type(mappedCfg) == 'table' and mappedCfg.type == cfg.type then
            return mappedCfg
        end
    end

    local defaultCfg = Config.Transmissions and Config.Transmissions[Config.DefaultTransmission]
    if type(defaultCfg) == 'table' and defaultCfg.type == cfg.type then
        return defaultCfg
    end

    return nil
end

local function GetRatioMode()
    local mode = type(Config.RatioMode) == 'string' and string.lower(Config.RatioMode) or 'custom'
    return mode == 'realistic' and 'realistic' or 'custom'
end

function GetActiveTransmissionConfig()
    return GearboxState.runtimeCfg or GearboxState.cfg
end

local function IsManualTransmissionConfig(cfg)
    return type(cfg) == 'table'
        and (cfg.type == GearboxConst.Type.ATMT or cfg.type == GearboxConst.Type.MT)
end

function RefreshActiveTransmissionRuntimeConfig()
    GearboxState.runtimeCfg = BuildRuntimeTransmissionConfig(
        GearboxState.cfg,
        GearboxState.handlingOverrides
    )
    return GearboxState.runtimeCfg
end

local function RefreshVehicleTopSpeedModifier(vehicle)
    if type(ModifyVehicleTopSpeed) ~= 'function' then return end
    -- 始終重置為 1.0，不讀回現有值：
    -- 舊版 gearbox 曾用 ModifyVehicleTopSpeed(gearRatio/refRatio) 做每檔限速，
    -- 若讀回殘留值（例如三檔的 0.394）再套用，會產生 273.6 × 0.394 ≈ 109 km/h 的永久上限。
    ModifyVehicleTopSpeed(vehicle, 1.0)
end

function BuildTransmissionHandlingOverrides(cfg, handlingBackup, modelName)
    if type(cfg) ~= 'table' or type(cfg.maxGear) ~= 'number' then
        return nil
    end

    local overrides = {
        nInitialDriveGears = cfg.maxGear,
    }

    for index, fieldName in ipairs(GEAR_RATIO_FIELDS) do
        local ratio = (cfg.gearRatios or {})[index] or 0.0
        if fieldName then
            overrides[fieldName] = ratio + 0.0
        end
    end

    local backup = handlingBackup
    if GetRatioMode() ~= 'realistic' then
        if type(backup) == 'table' then
            if type(cfg.topSpeedScale) == 'number'
                and type(backup.maxFlatVel) == 'number' and backup.maxFlatVel > 0
            then
                overrides.fInitialDriveMaxFlatVel = backup.maxFlatVel
                    * math.clamp(cfg.topSpeedScale, 0.40, 1.80)
            end

            if type(cfg.driveForceScale) == 'number'
                and type(backup.driveForce) == 'number' and backup.driveForce > 0
            then
                overrides.fInitialDriveForce = backup.driveForce
                    * math.clamp(cfg.driveForceScale, 0.40, 1.80)
            end
        end

        return overrides
    end

    local topGear = cfg.maxGear
    local topRatio = (cfg.gearRatios or {})[topGear] or 0.0
    local firstRatio = (cfg.gearRatios or {})[1] or 0.0
    if type(backup) == 'table'
        and type(backup.maxFlatVel) == 'number' and backup.maxFlatVel > 0
    then
        local stockTopGear = math.max(1, math.floor(tonumber(backup.driveGears) or tonumber(backup.highGear) or topGear))
        local stockTopRatio = type(backup.gearRatios) == 'table' and tonumber(backup.gearRatios[stockTopGear]) or nil
        local stockFirstRatio = type(backup.gearRatios) == 'table' and tonumber(backup.gearRatios[1]) or nil
        local referenceCfg = ResolveReferenceTransmissionConfig(cfg, modelName)
        local stockFinalDrive = tonumber(referenceCfg and referenceCfg.finalDrive) or tonumber(cfg.finalDrive) or 1.0
        local newFinalDrive = tonumber(cfg.finalDrive) or stockFinalDrive or 1.0

        -- 1) 顯式 maxSpeedRatio 優先（config 中設定的明確極速比例）
        -- 下限改為 1.0：不允許低於原廠頂速，只允許升級加速，不限速
        if type(cfg.maxSpeedRatio) == 'number' then
            overrides.fInitialDriveMaxFlatVel = backup.maxFlatVel
                * math.clamp(cfg.maxSpeedRatio, 1.0, 2.0)
        -- 2) 依齒比 / 終傳計算縮放（下限改為 1.0，不允許低於原廠頂速）
        elseif (stockTopRatio or 0) > 0 and topRatio > 0 and stockFinalDrive > 0 and newFinalDrive > 0 then
            local topSpeedScale = math.clamp(
                (stockTopRatio * stockFinalDrive) / (topRatio * newFinalDrive),
                1.0, 1.35
            )
            overrides.fInitialDriveMaxFlatVel = backup.maxFlatVel * topSpeedScale
        end

        if type(backup.driveForce) == 'number' and backup.driveForce > 0
            and (stockFirstRatio or 0) > 0 and firstRatio > 0
            and stockFinalDrive > 0 and newFinalDrive > 0
        then
            local driveForceScale = math.clamp(
                (firstRatio * newFinalDrive) / (stockFirstRatio * stockFinalDrive),
                0.75, 1.45
            )
            overrides.fInitialDriveForce = backup.driveForce * driveForceScale
        end
    end

    return overrides
end

NormalizeHandlingOverrides = function(cfg, handlingOverrides)
    local normalized = BuildTransmissionHandlingOverrides(cfg, GearboxState.handlingBackup, GearboxState.modelName) or {}
    if type(handlingOverrides) ~= 'table' then
        return next(normalized) and normalized or nil
    end

    local maxGear = tonumber(handlingOverrides.nInitialDriveGears)
    if maxGear and maxGear > 0 then
        normalized.nInitialDriveGears = math.floor(maxGear)
    end

    for _, fieldName in ipairs(GEAR_RATIO_FIELDS) do
        local ratio = tonumber(handlingOverrides[fieldName])
        if ratio then
            normalized[fieldName] = ratio + 0.0
        end
    end

    -- fInitialDriveMaxFlatVel / fInitialDriveForce 不從存檔覆蓋：
    -- 這兩個值由 BuildTransmissionHandlingOverrides 依 backup × cfg 重算，
    -- 若沿用舊存檔（例如先前 menu.lua 齒比調整產生的錯誤值）會導致頂速異常。

    return next(normalized) and normalized or nil
end

local function ResetVehicleGearAfterHandlingChange(vehicle, maxGear)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end

    if type(SetVehicleCurrentGear) == 'function' then
        SetVehicleCurrentGear(vehicle, maxGear)
    end

    if type(SetVehicleNextGear) == 'function' then
        SetVehicleNextGear(vehicle, maxGear)
    end

    SetTimeout(11, function()
        if vehicle == 0 or not DoesEntityExist(vehicle) then return end

        if type(SetVehicleCurrentGear) == 'function' then
            SetVehicleCurrentGear(vehicle, 1)
        end

        if type(SetVehicleNextGear) == 'function' then
            SetVehicleNextGear(vehicle, math.min(2, maxGear))
        end

        EnforceTransmissionGearLimit(vehicle, { maxGear = maxGear })
    end)
end

function ApplyVehicleHandlingOverrides(vehicle, handlingOverrides)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if type(handlingOverrides) ~= 'table' then return end

    local previousDriveGears = type(GetVehicleHandlingInt) == 'function'
        and GetVehicleHandlingInt(vehicle, 'CHandlingData', 'nInitialDriveGears')
        or nil

    CaptureVehicleHandlingBackup(vehicle)

    -- 將原廠值存入 Entity StateBag（vehicle 實體存活期間持續有效，跨資源重啟）
    -- 日後重啟時 CaptureVehicleHandlingBackup 優先讀 StateBag，避免讀到已修改的值
    local backup = GearboxState.handlingBackup
    if backup then
        if type(backup.maxFlatVel) == 'number' and backup.maxFlatVel > 0
            and not Entity(vehicle).state['gearboxOrigMaxFlatVel']
        then
            Entity(vehicle).state:set('gearboxOrigMaxFlatVel', backup.maxFlatVel, false)
        end
        if type(backup.driveForce) == 'number' and backup.driveForce > 0
            and not Entity(vehicle).state['gearboxOrigDriveForce']
        then
            Entity(vehicle).state:set('gearboxOrigDriveForce', backup.driveForce, false)
        end
    end

    local maxGear = GetTransmissionMaxGear(nil, handlingOverrides)
    if maxGear then
        if type(SetVehicleHandlingInt) == 'function' then
            SetVehicleHandlingInt(vehicle, 'CHandlingData', 'nInitialDriveGears', maxGear)
        end

        if type(SetVehicleHighGear) == 'function' then
            SetVehicleHighGear(vehicle, maxGear)
        end

        if Citizen and type(Citizen.InvokeNative) == 'function' then
            pcall(Citizen.InvokeNative, SET_VEHICLE_MAX_GEAR_NATIVE, vehicle, maxGear)
            pcall(Citizen.InvokeNative, SET_VEHICLE_HIGH_GEAR_NATIVE, vehicle, maxGear)
        end
    end

    for key, value in pairs(handlingOverrides) do
        if key ~= 'nInitialDriveGears' then
            local ratioIndex = GEAR_RATIO_FIELD_INDEX[key]
            if ratioIndex and type(value) == 'number' then
                if type(SetVehicleGearRatio) == 'function' then
                    SetVehicleGearRatio(vehicle, ratioIndex, value)
                end
            elseif FLOAT_HANDLING_FIELD_SET[key] and type(value) == 'number' then
                if type(SetVehicleHandlingFloat) == 'function' then
                    SetVehicleHandlingFloat(vehicle, 'CHandlingData', key, value)
                end
            end
        end
    end

    RefreshVehicleTopSpeedModifier(vehicle)

    if maxGear then
        if previousDriveGears ~= maxGear then
            ResetVehicleGearAfterHandlingChange(vehicle, maxGear)
        end

        EnforceTransmissionGearLimit(vehicle, { maxGear = maxGear })
    end
end

local function GetResolvedVehicleGear(vehicle, maxGear)
    local currentGear = GetVehicleCurrentGear(vehicle)
    if type(maxGear) == 'number' and currentGear > maxGear then
        currentGear = maxGear
    end
    return (currentGear <= 0) and currentGear or math.max(1, currentGear)
end

CaptureVehicleHandlingBackup = function(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end

    local backup = GearboxState.handlingBackup
    if backup and backup.vehicle == vehicle then
        return backup
    end

    local ratios = {}
    if type(GetVehicleGearRatio) == 'function' then
        for gear = 0, MAX_GEAR_RATIO_SLOTS do
            ratios[gear] = GetVehicleGearRatio(vehicle, gear)
        end
    end

    backup = {
        vehicle = vehicle,
        highGear = type(GetVehicleHighGear) == 'function' and GetVehicleHighGear(vehicle) or nil,
        driveGears = type(GetVehicleHandlingInt) == 'function'
            and GetVehicleHandlingInt(vehicle, 'CHandlingData', 'nInitialDriveGears')
            or nil,
        -- 原廠極速讀取優先順序：
        -- 0) Config.VehicleStockHandling：管理員手動填入，最可靠（改裝車首選）
        -- 1) GetVehicleModelMaxSpeed：從模型資料讀取，不受執行期修改影響
        -- 2) StateBag：資源重啟時保留的原廠備份（需與模型值比對驗證）
        -- 3) GTA entity：最後備援（可能已被本腳本修改為每檔速度值）
        maxFlatVel = (function()
            -- 0) 管理員手動設定的原廠值（最高優先，完全繞過 entity 讀取問題）
            local stockCfg = Config.VehicleStockHandling
                and Config.VehicleStockHandling[GearboxState.modelName]
            if stockCfg and type(stockCfg.maxFlatVel) == 'number' and stockCfg.maxFlatVel > 0 then
                -- 同步覆蓋 StateBag（清除舊的損壞值）
                Entity(vehicle).state:set('gearboxOrigMaxFlatVel', stockCfg.maxFlatVel, false)
                return stockCfg.maxFlatVel
            end

            -- 1) 從車輛模型讀取原廠極速（m/s → km/h）
            local modelKmh = nil
            if type(GetVehicleModelMaxSpeed) == 'function' then
                local ms = GetVehicleModelMaxSpeed(GetEntityModel(vehicle))
                if type(ms) == 'number' and ms > 0 then modelKmh = ms * 3.6 end
            end

            -- 2) StateBag 有值：驗證是否合理（若明顯低於模型值視為殘留的每檔速度值）
            local sb = Entity(vehicle).state['gearboxOrigMaxFlatVel']
            if type(sb) == 'number' and sb > 0 then
                local isValid = (modelKmh == nil) or (sb >= modelKmh * 0.5)
                if isValid then return sb end
                -- StateBag 損壞，清除讓後續重建正確值
                Entity(vehicle).state:set('gearboxOrigMaxFlatVel', nil, false)
            end

            -- 優先使用模型極速（不受執行期修改）
            if modelKmh then return modelKmh end

            -- 3) 最後備援：從 entity 讀（首次進車時尚未被修改）
            return type(GetVehicleHandlingFloat) == 'function'
                and GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel')
                or nil
        end)(),
        driveForce = (function()
            local sb = Entity(vehicle).state['gearboxOrigDriveForce']
            if type(sb) == 'number' and sb > 0 then return sb end
            return type(GetVehicleHandlingFloat) == 'function'
                and GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce')
                or nil
        end)(),
        gearRatios = ratios,
    }

    GearboxState.handlingBackup = backup

    -- 診斷輸出：確認 modelName 與捕獲到的 handling 數值
    print(('[Gearbox][Backup] modelName="%s" maxFlatVel=%s driveForce=%s stockCfgFound=%s'):format(
        tostring(GearboxState.modelName),
        tostring(backup.maxFlatVel),
        tostring(backup.driveForce),
        tostring(Config.VehicleStockHandling ~= nil and Config.VehicleStockHandling[GearboxState.modelName] ~= nil)
    ))

    return backup
end

function RestoreVehicleGearHandling(vehicle)
    local backup = GearboxState.handlingBackup
    if not backup then return end

    GearboxState.handlingBackup = nil
    GearboxState.driveForceCutActive = false
    GearboxState.torqueCutActive = false

    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if backup.vehicle ~= vehicle then return end

    if type(SetVehicleHandlingInt) == 'function'
        and type(backup.driveGears) == 'number'
        and backup.driveGears > 0
    then
        SetVehicleHandlingInt(vehicle, 'CHandlingData', 'nInitialDriveGears', backup.driveGears)
    end

    if type(SetVehicleHighGear) == 'function'
        and type(backup.highGear) == 'number'
        and backup.highGear > 0
    then
        SetVehicleHighGear(vehicle, backup.highGear)
    end

    if type(SetVehicleGearRatio) == 'function' and type(backup.gearRatios) == 'table' then
        for gear = 0, MAX_GEAR_RATIO_SLOTS do
            local ratio = backup.gearRatios[gear]
            if type(ratio) == 'number' then
                SetVehicleGearRatio(vehicle, gear, ratio)
            end
        end
    end

    if type(SetVehicleHandlingFloat) == 'function' then
        if type(backup.maxFlatVel) == 'number' and backup.maxFlatVel > 0 then
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel', backup.maxFlatVel)
        end
        if type(backup.driveForce) == 'number' and backup.driveForce > 0 then
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce', backup.driveForce)
        end
    end

    RefreshVehicleTopSpeedModifier(vehicle)

    if type(SetVehicleEngineTorqueMultiplier) == 'function' then
        SetVehicleEngineTorqueMultiplier(vehicle, 1.0)
    end

    -- 移除腳本設定的硬性極速上限
    if type(SetVehicleMaxSpeed) == 'function' then
        SetVehicleMaxSpeed(vehicle, 0.0)
    end

    -- StateBag 不手動清除：Entity StateBag 與 vehicle entity 生命週期綁定，
    -- 車輛實體被銷毀時會自動清除。手動清除反而會讓資源重啟後找不到備份值，
    -- 被迫從已被修改的 GTA entity 讀取（可能是錯誤的每檔速度值）。

    if Config.Debug then
        print(('[GearboxState] Restored original handling for vehicle=%d'):format(vehicle))
    end
end


function ApplyTransmissionState(vehicle, transmKey, handlingOverrides)
    local state = GearboxState
    local key = tostring(transmKey or STOCK_TRANSMISSION_KEY)
    local cfg = Config.Transmissions[key]

    if not cfg or IsStockTransmissionKey(key) then
        if vehicle ~= 0 and DoesEntityExist(vehicle) and type(SetVehicleEngineTorqueMultiplier) == 'function' then
            SetVehicleEngineTorqueMultiplier(vehicle, 1.0)
        end
        RestoreVehicleGearHandling(vehicle)
        state.transmKey = STOCK_TRANSMISSION_KEY
        state.cfg = nil
        state.runtimeCfg = nil
        state.handlingOverrides = nil
        state.driveForceCutActive = false
        state.torqueCutActive = false
        state.currentGear = (vehicle ~= 0 and DoesEntityExist(vehicle))
            and GetResolvedVehicleGear(vehicle)
            or 1
        state.clutchHealth = 100.0
        return false
    end

    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        CaptureVehicleHandlingBackup(vehicle)
    end

    local resolvedOverrides = handlingOverrides
    resolvedOverrides = NormalizeHandlingOverrides(cfg, resolvedOverrides)

    -- 切換變速箱時，若離合器 torque cut 正在作用，先強制恢復
    -- （僅重設旗標而不呼叫 native 會導致 torque 永遠卡在 0.0）
    if state.torqueCutActive and vehicle ~= 0 and DoesEntityExist(vehicle)
        and type(SetVehicleEngineTorqueMultiplier) == 'function'
    then
        SetVehicleEngineTorqueMultiplier(vehicle, 1.0)
    end

    state.transmKey = key
    state.cfg = cfg
    state.handlingOverrides = resolvedOverrides
    state.runtimeCfg = BuildRuntimeTransmissionConfig(cfg, resolvedOverrides)
    state.driveForceCutActive = false
    state.torqueCutActive = false
    state.currentGear = GetResolvedVehicleGear(
        vehicle,
        GetTransmissionMaxGear(state.runtimeCfg or cfg, resolvedOverrides)
    )
    ApplyGearRatiosToVehicle(vehicle, state.runtimeCfg or cfg, resolvedOverrides)

    -- 不設定 SetVehicleMaxSpeed：GTA 物理自行透過 fInitialDriveMaxFlatVel 限速；
    -- 硬性上限（maxSpeedRatio × 原廠速度）會讓車輛卡在低於設計頂速，體感像「限速器」。
    -- 若有舊值殘留（換檔箱切換時），清除之。
    if vehicle ~= 0 and DoesEntityExist(vehicle) and type(SetVehicleMaxSpeed) == 'function' then
        SetVehicleMaxSpeed(vehicle, 0.0)
    end

    return true
end

function EnforceTransmissionGearLimit(vehicle, cfg)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if type(cfg) ~= 'table' or type(cfg.maxGear) ~= 'number' then return end

    -- AT 模式：highGear = scriptGear（腳本自行控制換檔邏輯，必須與腳本檔位同步，
    --   防止 GTA 原生 AT 自行升超過腳本當前檔）。
    -- ATMT/MT 模式：highGear = maxGear，讓 GTA AT 自由選擇 1..maxGear。
    --   每檔速度上限由 physics.lua 的 fInitialDriveMaxFlatVel = gearTopSpeed 控制。
    --   highGear=scriptGear 會使 GTA 在 gear 1 高速時驅動力異常衰減（torque multiplier
    --   = ratio[1]/ratio[1] = 1.0，缺乏真實低檔大扭矩），導致 gear 1 無法達到與
    --   高齒比相同頂速。改用 highGear=maxGear 後，GTA 在高速自然切入高檔，
    --   驅動力正確，且 fInitialDriveMaxFlatVel 負責限速，不需要鎖 highGear。
    local isManual = IsManualTransmissionConfig(cfg)
    local highGear = isManual
        and cfg.maxGear
        or  math.max(1, math.min(GearboxState.currentGear or cfg.maxGear, cfg.maxGear))
    if type(SetVehicleHighGear) == 'function' then
        SetVehicleHighGear(vehicle, highGear)
    end

    local currentGear = GetVehicleCurrentGear(vehicle)
    if currentGear > cfg.maxGear then
        if type(SetVehicleCurrentGear) == 'function' then
            SetVehicleCurrentGear(vehicle, cfg.maxGear)
        end
        if type(SetVehicleNextGear) == 'function' then
            SetVehicleNextGear(vehicle, cfg.maxGear)
        end
        GearboxState.currentGear = cfg.maxGear
        return
    end

    if type(SetVehicleNextGear) == 'function' and currentGear >= cfg.maxGear then
        SetVehicleNextGear(vehicle, cfg.maxGear)
    end
end

function ApplyManualTransmissionLock(vehicle)
    local state = GearboxState
    local cfg = GetActiveTransmissionConfig() or state.cfg
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if not IsManualTransmissionConfig(cfg) then return end
    if IsControlPressed(0, 72) and GetEntitySpeed(vehicle) < 1.0 then return end
    if IsVehicleReversingState(vehicle) then return end

    local maxGear = GetActiveTransmissionMaxGear() or cfg.maxGear or 1
    local desiredGear = math.max(1, math.floor(tonumber(state.currentGear) or 1))
    desiredGear = math.min(desiredGear, maxGear)
    state.currentGear = desiredGear

    -- 不在此每幀強制呼叫 SetVehicleCurrentGear(desiredGear)。
    -- 低速時強制設為高檔會觸發 GTA AT 自動降檔迴圈（每幀：腳本升→GTA降→腳本升...），
    -- 導致 GTA 在每次降檔事件中切斷油門，車輛完全無法移動。
    -- 改由 EnforceTransmissionGearLimit 將 HighGear 設為 scriptGear 作上限，
    -- 讓 GTA AT 在 1..scriptGear 範圍內自然選擇，SetVehicleMaxSpeed 負責每檔頂速限制。
end

function ApplyManualNeutralStartIfNeeded(vehicle)
    local state = GearboxState
    local cfg = GetActiveTransmissionConfig() or state.cfg
    if Config.MTStartInNeutral == false then return false end
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if type(cfg) ~= 'table' or cfg.type ~= GearboxConst.Type.MT then return false end

    state.currentGear = 1
    SetNeutral(true)
    ApplyManualTransmissionLock(vehicle)
    return true
end

local function GetAppliedDriveForceValue()
    local state = GearboxState
    local overrides = state.handlingOverrides
    local overrideDriveForce = type(overrides) == 'table'
        and tonumber(overrides.fInitialDriveForce)
        or nil
    if overrideDriveForce and overrideDriveForce > 0 then
        return overrideDriveForce
    end

    local backup = state.handlingBackup
    local backupDriveForce = type(backup) == 'table'
        and tonumber(backup.driveForce)
        or nil
    if backupDriveForce and backupDriveForce > 0 then
        return backupDriveForce
    end

    return nil
end

function UpdateManualClutchDriveForce(vehicle, shouldCut)
    local state = GearboxState
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if type(SetVehicleHandlingFloat) ~= 'function' then return end

    local desiredCutState = shouldCut == true
    if state.driveForceCutActive == desiredCutState then
        return
    end

    if desiredCutState then
        -- 切斷前先取得驅動力並快取（供恢復使用，避免備份/override 遺失時無法還原）
        local driveForce = GetAppliedDriveForceValue()
        -- 備用：直接從 GTA 讀取（當備份尚未建立或 nil 時）
        if not driveForce or driveForce <= 0 then
            driveForce = type(GetVehicleHandlingFloat) == 'function'
                and GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce')
                or nil
        end
        if not driveForce or driveForce <= 0 then return end
        state.savedDriveForce = driveForce
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce', 0.0001)
        state.driveForceCutActive = true
    else
        -- 恢復：優先使用切斷前快取的值，備援才用 GetAppliedDriveForceValue
        local driveForce = state.savedDriveForce or GetAppliedDriveForceValue()
        -- 無論是否能取回驅動力，都必須先重設旗標，防止 driveForceCutActive 卡住導致車輛無法行駛
        state.driveForceCutActive = false
        state.savedDriveForce = nil
        if not driveForce or driveForce <= 0 then return end
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce', driveForce)
    end
end

function UpdateManualClutchTorque(vehicle, shouldCut)
    local state = GearboxState
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if type(SetVehicleEngineTorqueMultiplier) ~= 'function' then return end

    local desiredCutState = shouldCut == true
    if desiredCutState then
        -- GTA 每幀會重設 torque multiplier，必須每幀強制套用
        SetVehicleEngineTorqueMultiplier(vehicle, 0.0)
        state.torqueCutActive = true
    elseif state.torqueCutActive then
        SetVehicleEngineTorqueMultiplier(vehicle, 1.0)
        state.torqueCutActive = false
    end
end

-- 初始化（進入車輛時呼叫）
function GearboxStateInit(vehicle)
    local netId     = NetworkGetNetworkIdFromEntity(vehicle)
    local modelHash = GetEntityModel(vehicle)
    local modelName = string.lower(GetDisplayNameFromVehicleModel(modelHash))
    local vehiclePlate = NormalizeVehiclePlate(GetVehicleNumberPlateText(vehicle))

    local transmKey = Config.VehicleTransmissions[modelName]

    GearboxState.vehicle        = vehicle
    GearboxState.vehicleNetId   = netId
    GearboxState.modelName      = modelName
    GearboxState.vehiclePlate   = vehiclePlate
    GearboxState.inVehicle      = true
    GearboxState.transmKey      = STOCK_TRANSMISSION_KEY
    GearboxState.cfg            = nil
    GearboxState.runtimeCfg     = nil
    GearboxState.handlingOverrides = nil
    GearboxState.currentGear    = GetResolvedVehicleGear(vehicle)
    GearboxState.isNeutral      = false
    GearboxState.isShifting     = false
    GearboxState.shiftTimer     = 0
    GearboxState.clutchKeyDown  = false
    GearboxState.clutchValue    = 0.0
    GearboxState.clutchSlipAccum = 0.0
    GearboxState.rpm            = GetVehicleCurrentRpm(vehicle)
    GearboxState.targetRpm      = GearboxState.rpm
    GearboxState.engineOn       = IsVehicleEngineOn(vehicle)
    GearboxState.stallTimer     = 0
    GearboxState.lastThrottle   = 0.0
    GearboxState.lastSpeed      = GetEntitySpeed(vehicle)
    GearboxState.gearboxTemp    = 20.0
    GearboxState.turboBoost     = 0.0
    GearboxState.antiStall      = Config.AntiStallAssist
    GearboxState.revMatch       = Config.RevMatchAssist
    GearboxState.driftEnabled   = Config.Drift.enabled
    GearboxState.launchActive   = false
    GearboxState.launchPrepped  = false
    GearboxState.driveForceCutActive = false
    GearboxState.torqueCutActive = false
    GearboxState.savedDriveForce = nil
    -- unlockedTransmissions 保留上次載入的值，不重置（進入新車時仍有效）

    if transmKey and Config.Transmissions[transmKey] then
        ApplyTransmissionState(vehicle, transmKey)
        ApplyManualNeutralStartIfNeeded(vehicle)
    end

    if Config.Debug then
        print(('[GearboxState] Init vehicle=%d model=%s transm=%s'):format(
            vehicle, modelName, GearboxState.transmKey))
    end
end

-- 重設（離開車輛時呼叫）
function GearboxStateReset()
    GearboxState.vehicle       = 0
    GearboxState.vehicleNetId  = 0
    GearboxState.modelName     = ''
    GearboxState.vehiclePlate  = '*'
    GearboxState.inVehicle     = false
    GearboxState.transmKey     = ''
    GearboxState.cfg           = nil
    GearboxState.runtimeCfg    = nil
    GearboxState.handlingOverrides = nil
    GearboxState.currentGear   = 1
    GearboxState.isNeutral     = false
    GearboxState.isShifting    = false
    GearboxState.shiftTimer    = 0
    GearboxState.clutchKeyDown = false
    GearboxState.clutchValue   = 0.0
    GearboxState.engineOn      = false
    GearboxState.stallTimer    = 0
    GearboxState.handlingBackup = nil
    GearboxState.driveForceCutActive = false
    GearboxState.torqueCutActive = false
    GearboxState.savedDriveForce = nil
end

function GetVehicleSignedForwardSpeed(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return 0.0
    end

    local velocity = GetEntitySpeedVector(vehicle, true)
    return velocity.y or 0.0
end

function IsVehicleReversingState(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    if GetVehicleSignedForwardSpeed(vehicle) < -0.15 then
        return true
    end

    return GetVehicleThrottleOffset(vehicle) < -0.10
end

-- 將齒比套用到 GTA Handling（僅影響本地端）
function ApplyGearRatiosToVehicle(vehicle, cfg, handlingOverrides)
    local overrides = handlingOverrides
    if type(overrides) ~= 'table' then
        overrides = BuildTransmissionHandlingOverrides(cfg, GearboxState.handlingBackup, GearboxState.modelName)
    end

    ApplyVehicleHandlingOverrides(vehicle, overrides)

    if Config.Debug then
        print(('[GearboxState] Applied handling overrides for %d gear ratios, maxGear=%d')
            :format(#(cfg.gearRatios or {}), cfg.maxGear))
    end
end

-- 取得 locale 字串（目前固定 zh-TW，日後可擴展）
function GetLocale(key)
    local loc = Locales and (Locales['zh-TW'] or Locales['en'])
    return loc and loc[key] or key
end
