-- ─────────────────────────────────────────────────────
-- 伺服器端：變速箱升級購買驗證
-- ─────────────────────────────────────────────────────

local UNLOCKED_TRANSMISSIONS_TABLE = 'sp_gearbox_unlocked_transmissions'

RegisterNetEvent(GearboxConst.Events.BUY_UPGRADE, function(transmKey)
    local src = source

    -- 驗證傳入的 key
    local upgradeInfo = Config.Upgrade.tiers[transmKey]
    if not upgradeInfo then
        TriggerClientEvent(GearboxConst.Events.UNLOCK_RESULT, src, false, transmKey, 'invalid_key')
        return
    end

    local citizenId = exports['sp_bridge']:GetCitizenId(src)
    if not citizenId then
        TriggerClientEvent(GearboxConst.Events.UNLOCK_RESULT, src, false, transmKey, 'no_citizen')
        return
    end

    local price = upgradeInfo.price

    -- 檢查是否已解鎖
    MySQL.scalar(
        ('SELECT COUNT(*) FROM %s WHERE citizenid = ? AND transmission = ?')
            :format(UNLOCKED_TRANSMISSIONS_TABLE),
        { citizenId, transmKey },
        function(count)
            if (tonumber(count) or 0) > 0 then
                -- 已解鎖，直接通知（不扣款）
                TriggerClientEvent(GearboxConst.Events.UNLOCK_RESULT, src, true, transmKey, nil)
                return
            end

            -- Tier 1 免費
            if upgradeInfo.tier <= 1 then
                InsertUnlock(src, citizenId, transmKey)
                return
            end

            -- 扣款
            local money = exports['sp_bridge']:GetMoney(src, 'bank')
            if money < price then
                TriggerClientEvent(GearboxConst.Events.UNLOCK_RESULT, src, false, transmKey, 'insufficient_funds')
                return
            end

            exports['sp_bridge']:RemoveMoney(src, 'bank', price, 'gearbox_upgrade_' .. transmKey)
            InsertUnlock(src, citizenId, transmKey)
        end
    )
end)

function InsertUnlock(src, citizenId, transmKey)
    MySQL.insert(
        ('INSERT IGNORE INTO %s (citizenid, transmission) VALUES (?, ?)')
            :format(UNLOCKED_TRANSMISSIONS_TABLE),
        { citizenId, transmKey },
        function()
            TriggerClientEvent(GearboxConst.Events.UNLOCK_RESULT, src, true, transmKey, nil)
        end
    )
end
