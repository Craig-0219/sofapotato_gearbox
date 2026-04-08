-- ─────────────────────────────────────────────────────
-- 持久化：載入 / 儲存 / 維修
-- ─────────────────────────────────────────────────────

local STOCK_TRANSMISSION_KEY = 'STOCK'
local PLAYER_SETTINGS_TABLE = 'sp_gearbox_player_settings'
local UNLOCKED_TRANSMISSIONS_TABLE = 'sp_gearbox_unlocked_transmissions'
local GEAR_RATIO_FIELDS = {
    'fGearRatioFirst', 'fGearRatioSecond', 'fGearRatioThird',
    'fGearRatioFourth', 'fGearRatioFifth', 'fGearRatioSixth',
    'fGearRatioSeventh', 'fGearRatioEighth',
}
local FLOAT_HANDLING_FIELDS = {
    'fInitialDriveMaxFlatVel',
    'fInitialDriveForce',
}

local function NormalizeVehicleModelName(modelName)
    if type(modelName) ~= 'string' then return nil end

    local normalized = modelName:match('^%s*(.-)%s*$')
    if not normalized or normalized == '' then return nil end

    return string.lower(normalized)
end

local function NormalizeVehiclePlate(plate)
    if type(plate) ~= 'string' then
        return '*'
    end

    local normalized = plate:gsub('^%s+', ''):gsub('%s+$', '')
    if normalized == '' then
        return '*'
    end

    return string.upper(normalized)
end

local function BuildHandlingOverridesFromTransmission(transmKey)
    local cfg = Config.Transmissions[transmKey]
    if not cfg then
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

    return overrides
end

local function MergeHandlingOverridesWithGearRatios(transmKey, gearRatios)
    local overrides = BuildHandlingOverridesFromTransmission(transmKey)
    if type(gearRatios) ~= 'table' then
        return overrides
    end

    overrides = overrides or {}
    for index, ratio in ipairs(gearRatios) do
        local fieldName = GEAR_RATIO_FIELDS[index]
        if fieldName and tonumber(ratio) then
            overrides[fieldName] = tonumber(ratio)
        end
    end

    return next(overrides) and overrides or nil
end

local function SanitizeHandlingOverrides(overrides, transmKey)
    if tostring(transmKey or STOCK_TRANSMISSION_KEY) == STOCK_TRANSMISSION_KEY then
        return nil
    end

    local cleaned = BuildHandlingOverridesFromTransmission(transmKey) or {}
    if type(overrides) ~= 'table' then
        return next(cleaned) and cleaned or nil
    end

    local maxGear = tonumber(overrides.nInitialDriveGears)
    if maxGear and maxGear > 0 then
        cleaned.nInitialDriveGears = math.floor(maxGear)
    end

    for _, fieldName in ipairs(GEAR_RATIO_FIELDS) do
        local value = tonumber(overrides[fieldName])
        if value then
            cleaned[fieldName] = value
        end
    end

    for _, fieldName in ipairs(FLOAT_HANDLING_FIELDS) do
        local value = tonumber(overrides[fieldName])
        if value then
            cleaned[fieldName] = value
        end
    end

    if not cleaned.nInitialDriveGears then
        local fallback = BuildHandlingOverridesFromTransmission(transmKey)
        if fallback then
            cleaned.nInitialDriveGears = fallback.nInitialDriveGears
        end
    end

    return next(cleaned) and cleaned or BuildHandlingOverridesFromTransmission(transmKey)
end

local function ExtractGearRatios(overrides, transmKey)
    if type(overrides) == 'table' then
        local ratios = {}
        for index, fieldName in ipairs(GEAR_RATIO_FIELDS) do
            local ratio = tonumber(overrides[fieldName])
            if ratio then
                ratios[index] = ratio
            end
        end

        if #ratios > 0 then
            return ratios
        end
    end

    local cfg = Config.Transmissions[transmKey]
    return cfg and cfg.gearRatios or nil
end

local function GetFrameworkName()
    local ok, frameworkName = pcall(function()
        return exports['sp_bridge']:GetFrameworkName()
    end)

    if ok and type(frameworkName) == 'string' and frameworkName ~= '' then
        return frameworkName
    end

    return nil
end

local function GetSharedVehicleByHash(modelHash)
    if type(modelHash) ~= 'number' or modelHash == 0 then return nil end

    local frameworkName = GetFrameworkName()

    if frameworkName == 'esx' then
        return nil
    end

    if frameworkName == 'qbx' or (not frameworkName and GetResourceState('qbx_core') == 'started') then
        local ok, vehicleData = pcall(function()
            return exports.qbx_core:GetVehiclesByHash(modelHash)
        end)

        if ok and type(vehicleData) == 'table' then
            return vehicleData
        end
    end

    if frameworkName == 'qbcore' or (not frameworkName and GetResourceState('qb-core') == 'started') then
        local ok, vehicleData = pcall(function()
            return exports['qb-core']:GetVehiclesByHash(modelHash)
        end)

        if ok and type(vehicleData) == 'table' then
            return vehicleData
        end

        local okCore, qbCore = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)

        if okCore and type(qbCore) == 'table' then
            local shared = qbCore.Shared
            if shared and shared.VehicleHashes then
                return shared.VehicleHashes[modelHash]
            end
        end
    end

    return nil
