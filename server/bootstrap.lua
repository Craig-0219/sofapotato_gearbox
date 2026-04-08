-- ─────────────────────────────────────────────────────
-- 依賴確認與初始化
-- ─────────────────────────────────────────────────────

local PLAYER_SETTINGS_TABLE = 'sp_gearbox_player_settings'
local LEGACY_PLAYER_SETTINGS_TABLE = 'gearbox_player_settings'
local UNLOCKED_TRANSMISSIONS_TABLE = 'sp_gearbox_unlocked_transmissions'
local LEGACY_UNLOCKED_TRANSMISSIONS_TABLE = 'gearbox_unlocked_transmissions'
_G.SP_GEARBOX_SCHEMA_READY = false

local function tableExists(tableName)
    if not MySQL or not MySQL.scalar or not MySQL.scalar.await then
        return false, 'MySQL.scalar.await unavailable'
    end

    local ok, result = pcall(MySQL.scalar.await, [[
        SELECT COUNT(*)
        FROM information_schema.tables
        WHERE table_schema = DATABASE()
          AND table_name = ?
    ]], { tableName })

    if not ok then
        return false, result
    end

    return (tonumber(result) or 0) > 0
end

local function columnExists(tableName, columnName)
    if not MySQL or not MySQL.scalar or not MySQL.scalar.await then
        return false, 'MySQL.scalar.await unavailable'
    end

    local ok, result = pcall(MySQL.scalar.await, [[
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = ?
          AND column_name = ?
    ]], { tableName, columnName })

    if not ok then
        return false, result
    end

    return (tonumber(result) or 0) > 0
end

local function indexExists(tableName, indexName)
    if not MySQL or not MySQL.scalar or not MySQL.scalar.await then
        return false, 'MySQL.scalar.await unavailable'
    end

    local ok, result = pcall(MySQL.scalar.await, [[
        SELECT COUNT(*)
        FROM information_schema.statistics
        WHERE table_schema = DATABASE()
          AND table_name = ?
          AND index_name = ?
    ]], { tableName, indexName })

    if not ok then
        return false, result
    end

    return (tonumber(result) or 0) > 0
end

local function renameTableIfNeeded(oldName, newName)
    local oldExists, oldErr = tableExists(oldName)
    if oldErr then
        return false, oldErr
    end

    local newExists, newErr = tableExists(newName)
    if newErr then
        return false, newErr
    end

    if not oldExists or newExists then
        return true
    end

    if not MySQL or not MySQL.query or not MySQL.query.await then
        return false, 'MySQL.query.await unavailable'
    end

    local sql = ('RENAME TABLE `%s` TO `%s`'):format(oldName, newName)
    local ok, err = pcall(MySQL.query.await, sql, {})
    if not ok then
        return false, err
    end

    print(('[sofapotato_gearbox] 已將資料表 `%s` 重新命名為 `%s`'):format(oldName, newName))
    return true
end

local function ensureColumnExists(tableName, columnName, definitionSql)
    local exists, err = columnExists(tableName, columnName)
    if err then
        return false, err
    end

    if exists then
        return true
    end

    if not MySQL or not MySQL.query or not MySQL.query.await then
        return false, 'MySQL.query.await unavailable'
    end

    local sql = ('ALTER TABLE `%s` ADD COLUMN %s'):format(tableName, definitionSql)
    local ok, queryErr = pcall(MySQL.query.await, sql, {})
    if not ok then
        return false, queryErr
    end

    return true
end

local function ensurePlayerSettingsIndex()
    local newIndexExists, newIndexErr = indexExists(PLAYER_SETTINGS_TABLE, 'uq_player_vehicle_scope')
    if newIndexErr then
        return false, newIndexErr
    end

    local oldIndexExists, oldIndexErr = indexExists(PLAYER_SETTINGS_TABLE, 'uq_player_vehicle')
    if oldIndexErr then
        return false, oldIndexErr
    end

    if oldIndexExists then
        local dropOk, dropErr = pcall(
            MySQL.query.await,
            ('ALTER TABLE `%s` DROP INDEX `uq_player_vehicle`'):format(PLAYER_SETTINGS_TABLE),
            {}
        )
        if not dropOk then
            return false, dropErr
        end
    end

    if not newIndexExists then
        local addOk, addErr = pcall(
            MySQL.query.await,
            ('ALTER TABLE `%s` ADD UNIQUE KEY `uq_player_vehicle_scope` (`citizenid`, `vehicle_plate`, `vehicle_model`)')
                :format(PLAYER_SETTINGS_TABLE),
            {}
        )
        if not addOk then
            return false, addErr
        end
    end

    return true
