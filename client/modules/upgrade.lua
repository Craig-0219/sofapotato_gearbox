-- ─────────────────────────────────────────────────────
-- 車行變速箱升級系統（ox_target 互動區域 + 專屬 NUI）
-- ─────────────────────────────────────────────────────

-- ── 初始化 ox_target 互動區域 ────────────────────────
CreateThread(function()
    if not Config.Upgrade.enabled then return end

    Wait(2000)  -- 等待 ox_target 就緒

    for i, loc in ipairs(Config.Upgrade.locations) do
        exports['ox_target']:addSphereZone({
            coords  = loc.coords,
            radius  = loc.radius,
            name    = ('gearbox_upgrade_%d'):format(i),
            options = {
                {
                    label    = GetLocale('UpgradeLabel'),
                    icon     = 'fa-solid fa-gears',
                    distance = loc.radius,
                    onSelect = function()
                        OpenUpgradeMenu()
                    end,
                },
            },
        })
    end
end)

-- ── 開啟升級選單（NUI 升級模式） ─────────────────────
function OpenUpgradeMenu()
    local state = GearboxState

    -- 所有變速箱依 tier 排序
    local sorted = {}
    for key, info in pairs(Config.Upgrade.tiers) do
        local cfg = Config.Transmissions[key]
        if cfg then
            sorted[#sorted + 1] = { key = key, info = info, cfg = cfg }
        end
    end
    table.sort(sorted, function(a, b) return a.info.tier < b.info.tier end)

    local transmissions = {}
    for _, entry in ipairs(sorted) do
        local key  = entry.key
        local info = entry.info
        local cfg  = entry.cfg
        transmissions[#transmissions + 1] = {
            key        = key,
            label      = cfg.label,
            gears      = cfg.maxGear,
            transmType = cfg.type,
            price      = info.price,
            tier       = info.tier,
            unlocked   = IsTransmissionUnlocked(key),
            isCurrent  = (state.transmKey == key),
            isStock    = false,
        }
    end

    -- 目前狀態（供左側面板顯示）
    local activeCfg = GetActiveTransmissionConfig() or state.cfg
    local isMT = activeCfg ~= nil and activeCfg.type == GearboxConst.Type.MT

    SendNUIMessage({
        action  = 'gearbox:open',
        mode    = 'upgrade',
        state   = {
            transmKey     = state.transmKey or '',
            transmLabel   = activeCfg and activeCfg.label or GetLocale('MenuStockClutch'),
            transmType    = activeCfg and activeCfg.type or '',
            transmMaxGear = activeCfg and activeCfg.maxGear or 0,
            clutchHealth  = math.floor(state.clutchHealth or 100),
            gearboxTemp   = math.floor(state.gearboxTemp  or 0),
            isStock       = IsStockTransmissionKey(state.transmKey),
            isMT          = isMT,
            vehicleModel  = state.modelName or '',
            antiStall     = false,
            revMatch      = false,
            driftEnabled  = false,
            launchPrepped = false,
            launchEnabled = false,
        },
        transmissions = transmissions,
        canRepair     = false,
        repairCost    = 0,
    })

    SetNuiFocus(true, true)
end

-- ── 判斷是否已解鎖（本地快取） ───────────────────────
function IsTransmissionUnlocked(key)
    if IsStockTransmissionKey(key) then
        return true
    end

    for _, k in ipairs(GearboxState.unlockedTransmissions) do
        if k == key then return true end
    end

    -- Tier 1 永遠免費可用
    local info = Config.Upgrade.tiers[key]
    return info and info.tier <= 1
end

-- ── 接收購買結果 ──────────────────────────────────────
RegisterNetEvent(GearboxConst.Events.UNLOCK_RESULT)
AddEventHandler(GearboxConst.Events.UNLOCK_RESULT, function(success, key, reason)
    if success then
        -- 避免重複加入清單（已解鎖的型號再次觸發）
        local list = GearboxState.unlockedTransmissions
        local already = false
        for _, k in ipairs(list) do
            if k == key then already = true break end
        end
        if not already then
            list[#list + 1] = key
        end

        local cfg = Config.Transmissions[key]
        exports['sp_bridge']:Notify(
            GetLocale('UpgradeSuccess'):format(cfg and cfg.label or key),
            'success'
        )

        -- 若玩家在車內（駕駛座）自動裝備
        local state = GearboxState
        if state.inVehicle and state.vehicle ~= 0 and DoesEntityExist(state.vehicle)
            and GetPedInVehicleSeat(state.vehicle, -1) == PlayerPedId()
        then
            ChangeTransmission(key)
        else
            exports['sp_bridge']:Notify(GetLocale('UpgradeEquipHint'), 'inform')
        end
    else
        local msg = (reason == 'insufficient_funds')
            and GetLocale('UpgradeNoFunds')
            or  GetLocale('UpgradeFailed')
        exports['sp_bridge']:Notify(msg, 'error')
    end
end)
