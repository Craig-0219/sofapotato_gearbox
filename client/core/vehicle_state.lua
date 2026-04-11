-- ═══════════════════════════════════════════════════════════════
-- client/core/vehicle_state.lua
-- 全域狀態表（唯一真相來源）
-- 職責：狀態定義、欄位語義文件、init/reset
-- 不負責：任何計算邏輯、native 呼叫
-- ═══════════════════════════════════════════════════════════════

math.clamp = math.clamp or function(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- ── 全域命名空間 ──────────────────────────────────────────────
GB = GB or {}

-- ── 相容性橋接（讓舊模組繼續讀 GearboxState）─────────────────
-- 舊模組（hud.lua、menu.lua、sounds.lua 等）讀寫 GearboxState
-- 新模組使用 GB.State
-- 讓兩者指向同一個表，零修改成本相容舊代碼
-- 注意：此 alias 在 GB.State 表建立後才設定（見本檔結尾）

-- ═══════════════════════════════════════════════════════════════
-- 欄位語義分類：
--   [SCRIPT]      腳本是唯一真相，native 只能讀來參考，不能覆蓋
--   [NATIVE_READ] 每幀從 GTA 讀取的輸入，不寫回
--   [NATIVE_SYNC] 腳本計算後需同步到 GTA（但 GTA 可能有自己的邏輯）
--   [NATIVE_REF]  從 GTA 讀取作為參考，不是決策依據
-- ═══════════════════════════════════════════════════════════════

-- 初始值（reset 的參考模板）
local STATE_DEFAULTS = {
    -- ── 車輛識別 ─────────────────────────────────────────────
    vehicle           = 0,       -- [SCRIPT] entity handle
    vehicleNetId      = 0,       -- [SCRIPT] 網路 ID（事件用）
    modelName         = '',      -- [SCRIPT] 小寫 model 名稱
    vehiclePlate      = '',      -- [SCRIPT] 正規化車牌
    inVehicle         = false,   -- [SCRIPT] 是否在駕駛座

    -- ── 變速箱設定 ──────────────────────────────────────────
    transmKey         = 'STOCK', -- [SCRIPT] 型號 key
    cfg               = nil,     -- [SCRIPT] 完整設定表（唯讀參考）
    -- perGearCache: 進車/換檔時預算的每檔數值，避免每幀重算
    -- { [gear] = { topSpeedMps, torqueScale } }
    perGearCache      = nil,     -- [SCRIPT] 由 gear_ratios.lua 填入

    -- ── 檔位狀態（腳本真相）────────────────────────────────
    currentGear       = 1,       -- [SCRIPT] 腳本當前檔位（1-indexed）
    desiredGear       = 1,       -- [SCRIPT] 玩家/AT 期望目標（換檔中才與 current 不同）
    isNeutral         = false,   -- [SCRIPT] 空檔（MT 專用）
    isShifting        = false,   -- [SCRIPT] 換檔中旗標（屏蔽新換檔請求）
    shiftLockUntil    = 0,       -- [SCRIPT] 換檔冷卻結束時間（ms，與 GetGameTimer 比較）

    -- 原生追蹤（只在 AT 模式用於跟蹤 GTA 自己的選擇）
    nativeGear        = 1,       -- [NATIVE_REF] GetVehicleCurrentGear 最新值

    -- ── 離合器 ──────────────────────────────────────────────
    -- 語義：0.0 = 完全放開（動力接合），1.0 = 完全踩下（動力切斷）
    -- GTA SetVehicleClutch 語義相反（1.0=接合），轉換公式：nativeClutch = 1.0 - clutchAxis
    clutchAxis        = 0.0,     -- [SCRIPT] 離合器軸位置（鍵盤模式為 0/1）
    clutchKeyDown     = false,   -- [SCRIPT] 離合鍵是否按下（input.lua 寫入）
    clutchHealth      = 100.0,   -- [SCRIPT] 離合器耐久 0~100
    clutchSlipSec     = 0.0,     -- [SCRIPT] 半離合累積秒數（鍵盤模式為 0）

    -- ── 引擎 / 轉速 ─────────────────────────────────────────
    engineOn          = false,   -- [NATIVE_SYNC] 每幀從 IsVehicleEngineOn 同步

    -- ATMT/MT 模式：腳本計算並寫回 GTA
    -- AT 模式：直接讀 GetVehicleCurrentRpm，不寫回
    rpm               = 0.12,    -- [SCRIPT for ATMT/MT] 腳本 RPM（0.0~1.0）
    targetRpm         = 0.12,    -- [SCRIPT] RPM lerp 目標
    stallTimer        = 0,       -- [SCRIPT] 熄火風險計時器 ms

    -- ── 每幀輸入（從 GTA 讀取，不修改）────────────────────
    throttleInput     = 0.0,     -- [NATIVE_READ] 油門軸位
    brakeInput        = false,   -- [NATIVE_READ] 剎車鍵
    vehicleSpeed      = 0.0,     -- [NATIVE_READ] 前向速度 m/s（水平分量）
    reversing         = false,   -- [NATIVE_READ] 是否在倒退

    -- ── 物理附屬 ────────────────────────────────────────────
    gearboxTemp       = 20.0,    -- [SCRIPT] 溫度 °C
    turboBoost        = 0.0,     -- [SCRIPT] 渦輪建壓 0.0~1.0
    launchActive      = false,   -- [SCRIPT] 起步控制啟動
    launchPrepped     = false,   -- [SCRIPT] 起步控制預備

    -- ── 輔助功能 ────────────────────────────────────────────
    antiStall         = false,
    revMatch          = false,
    driftEnabled      = true,

    -- ── Handling 快照（進車時讀取，只讀）────────────────────
    -- handlingSnapshot: { maxFlatVel(km/h), driveForce, gearRatios[], highGear }
    handlingSnapshot  = nil,

    -- ── Dirty 旗標（減少 native 呼叫次數）──────────────────
    -- speedLimitDirty: 換檔後需更新 SetVehicleMaxSpeed（設 true → native_adapter 處理）
    speedLimitDirty   = true,
    -- gearNativeDirty: ATMT/MT 需強制同步 SetVehicleCurrentGear
    gearNativeDirty   = true,

    -- ── Feature 請求（功能模組只能寫請求，不可直寫 native）──
    -- 結構：
    -- featureRequests = {
    --   rpmOverride = { [source] = rpm01 },
    --   gearLock    = { [source] = gear },
    --   tractionScale = { [source] = scale01_to_1_5 },
    -- }
    featureRequests   = nil,

    -- ── 解鎖清單（從 server 載入，跨車保留）────────────────
    unlockedTransmissions = {},
}

-- ═══════════════════════════════════════════════════════════════
-- 狀態表實例（全域，所有模組共用）
-- ═══════════════════════════════════════════════════════════════
GB.State = {}

-- ─────────────────────────────────────────────────────────────
-- GB.State.Init(vehicle)
-- 進車時呼叫，重設並填入車輛資訊
-- ─────────────────────────────────────────────────────────────
function GB.State.Init(vehicle)
    -- 複製預設值
    for k, v in pairs(STATE_DEFAULTS) do
        GB.State[k] = v
    end

    -- 解鎖清單跨車保留（不重設）
    -- GB.State.unlockedTransmissions 保持原樣

    -- 填入車輛識別
    local modelHash = GetEntityModel(vehicle)
    local modelName = string.lower(GetDisplayNameFromVehicleModel(modelHash))
    local plate     = GetVehicleNumberPlateText(vehicle) or ''
    plate = plate:gsub('^%s+', ''):gsub('%s+$', '')
    plate = (plate == '') and '*' or string.upper(plate)

    GB.State.vehicle      = vehicle
    GB.State.vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
    GB.State.modelName    = modelName
    GB.State.vehiclePlate = plate
    GB.State.inVehicle    = true

    -- 同步初始引擎狀態和 RPM
    GB.State.engineOn  = IsVehicleEngineOn(vehicle)
    GB.State.rpm       = GetVehicleCurrentRpm(vehicle)
    GB.State.targetRpm = GB.State.rpm

    -- 初始 antiStall / revMatch 從 Config 讀取
    GB.State.antiStall   = Config.AntiStallAssist or false
    GB.State.revMatch    = Config.RevMatchAssist   or false
    GB.State.driftEnabled = (Config.Drift and Config.Drift.enabled) or true

    -- 初始速度
    local vel = GetEntitySpeedVector(vehicle, true)
    GB.State.vehicleSpeed = math.max(0.0, vel.y or 0.0)

    GB.State.featureRequests = {
        rpmOverride   = {},
        gearLock      = {},
        tractionScale = {},
    }
end

-- ─────────────────────────────────────────────────────────────
-- GB.State.Reset()
-- 離車時呼叫
-- ─────────────────────────────────────────────────────────────
function GB.State.Reset()
    local savedUnlocked = GB.State.unlockedTransmissions
    for k, v in pairs(STATE_DEFAULTS) do
        GB.State[k] = v
    end
    GB.State.unlockedTransmissions = savedUnlocked
    GB.State.inVehicle = false
    GB.State.vehicle   = 0
end

-- ─────────────────────────────────────────────────────────────
-- GB.State.IsManualMode()
-- 是否為手動控制模式（ATMT 或 MT）
-- ─────────────────────────────────────────────────────────────
function GB.State.IsManualMode()
    local cfg = GB.State.cfg
    if not cfg then return false end
    return cfg.type == GearboxConst.Type.ATMT or cfg.type == GearboxConst.Type.MT
end

-- ─────────────────────────────────────────────────────────────
-- GB.State.IsMTMode()
-- ─────────────────────────────────────────────────────────────
function GB.State.IsMTMode()
    local cfg = GB.State.cfg
    return cfg and cfg.type == GearboxConst.Type.MT
end

-- ─────────────────────────────────────────────────────────────
-- GB.State.IsATMode()
-- ─────────────────────────────────────────────────────────────
function GB.State.IsATMode()
    local cfg = GB.State.cfg
    return cfg and cfg.type == GearboxConst.Type.AT
end

-- ─────────────────────────────────────────────────────────────
-- GB.State.MaxGear()
-- ─────────────────────────────────────────────────────────────
function GB.State.MaxGear()
    local cfg = GB.State.cfg
    return cfg and cfg.maxGear or 1
end

-- ─────────────────────────────────────────────────────────────
-- GB.State.ClutchDisengaged()
-- 離合器是否切斷動力（包含空檔）
-- ─────────────────────────────────────────────────────────────
function GB.State.ClutchDisengaged()
    return GB.State.isNeutral or GB.State.clutchAxis >= 0.65
end

-- ─────────────────────────────────────────────────────────────
-- GB.State.EffectiveClutchAxis()
-- 考慮離合器耐久後的有效軸位（磨損越嚴重，clutch 效果越差）
-- ─────────────────────────────────────────────────────────────
function GB.State.EffectiveClutchAxis()
    local healthFactor = GB.State.clutchHealth / 100.0
    return GB.State.clutchAxis * healthFactor
end

-- ─────────────────────────────────────────────────────────────
-- GB.State.ReadInputs()
-- 每幀從 GTA 讀取輸入值（集中在此，方便測試 mock）
-- ─────────────────────────────────────────────────────────────
function GB.State.ReadInputs()
    local v = GB.State.vehicle
    if v == 0 or not DoesEntityExist(v) then return end

    -- 油門：取 GTA 回報與原始按鍵輸入的最大值
    -- 原因：某些情況下 GTA 高檔位靜止時會把 throttle offset 鎖死為 0
    local nativeThrottle = GetVehicleThrottleOffset(v)
    local rawKey         = GetControlNormal(0, 71)
    GB.State.throttleInput = math.max(0.0, nativeThrottle, rawKey)

    -- 剎車
    GB.State.brakeInput = IsControlPressed(0, 72)

    -- 前向速度（水平分量，排除 Z 軸避免地形起伏 spike）
    local vel = GetEntitySpeedVector(v, true)
    GB.State.vehicleSpeed = math.max(0.0, vel.y or 0.0)

    -- 倒退判斷
    GB.State.reversing = (vel.y or 0.0) < -0.15
        or GetVehicleThrottleOffset(v) < -0.10

    -- 引擎狀態同步
    GB.State.engineOn = IsVehicleEngineOn(v)
end

-- ═══════════════════════════════════════════════════════════════
-- 相容性 alias（必須在 GB.State 表建立後設定）
-- 舊模組直接讀寫 GearboxState.xxx，新模組用 GB.State.xxx
-- 兩者指向同一表，零相容成本
-- ═══════════════════════════════════════════════════════════════
GearboxState = GB.State

-- ─────────────────────────────────────────────────────────────
-- handlingBackup 相容 getter
-- menu.lua 讀 GearboxState.handlingBackup.maxFlatVel（km/h 值）
-- 新架構存在 GB.State.handlingSnapshot.maxFlatVelKmh
-- 用 metatble 的 __index 在讀 handlingBackup 時轉接到 handlingSnapshot
-- ─────────────────────────────────────────────────────────────
do
    local _stateMeta = getmetatable(GB.State) or {}
    local _prevIndex = _stateMeta.__index

    _stateMeta.__index = function(t, k)
        if k == 'handlingBackup' then
            -- 返回一個代理表，.maxFlatVel 讀 handlingSnapshot.maxFlatVelKmh
            local snap = rawget(t, 'handlingSnapshot')
            if not snap then return nil end
            return setmetatable({}, {
                __index = function(_, field)
                    if field == 'maxFlatVel' then
                        return snap.maxFlatVelKmh
                    elseif field == 'driveForce' then
                        return snap.driveForce
                    elseif field == 'gearRatios' then
                        return snap.gearRatios
                    elseif field == 'highGear' then
                        return snap.highGear
                    elseif field == 'vehicle' then
                        return snap.vehicle
                    end
                    return snap[field]
                end,
                __newindex = function(_, field, val)
                    -- 允許 menu.lua 寫入（忽略，防止報錯）
                end,
            })
        end
        if _prevIndex then return _prevIndex(t, k) end
        return nil
    end

    setmetatable(GB.State, _stateMeta)
end
