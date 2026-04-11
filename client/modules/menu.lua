-- ─────────────────────────────────────────────────────
-- 變速箱設定選單（專屬 NUI，不依賴 ox_lib context menu）
-- ─────────────────────────────────────────────────────

local _menuOpen = false

-- ── 前提檢查 ──────────────────────────────────────────
local function CanOpenMenu(showError)
    local state = GearboxState

    if not state.inVehicle or state.vehicle == 0 or not DoesEntityExist(state.vehicle) then
        if showError then
            exports['sp_bridge']:Notify(GetLocale('MenuNeedVehicle'), 'error')
        end
        return false
    end

    if GetPedInVehicleSeat(state.vehicle, -1) ~= PlayerPedId() then
        if showError then
            exports['sp_bridge']:Notify(GetLocale('MenuNeedDriverSeat'), 'error')
        end
        return false
    end

    if not state.transmKey or state.transmKey == '' then
        if showError then
            exports['sp_bridge']:Notify(GetLocale('MenuNotReady'), 'error')
        end
        return false
    end

    return true
end

-- ── 取得目前齒比（含玩家自訂覆蓋） ───────────────────
local GEAR_FIELD_NAMES = {
    'fGearRatioFirst', 'fGearRatioSecond', 'fGearRatioThird',
    'fGearRatioFourth', 'fGearRatioFifth', 'fGearRatioSixth',
    'fGearRatioSeventh', 'fGearRatioEighth',
}

local function GetCurrentGearRatios(cfg, handlingOverrides)
    if not cfg or not cfg.gearRatios or not cfg.maxGear then
        return {}, {}
    end
    local current  = {}
    local defaults = {}
    for i = 1, cfg.maxGear do
        local field    = GEAR_FIELD_NAMES[i]
        local override = field and handlingOverrides and tonumber(handlingOverrides[field])
        current[i]  = override or cfg.gearRatios[i] or 1.0
        defaults[i] = cfg.gearRatios[i] or 1.0
    end
    return current, defaults
end

-- ── 組裝目前狀態 payload ──────────────────────────────
local function BuildStatePayload()
    local state   = GearboxState
    local cfg     = GetActiveTransmissionConfig() or state.cfg
    local isMT    = cfg ~= nil and cfg.type == GearboxConst.Type.MT
    local isStock = IsStockTransmissionKey(state.transmKey)

    local gearRatios, defaultGearRatios = {}, {}
    if not isStock and cfg then
        gearRatios, defaultGearRatios = GetCurrentGearRatios(cfg, state.handlingOverrides)
    end

    return {
        transmKey         = state.transmKey or '',
        transmLabel       = cfg and cfg.label or GetLocale('MenuStockClutch'),
        transmType        = cfg and cfg.type  or '',
        transmMaxGear     = cfg and cfg.maxGear or 0,
        clutchHealth      = math.floor(state.clutchHealth or 100),
        gearboxTemp       = math.floor(state.gearboxTemp  or 0),
        antiStall         = state.antiStall   or false,
        revMatch          = state.revMatch    or false,
        driftEnabled      = state.driftEnabled or false,
        launchPrepped     = state.launchPrepped or false,
        launchEnabled     = Config.Launch.enabled and (
            cfg ~= nil and (
                cfg.type == GearboxConst.Type.AT or
                cfg.type == GearboxConst.Type.ATMT
            )
        ) or false,
        isStock           = isStock,
        isMT              = isMT,
        vehicleModel      = state.modelName or '',
        gearRatios        = gearRatios,
        defaultGearRatios = defaultGearRatios,
    }
end

-- ── 組裝已解鎖的變速箱列表（settings 模式） ───────────
local function BuildUnlockedTransmissions()
    local state = GearboxState
    local list  = {}

    -- 原廠
    list[#list + 1] = {
        key        = GetStockTransmissionKey(),
        label      = GetLocale('MenuStockClutch'),
        gears      = 0,
        transmType = '',
        unlocked   = true,
        isCurrent  = IsStockTransmissionKey(state.transmKey),
        isStock    = true,
    }

    -- 已解鎖的自訂變速箱（依名稱排序）
    local sorted = {}
    for key, cfg in pairs(Config.Transmissions) do
        if IsTransmissionUnlocked(key) then
            sorted[#sorted + 1] = { key = key, cfg = cfg }
        end
    end
    table.sort(sorted, function(a, b) return a.cfg.label < b.cfg.label end)

    for _, entry in ipairs(sorted) do
        list[#list + 1] = {
            key        = entry.key,
            label      = entry.cfg.label,
            gears      = entry.cfg.maxGear,
            transmType = entry.cfg.type,
            unlocked   = true,
            isCurrent  = (entry.key == state.transmKey),
            isStock    = false,
        }
    end

    return list
end

-- ── 開啟設定選單（F6 按鍵觸發） ──────────────────────
function OpenGearboxMenu()
    if not CanOpenMenu(true) then return end

    local state = GearboxState
    local cfg   = GetActiveTransmissionConfig() or state.cfg

    SendNUIMessage({
        action        = 'gearbox:open',
        mode          = 'settings',
        state         = BuildStatePayload(),
        transmissions = BuildUnlockedTransmissions(),
        canRepair     = cfg ~= nil and state.clutchHealth < 100.0,
        repairCost    = Config.Clutch.repairCost,
    })

    SetNuiFocus(true, true)
    _menuOpen = true
end

-- ── 更換變速箱型號（NUI callback + 升級模組共用） ─────
function ChangeTransmission(key)
    local state    = GearboxState
    local useStock = IsStockTransmissionKey(key)
    local cfg      = useStock and nil or Config.Transmissions[key]

    if not useStock and not cfg then return end

    state.isNeutral     = false
    state.isShifting    = false
    state.launchActive  = false
    state.launchPrepped = false

    if useStock then
        ApplyTransmissionState(state.vehicle, key)
    else
        ApplyTransmissionState(state.vehicle, key)
    end

    TriggerServerEvent(GearboxConst.Events.SAVE_SETTINGS, {
        vehicleNetId      = state.vehicleNetId,
        vehicleModel      = state.modelName,
        vehiclePlate      = state.vehiclePlate,
        transmKey         = key,
        clutchHealth      = useStock and 100.0 or state.clutchHealth,
        handlingOverrides = useStock and nil or state.handlingOverrides,
    })

    exports['sp_bridge']:Notify(
        useStock and GetLocale('MenuStockClutch') or cfg.label,
        'success'
    )
end

-- ── NUI Callbacks ─────────────────────────────────────
RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    _menuOpen = false
    cb('ok')
end)

