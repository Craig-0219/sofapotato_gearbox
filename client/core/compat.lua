-- ═══════════════════════════════════════════════════════════════
-- client/core/compat.lua
-- 相容橋接層
--
-- 用途：提供舊模組（hud、menu、damage、upgrade、sounds 等）所依賴的
--       全域函式，對應到新架構的等效實作。
--
-- 這個檔案在新架構穩定後可逐步縮減，最終刪除。
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- GetLocale(key) → 多語系字串
-- ─────────────────────────────────────────────────────────────
function GetLocale(key)
    local loc = Locales and (Locales['zh-TW'] or Locales['en'])
    return loc and loc[key] or key
end

-- ─────────────────────────────────────────────────────────────
-- IsVehicleReversingState(vehicle) → bool
-- ─────────────────────────────────────────────────────────────
function IsVehicleReversingState(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local vel = GetEntitySpeedVector(vehicle, true)
    if (vel.y or 0.0) < -0.15 then return true end
    return GetVehicleThrottleOffset(vehicle) < -0.10
end

-- ─────────────────────────────────────────────────────────────
-- ApplyTransmissionState(vehicle, transmKey, handlingOverrides)
-- 舊 menu.lua 和 damage.lua 呼叫，路由到新核心
-- handlingOverrides 參數在新架構中由 gear_ratios.lua 內部處理，
-- 此處接受但忽略（不再每幀計算，改由 BuildPerGearCache 一次性計算）
-- ─────────────────────────────────────────────────────────────
function ApplyTransmissionState(vehicle, transmKey, handlingOverrides)
    if not vehicle or vehicle == 0 then return end
    GB.Core.ChangeTransmission(transmKey)
end

-- ─────────────────────────────────────────────────────────────
-- RestoreVehicleGearHandling(vehicle)
-- 路由到新核心
-- ─────────────────────────────────────────────────────────────
function RestoreVehicleGearHandling(vehicle)
    GB.GearRatios.RestoreSnapshot(vehicle)
end

-- ─────────────────────────────────────────────────────────────
-- GetEffectiveShiftDelay() → ms
-- 舊 gearbox.lua 呼叫，現在由 gearbox_core 內部使用；
-- 保留空殼以防有外部呼叫
-- ─────────────────────────────────────────────────────────────
function GetEffectiveShiftDelay()
    return GB.Core.GetShiftDelay(GB.State.cfg)
end

-- ─────────────────────────────────────────────────────────────
-- WearClutch / WearClutchOnShift
-- damage.lua 定義了這兩個函式，但也有地方從外部呼叫；
-- 保持向前相容（damage.lua 先載入，此處不覆蓋）
-- ─────────────────────────────────────────────────────────────
-- damage.lua 仍是 modules/damage.lua，WearClutch 由它定義

-- ─────────────────────────────────────────────────────────────
-- GetVehicleSignedForwardSpeed(vehicle) → m/s
-- 被 drift.lua 等模組使用
-- ─────────────────────────────────────────────────────────────
function GetVehicleSignedForwardSpeed(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return 0.0 end
    local vel = GetEntitySpeedVector(vehicle, true)
    return vel.y or 0.0
end

-- ─────────────────────────────────────────────────────────────
-- Lerp(a, b, t) → number
-- 很多舊模組直接用這個工具函式
-- ─────────────────────────────────────────────────────────────
function Lerp(a, b, t)
    return a + (b - a) * math.min(1.0, math.max(0.0, t))
end

-- ─────────────────────────────────────────────────────────────
-- OpenGearboxMenu() → 觸發 menu.lua 開啟選單
-- 保留向後相容（menu.lua 自己定義這個函式）
-- ─────────────────────────────────────────────────────────────
-- menu.lua 會定義 OpenGearboxMenu，不需要在這裡定義

-- ─────────────────────────────────────────────────────────────
-- 舊 AT / ATMT / MT 的 Shift 函式（input.lua 的 RegisterCommand 呼叫的是
-- 新 main.lua 定義的 TriggerShift，這裡不需要 ShiftATMT / ShiftMT）
-- ─────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────
-- EnforceTransmissionGearLimit
-- 舊 state.lua 的函式，仍被一些尚未遷移的地方呼叫；
-- 路由到新核心的安全版本
-- ─────────────────────────────────────────────────────────────
function EnforceTransmissionGearLimit(vehicle, cfg)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if type(cfg) ~= 'table' or not cfg.maxGear then return end
    -- 新架構由 gearbox_core.Tick() 的 SyncGear 負責每幀同步，
    -- 這裡只做安全截斷（超出 maxGear 的情況）
    if type(SetVehicleHighGear) == 'function' then
        SetVehicleHighGear(vehicle, cfg.maxGear)
    end
end

-- ─────────────────────────────────────────────────────────────
-- IsStockTransmissionKey / GetStockTransmissionKey
-- ─────────────────────────────────────────────────────────────
function IsStockTransmissionKey(key)
    return tostring(key or '') == 'STOCK'
end

function GetStockTransmissionKey()
    return 'STOCK'
end

-- ─────────────────────────────────────────────────────────────
-- RefreshActiveTransmissionRuntimeConfig
-- 舊 state.lua 的函式，menu.lua 會呼叫
-- ─────────────────────────────────────────────────────────────
function RefreshActiveTransmissionRuntimeConfig()
    -- 新架構不使用 runtimeCfg，齒比在 BuildPerGearCache 一次計算
    -- 回傳 cfg 本身保持相容
    return GB.State.cfg
end

-- ─────────────────────────────────────────────────────────────
-- BuildTransmissionHandlingOverrides
-- menu.lua 的齒比手動調整功能呼叫此函式
-- 在新架構中，handling 由 gear_ratios.lua 統一管理
-- ─────────────────────────────────────────────────────────────
function BuildTransmissionHandlingOverrides(cfg, handlingBackup, modelName)
    -- 轉接到新的 gear_ratios 系統
    -- 回傳一個空表（實際套用改由 GB.GearRatios.ApplyToVehicle 負責）
    return {}
end

-- ─────────────────────────────────────────────────────────────
-- ApplyGearRatiosToVehicle（menu.lua 的齒比調整功能）
-- ─────────────────────────────────────────────────────────────
function ApplyGearRatiosToVehicle(vehicle, cfg, handlingOverrides)
    if not cfg then return end
    GB.State.cfg = cfg
    GB.GearRatios.BuildPerGearCache(cfg, GB.State.handlingSnapshot)
    GB.GearRatios.ApplyToVehicle(vehicle, cfg)
end

-- ─────────────────────────────────────────────────────────────
-- ApplyManualNeutralStartIfNeeded(vehicle)
-- 舊 state.lua 的函式，damage.lua 的 SYNC_SETTINGS 事件呼叫
-- ─────────────────────────────────────────────────────────────
function ApplyManualNeutralStartIfNeeded(vehicle)
    local state = GB.State
    if Config.MTStartInNeutral == false then return false end
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local cfg = state.cfg
    if type(cfg) ~= 'table' or cfg.type ~= GearboxConst.Type.MT then return false end
    GB.Core.SetNeutral(true)
    return true
end

-- ─────────────────────────────────────────────────────────────
-- NormalizeVehiclePlate(plate)
-- 舊模組用到的工具函式
-- ─────────────────────────────────────────────────────────────
function NormalizeVehiclePlate(plate)
    if type(plate) ~= 'string' then return '*' end
    local normalized = plate:gsub('^%s+', ''):gsub('%s+$', '')
    return (normalized == '') and '*' or string.upper(normalized)
end

-- ─────────────────────────────────────────────────────────────
-- ApplyVehicleHandlingOverrides(vehicle, handlingOverrides)
-- menu.lua 的齒比手動微調呼叫此函式
-- 在新架構中，handling 由 gear_ratios.lua 管理；
-- 此函式做簡化版的套用（只設 fGearRatioXxx 和 fInitialDriveMaxFlatVel）
-- ─────────────────────────────────────────────────────────────
local _RATIO_FIELD_TO_INDEX = {
    fGearRatioFirst = 1, fGearRatioSecond = 2, fGearRatioThird = 3,
    fGearRatioFourth = 4, fGearRatioFifth = 5, fGearRatioSixth = 6,
    fGearRatioSeventh = 7, fGearRatioEighth = 8,
}

function ApplyVehicleHandlingOverrides(vehicle, handlingOverrides)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if type(handlingOverrides) ~= 'table' then return end

    for field, value in pairs(handlingOverrides) do
        local ratioIndex = _RATIO_FIELD_TO_INDEX[field]
        if ratioIndex and type(value) == 'number' and type(SetVehicleGearRatio) == 'function' then
            SetVehicleGearRatio(vehicle, ratioIndex, value)
        elseif field == 'fInitialDriveMaxFlatVel' and type(value) == 'number' then
            if type(SetVehicleHandlingFloat) == 'function' then
                SetVehicleHandlingFloat(vehicle, 'CHandlingData', field, value)
            end
        elseif field == 'fInitialDriveForce' and type(value) == 'number' then
            if type(SetVehicleHandlingFloat) == 'function' then
                SetVehicleHandlingFloat(vehicle, 'CHandlingData', field, value)
                GB.State._appliedDriveForce = value
            end
        elseif field == 'nInitialDriveGears' and type(value) == 'number' then
            if type(SetVehicleHandlingInt) == 'function' then
                SetVehicleHandlingInt(vehicle, 'CHandlingData', field, math.floor(value))
            end
            if type(SetVehicleHighGear) == 'function' then
                SetVehicleHighGear(vehicle, math.floor(value))
            end
        end
    end

    -- 重建 per-gear cache（齒比可能已被手動修改）
    local cfg = GB.State.cfg
    if cfg then
        -- 從 handlingOverrides 更新 cfg.gearRatios（臨時）
        local newRatios = {}
        for i = 1, (cfg.maxGear or 8) do
            newRatios[i] = cfg.gearRatios[i] or 1.0
        end
        for field, value in pairs(handlingOverrides) do
            local idx = _RATIO_FIELD_TO_INDEX[field]
            if idx and type(value) == 'number' then
                newRatios[idx] = value
            end
        end
        -- 建立臨時 cfg 副本（不修改原 Config.Transmissions 的表）
        local tmpCfg = {}
        for k, v in pairs(cfg) do tmpCfg[k] = v end
        tmpCfg.gearRatios = newRatios
        GB.GearRatios.BuildPerGearCache(tmpCfg, GB.State.handlingSnapshot)
        -- 同步 dirty flag（換檔後更新頂速）
        GB.State.speedLimitDirty = true
    end
end