end

local function ResolveVehicleModelName(vehicleNetId, fallbackModelName)
    local normalizedFallback = NormalizeVehicleModelName(fallbackModelName)
    local netId = tonumber(vehicleNetId)

    -- 先確認 netId 出現在 server 已知的 entity 清單中，避免直接呼叫
    -- NetworkGetEntityFromNetworkId 時讓 FiveM 印出 "GetNetworkObject: no object by ID" 警告。
    -- （該警告在 C++ 層產生，早於 Lua 的 DoesEntityExist 判斷，無法用 pcall 抑制。）
    local function isNetworkEntityKnown(id)
        if not id or id <= 0 then return false end
        for _, ent in ipairs(GetAllVehicles() or {}) do
            if NetworkGetNetworkIdFromEntity(ent) == id then return true end
        end
        return false
    end

    if netId and netId > 0
        and type(NetworkGetEntityFromNetworkId) == 'function'
        and type(DoesEntityExist) == 'function'
        and type(GetEntityModel) == 'function'
        and isNetworkEntityKnown(netId)
    then
        local vehicle = NetworkGetEntityFromNetworkId(netId)
        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
            local modelHash = GetEntityModel(vehicle)
            local vehicleData = GetSharedVehicleByHash(modelHash)

            if vehicleData and type(vehicleData.model) == 'string' and vehicleData.model ~= '' then
                return string.lower(vehicleData.model)
            end

            if normalizedFallback and type(GetHashKey) == 'function' and GetHashKey(normalizedFallback) == modelHash then
                return normalizedFallback
            end
        end
    end

    return normalizedFallback or 'default'
end