end

local function ensureSchema()
    if not MySQL or not MySQL.query or not MySQL.query.await then
        return false, 'MySQL.query.await unavailable'
    end

    local ok, err = renameTableIfNeeded(LEGACY_PLAYER_SETTINGS_TABLE, PLAYER_SETTINGS_TABLE)
    if not ok then
        return false, err
    end

    ok, err = renameTableIfNeeded(LEGACY_UNLOCKED_TRANSMISSIONS_TABLE, UNLOCKED_TRANSMISSIONS_TABLE)
    if not ok then
        return false, err
    end

    local queries = {
        ([[CREATE TABLE IF NOT EXISTS `%s` (
            `id`            INT           AUTO_INCREMENT PRIMARY KEY,
            `citizenid`     VARCHAR(50)   NOT NULL,
            `vehicle_model` VARCHAR(50)   NOT NULL DEFAULT 'default',
            `vehicle_plate` VARCHAR(16)   NOT NULL DEFAULT '*',
            `transmission`  VARCHAR(20)   NOT NULL DEFAULT 'STOCK',
            `clutch_health` FLOAT         NOT NULL DEFAULT 100.0,
            `gear_ratios`   JSON          NULL,
            `handling_overrides` JSON     NULL,
            `updated_at`    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                          ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY `uq_player_vehicle_scope` (`citizenid`, `vehicle_plate`, `vehicle_model`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]])
            :format(PLAYER_SETTINGS_TABLE),
        ([[CREATE TABLE IF NOT EXISTS `%s` (
            `id`           INT          AUTO_INCREMENT PRIMARY KEY,
            `citizenid`    VARCHAR(50)  NOT NULL,
            `transmission` VARCHAR(20)  NOT NULL,
            `unlocked_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY `uq_citizen_transm` (`citizenid`, `transmission`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]])
            :format(UNLOCKED_TRANSMISSIONS_TABLE),
    }

    for i = 1, #queries do
        local runOk, runErr = pcall(MySQL.query.await, queries[i], {})
        if not runOk then
            return false, runErr
        end
    end

    local okColumn, errColumn = ensureColumnExists(
        PLAYER_SETTINGS_TABLE,
        'vehicle_plate',
        "`vehicle_plate` VARCHAR(16) NOT NULL DEFAULT '*' AFTER `vehicle_model`"
    )
    if not okColumn then
        return false, errColumn
    end

    okColumn, errColumn = ensureColumnExists(
        PLAYER_SETTINGS_TABLE,
        'handling_overrides',
        "`handling_overrides` JSON NULL AFTER `gear_ratios`"
    )
    if not okColumn then
        return false, errColumn
    end

    local indexOk, indexErr = ensurePlayerSettingsIndex()
    if not indexOk then
        return false, indexErr
    end

    return true
end

CreateThread(function()
    local required = { 'sp_bridge', 'oxmysql', 'ox_lib' }
    local ok       = true

    for _, dep in ipairs(required) do
        if GetResourceState(dep) ~= 'started' then
            print(('[sofapotato_gearbox] ❌ 缺少依賴：%s，請先啟動！'):format(dep))
            ok = false
        end
    end

    if not ok then
        StopResource(GetCurrentResourceName())
        return
    end

    local mysqlReady = MySQL and MySQL.ready
    if mysqlReady and mysqlReady.await then
        local readyOk, readyErr = pcall(mysqlReady.await)
        if not readyOk then
            print(('[sofapotato_gearbox] ❌ 等待資料庫連線失敗：%s'):format(tostring(readyErr)))
        else
            local schemaOk, schemaErr = ensureSchema()
            if schemaOk then
                _G.SP_GEARBOX_SCHEMA_READY = true
                print('[sofapotato_gearbox] ✅ 資料表檢查完成')
            else
                print(('[sofapotato_gearbox] ❌ 資料表檢查失敗：%s'):format(tostring(schemaErr)))
            end
        end
    elseif MySQL and MySQL.query and MySQL.query.await then
        local schemaOk, schemaErr = ensureSchema()
        if schemaOk then
            _G.SP_GEARBOX_SCHEMA_READY = true
            print('[sofapotato_gearbox] ✅ 資料表檢查完成')
        else
            print(('[sofapotato_gearbox] ❌ 資料表檢查失敗：%s'):format(tostring(schemaErr)))
        end
    else
        print('[sofapotato_gearbox] ⚠ 無法執行資料表檢查：MySQL await API unavailable')
    end

    print('[sofapotato_gearbox] ✅ 依賴確認完成，系統啟動')
end)