RegisterNUICallback('changeTransmission', function(data, cb)
    SetNuiFocus(false, false)
    _menuOpen = false
    if type(data.key) == 'string' and data.key ~= '' then
        ChangeTransmission(data.key)
    end
    cb('ok')
end)

RegisterNUICallback('toggleAssist', function(data, cb)
    local state  = GearboxState
    local assist = data.assist

    if assist == 'antiStall' then
        state.antiStall    = not state.antiStall
    elseif assist == 'revMatch' then
        state.revMatch     = not state.revMatch
    elseif assist == 'driftMode' then
        state.driftEnabled = not state.driftEnabled
    end

    -- 將最新狀態回傳給 NUI，讓 bar 數值即時更新
    local cfg = GetActiveTransmissionConfig() or state.cfg
    SendNUIMessage({
        action     = 'gearbox:updateState',
        state      = BuildStatePayload(),
        canRepair  = cfg ~= nil and state.clutchHealth < 100.0,
        repairCost = Config.Clutch.repairCost,
    })

    cb('ok')
end)

RegisterNUICallback('repairClutch', function(_, cb)
    SetNuiFocus(false, false)
    _menuOpen = false
    local state = GearboxState
    TriggerServerEvent(GearboxConst.Events.REPAIR_CLUTCH, {
        vehicleNetId = state.vehicleNetId,
        vehicleModel = state.modelName,
        vehiclePlate = state.vehiclePlate,
    })
    cb('ok')
end)

RegisterNUICallback('confirmBuy', function(data, cb)
    SetNuiFocus(false, false)
    _menuOpen = false
    if type(data.key) == 'string' and data.key ~= '' then
        TriggerServerEvent(GearboxConst.Events.BUY_UPGRADE, data.key)
    end
    cb('ok')
end)

-- ── 套用玩家自訂齒比 ──────────────────────────────────
RegisterNUICallback('applyGearRatios', function(data, cb)
    local state = GearboxState
    local cfg   = GetActiveTransmissionConfig() or state.cfg
    if not cfg or IsStockTransmissionKey(state.transmKey) then
        cb('nok')
        return
    end

    local ratios = data.ratios
    if type(ratios) ~= 'table' then cb('nok') return end

    -- 合併到既有 overrides（保留極速等其他覆蓋）
    local newOverrides = {}
    for k, v in pairs(state.handlingOverrides or {}) do
        newOverrides[k] = v
    end

    for i, ratio in ipairs(ratios) do
        local field = GEAR_FIELD_NAMES[i]
        if field and i <= cfg.maxGear then
            newOverrides[field] = math.clamp(tonumber(ratio) or 1.0, 0.10, 20.0)
        end
    end

    -- Phase 3：menu 不再自行計算 fInitialDriveMaxFlatVel / handling 極速欄位。
    -- 極速與扭力統一由 snapshot + perGearCache（core/gear_ratios.lua）管理。
    state.handlingOverrides = newOverrides

    -- 以新齒比建立臨時 cfg，交給 core 套用（一次重建 cache + 套用到車輛）
    local tmpCfg = {}
    for k, v in pairs(cfg) do tmpCfg[k] = v end
    local mergedRatios = {}
    for i = 1, cfg.maxGear do
        local field = GEAR_FIELD_NAMES[i]
        mergedRatios[i] = (field and newOverrides[field]) or cfg.gearRatios[i] or 1.0
    end
    tmpCfg.gearRatios = mergedRatios

    ApplyGearRatiosToVehicle(state.vehicle, tmpCfg, newOverrides)
    GB.State.speedLimitDirty = true

    -- 同步儲存
    TriggerServerEvent(GearboxConst.Events.SAVE_SETTINGS, {
        vehicleNetId      = state.vehicleNetId,
        vehicleModel      = state.modelName,
        vehiclePlate      = state.vehiclePlate,
        transmKey         = state.transmKey,
        clutchHealth      = state.clutchHealth,
        handlingOverrides = newOverrides,
    })

    exports['sp_bridge']:Notify(GetLocale('GearRatioApplied') or '齒比已套用', 'success')
    cb('ok')
end)
