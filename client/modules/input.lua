-- ─────────────────────────────────────────────────────
-- 按鍵綁定
-- RegisterKeyMapping 使用 +/- command 支援 hold 行為
-- ─────────────────────────────────────────────────────

local INPUT_NOTIFY_COOLDOWN_MS = 1200
local _lastInputNotifyAt = 0
local _lastInputNotifyKey = nil

local function NotifyInputBlocked(localeKey)
    local now = GetGameTimer()
    if _lastInputNotifyKey == localeKey and (now - _lastInputNotifyAt) < INPUT_NOTIFY_COOLDOWN_MS then
        return
    end

    _lastInputNotifyAt = now
    _lastInputNotifyKey = localeKey
    exports['sp_bridge']:Notify(GetLocale(localeKey), 'error')
end

local function GetBoundTransmissionConfig()
    return (GetActiveTransmissionConfig and GetActiveTransmissionConfig()) or GearboxState.cfg
end

-- ── 離合器（Hold 模式）────────────────────────────────
RegisterCommand('+gearbox_clutch', function()
    if not GearboxState.inVehicle then return end

    local cfg = GetBoundTransmissionConfig()
    if not cfg then
        NotifyInputBlocked('InputNeedTransmission')
        return
    end

    if cfg.type ~= GearboxConst.Type.MT then
        NotifyInputBlocked('InputClutchMtOnly')
        return
    end

    GearboxState.clutchKeyDown = true
end, false)

RegisterCommand('-gearbox_clutch', function()
    GearboxState.clutchKeyDown = false
end, false)

RegisterKeyMapping('+gearbox_clutch', Config.Keys.Clutch.label, 'keyboard', Config.Keys.Clutch.default)

-- ── 升檔 ───────────────────────────────────────────────
RegisterCommand('gearbox_shiftup', function()
    if not GearboxState.inVehicle then return end

    local cfg = GetBoundTransmissionConfig()
    if not cfg then
        NotifyInputBlocked('InputNeedTransmission')
        return
    end

    if cfg.type == GearboxConst.Type.AT then
        NotifyInputBlocked('InputShiftManualOnly')
        return
    end

    TriggerShift(GearboxConst.ShiftDir.UP)
end, false)

RegisterKeyMapping('gearbox_shiftup', Config.Keys.ShiftUp.label, 'keyboard', Config.Keys.ShiftUp.default)

-- ── 降檔 ───────────────────────────────────────────────
RegisterCommand('gearbox_shiftdown', function()
    if not GearboxState.inVehicle then return end

    local cfg = GetBoundTransmissionConfig()
    if not cfg then
        NotifyInputBlocked('InputNeedTransmission')
        return
    end

    if cfg.type == GearboxConst.Type.AT then
        NotifyInputBlocked('InputShiftManualOnly')
        return
    end

    TriggerShift(GearboxConst.ShiftDir.DOWN)
end, false)

RegisterKeyMapping('gearbox_shiftdown', Config.Keys.ShiftDown.label, 'keyboard', Config.Keys.ShiftDown.default)

-- ── 空檔切換（MT 專用）────────────────────────────────
RegisterCommand('gearbox_neutral', function()
    if not GearboxState.inVehicle then return end
    local cfg = GetBoundTransmissionConfig()
    if not cfg then
        NotifyInputBlocked('InputNeedTransmission')
        return
    end

    if cfg.type ~= GearboxConst.Type.MT then
        NotifyInputBlocked('InputNeutralMtOnly')
        return
    end

    ToggleNeutral()
end, false)

RegisterKeyMapping('gearbox_neutral', Config.Keys.Neutral.label, 'keyboard', Config.Keys.Neutral.default)

-- ── 設定選單 ───────────────────────────────────────────
local function TryOpenMenu()
    if not GearboxState.inVehicle then
        exports['sp_bridge']:Notify(GetLocale('MenuNeedVehicle'), 'error')
        BeginTextCommandDisplayHelp('STRING')
        AddTextComponentSubstringPlayerName(GetLocale('MenuNeedVehicle'))
        EndTextCommandDisplayHelp(0, false, true, 3000)
        return
    end
    OpenGearboxMenu()
end

RegisterCommand('gearbox_menu', TryOpenMenu, false)
RegisterKeyMapping('gearbox_menu', Config.Keys.OpenMenu.label, 'keyboard', Config.Keys.OpenMenu.default)

-- 短指令別名
RegisterCommand('gearbox', TryOpenMenu, false)

-- ── 除錯：強制套用變速箱型號（F8 輸入，需 Config.F8GearDebug = true）─
if Config.F8GearDebug then
    RegisterCommand('gearset', function(src, args)
        if not GearboxState.inVehicle then
            print('[gearbox][DEBUG] gearset: 請先進入車輛駕駛座')
            return
        end
        local key = args[1]
        if not key then
            print('[gearbox][DEBUG] 用法: gearset <型號>')
            print('[gearbox][DEBUG] 可用: AT_4 AT_5 AT_6 ATMT_6 ATMT_7 ATMT_8 MT_4 MT_5 MT_6 MT_7 STOCK')
            return
        end
        if key ~= 'STOCK' and not Config.Transmissions[key] then
            print('[gearbox][DEBUG] gearset: 找不到型號 [' .. tostring(key) .. ']')
            return
        end
        print('[gearbox][DEBUG] gearset → ' .. key)
        ChangeTransmission(key)
    end, false)
end