-- ── 載入設定（Client 進入車輛後觸發）────────────────────
RegisterNetEvent(GearboxConst.Events.LOAD_SETTINGS, function(data)
    local src = source
    if type(data) ~= 'table' then return end

    local citizenId  = exports['sp_bridge']:GetCitizenId(src)
    if not citizenId then return end

    local modelName = ResolveVehicleModelName(data.vehicleNetId, data.modelName)
    local vehiclePlate = NormalizeVehiclePlate(data.vehiclePlate)

    -- 同時查詢車輛設定 + 玩家已解鎖清單
    MySQL.query(
        ([[
            SELECT transmission, clutch_health, gear_ratios, handling_overrides
            FROM %s
            WHERE citizenid = ?
              AND vehicle_model = ?
              AND vehicle_plate IN (?, '*')
            ORDER BY CASE WHEN vehicle_plate = ? THEN 1 ELSE 0 END DESC
            LIMIT 1
        ]])
            :format(PLAYER_SETTINGS_TABLE),
        { citizenId, modelName, vehiclePlate, vehiclePlate },
        function(result)
            local payload = {}
            local mappedTransmKey = Config.VehicleTransmissions[modelName]
            if mappedTransmKey and not Config.Transmissions[mappedTransmKey] then
                mappedTransmKey = nil
            end

            local storedTransmKey = tostring(mappedTransmKey or STOCK_TRANSMISSION_KEY)
            if result and result[1] then
                storedTransmKey      = tostring(result[1].transmission or STOCK_TRANSMISSION_KEY)
                payload.clutchHealth = result[1].clutch_health

                if result[1].gear_ratios then
                    local ok, decoded = pcall(json.decode, result[1].gear_ratios)
                    if ok then payload.gearRatios = decoded end
                end

                if result[1].handling_overrides then
                    local ok, decoded = pcall(json.decode, result[1].handling_overrides)
                    if ok and type(decoded) == 'table' then
                        payload.handlingOverrides = decoded
                    end
                end

                if not payload.handlingOverrides
                    and storedTransmKey ~= STOCK_TRANSMISSION_KEY
                    and payload.gearRatios
                then
                    payload.handlingOverrides = MergeHandlingOverridesWithGearRatios(
                        storedTransmKey,
                        payload.gearRatios
                    )
                end
            end

            -- 查詢已解鎖清單
            MySQL.query(
                ('SELECT transmission FROM %s WHERE citizenid = ?')
                    :format(UNLOCKED_TRANSMISSIONS_TABLE),
                { citizenId },
                function(unlocks)
                    local list = {}
                    if unlocks then
                        for _, row in ipairs(unlocks) do
                            list[#list + 1] = row.transmission
                        end
                    end

                    local resolvedTransmKey = storedTransmKey
                    if resolvedTransmKey ~= STOCK_TRANSMISSION_KEY then
                        local cfg = Config.Transmissions[resolvedTransmKey]
                        local tierInfo = Config.Upgrade.tiers[resolvedTransmKey]
                        local isPreinstalled = mappedTransmKey == resolvedTransmKey
                        local isUnlocked = isPreinstalled
                            or (tierInfo and tierInfo.tier <= 1)

                        if not isUnlocked then
                            for _, unlockedKey in ipairs(list) do
                                if unlockedKey == resolvedTransmKey then
                                    isUnlocked = true
                                    break
                                end
                            end
                        end

                        if not cfg or not isUnlocked then
                            resolvedTransmKey = STOCK_TRANSMISSION_KEY
                        end
                    end

                    payload.transmKey = resolvedTransmKey
                    if resolvedTransmKey == STOCK_TRANSMISSION_KEY then
                        payload.clutchHealth = 100.0
                        payload.gearRatios = nil
                        payload.handlingOverrides = nil
                    end

                    payload.unlockedTransmissions = list
                    TriggerClientEvent(GearboxConst.Events.SYNC_SETTINGS, src, payload)
                end
            )
        end
    )
end)

-- ── 儲存設定（離開車輛或手動換型號時觸發）────────────────
RegisterNetEvent(GearboxConst.Events.SAVE_SETTINGS, function(data)
    local src = source
    if type(data) ~= 'table' then return end

    local citizenId = exports['sp_bridge']:GetCitizenId(src)
    if not citizenId then return end

    local vehicleModel = ResolveVehicleModelName(data.vehicleNetId, data.vehicleModel)
    local vehiclePlate = NormalizeVehiclePlate(data.vehiclePlate)
    local transmKey    = tostring(data.transmKey or STOCK_TRANSMISSION_KEY)
    local clutchHealth = math.max(0.0, math.min(100.0, tonumber(data.clutchHealth) or 100.0))
    local handlingOverrides = SanitizeHandlingOverrides(data.handlingOverrides, transmKey)
    local gearRatios = data.gearRatios or ExtractGearRatios(handlingOverrides, transmKey)
    local gearRatiosJson = gearRatios and json.encode(gearRatios) or nil
    local handlingOverridesJson = handlingOverrides and json.encode(handlingOverrides) or nil

    if transmKey ~= STOCK_TRANSMISSION_KEY and not Config.Transmissions[transmKey] then
        transmKey = STOCK_TRANSMISSION_KEY
    end

    if transmKey == STOCK_TRANSMISSION_KEY then
        clutchHealth = 100.0
        gearRatiosJson = nil
        handlingOverridesJson = nil
    end

    MySQL.insert(
        ([[INSERT INTO %s
            (citizenid, vehicle_model, vehicle_plate, transmission, clutch_health, gear_ratios, handling_overrides)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE
            vehicle_plate  = VALUES(vehicle_plate),
            transmission  = VALUES(transmission),
            clutch_health = VALUES(clutch_health),
            gear_ratios   = VALUES(gear_ratios),
            handling_overrides = VALUES(handling_overrides)]])
            :format(PLAYER_SETTINGS_TABLE),
        { citizenId, vehicleModel, vehiclePlate, transmKey, clutchHealth, gearRatiosJson, handlingOverridesJson }
    )
end)

-- ── 維修離合器（從 ox_target NPC 或物品觸發）─────────────
RegisterNetEvent(GearboxConst.Events.REPAIR_CLUTCH, function(payload)
    local src = source

    local citizenId = exports['sp_bridge']:GetCitizenId(src)
    if not citizenId then return end

    local vehicleModel
    local vehiclePlate = '*'
    if type(payload) == 'table' then
        vehicleModel = ResolveVehicleModelName(payload.vehicleNetId, payload.vehicleModel or payload.modelName)
        vehiclePlate = NormalizeVehiclePlate(payload.vehiclePlate)
    else
        vehicleModel = ResolveVehicleModelName(nil, payload)
    end

    local money = exports['sp_bridge']:GetMoney(src, 'bank')
    if money < Config.Clutch.repairCost then
        TriggerClientEvent(GearboxConst.Events.REPAIR_RESULT, src, false, 'insufficient_funds')
        return
    end

    exports['sp_bridge']:RemoveMoney(src, 'bank', Config.Clutch.repairCost, 'gearbox_clutch_repair')

    MySQL.update(
        ('UPDATE %s SET clutch_health = 100.0 WHERE citizenid = ? AND vehicle_model = ? AND vehicle_plate IN (?, \'*\')')
            :format(PLAYER_SETTINGS_TABLE),
        { citizenId, vehicleModel, vehiclePlate },
        function()
            TriggerClientEvent(GearboxConst.Events.REPAIR_RESULT, src, true, nil)
        end
    )
end)
