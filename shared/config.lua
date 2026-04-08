Config = {}

-- ─────────────────────────────────────────────────────
-- 全域設定
-- ─────────────────────────────────────────────────────
Config.Debug              = false
Config.F8GearDebug        = true
Config.UseNativeATLogic   = false     -- 純 AT 改由腳本控制升降檔
Config.RatioMode          = 'realistic'  -- 'custom' = 齒比自由玩法；'realistic' = 齒比/終傳自動縮放極速與驅動力
Config.HudEnabled         = true
Config.DefaultTransmission = 'AT_5'   -- 保留給舊邏輯/手動指定使用；未安裝時預設走原廠 handling
Config.PersistPerVehicle  = true      -- 每台車記住各自設定
Config.MTStartInNeutral   = true      -- MT 進車時預設停在空檔

-- 輔助功能（玩家可在選單中切換）
Config.AntiStallAssist    = false     -- 防熄火輔助
Config.RevMatchAssist     = false     -- 轉速匹配輔助（降檔補油）

-- 引擎煞車強度（0.0 停用 ～ 1.0 最強）
Config.EngineBrakingStrength = 0.35

-- ─────────────────────────────────────────────────────
-- 按鍵預設值（RegisterKeyMapping 使用）
-- ─────────────────────────────────────────────────────
Config.Keys = {
    ShiftUp      = { default = 'UP',       label = '升檔'         },
    ShiftDown    = { default = 'DOWN',     label = '降檔'         },
    Clutch       = { default = 'LCONTROL', label = '離合器'       },
    Neutral      = { default = 'X',        label = '空檔切換'     },
    OpenMenu     = { default = 'F6',       label = '變速箱設定'   },
    LaunchCancel = { default = 'L',        label = '取消起步控制' },
}

-- ─────────────────────────────────────────────────────
-- 離合器設定
-- ─────────────────────────────────────────────────────
Config.Clutch = {
    engageSpeed      = 4.0,   -- 放離合速率（/s），越高越快接合
    disengageSpeed   = 8.0,   -- 踩離合速率（/s），越高越快切斷

    -- 磨損量（每次事件增加的耐久度損失）
    wearNormal       = 0.05,  -- 正常完整換檔
    wearHalf         = 0.20,  -- 半離合換檔
    wearDump         = 0.50,  -- 猛放離合器
    wearSlipPerSec   = 0.08,  -- 持續半離合（每秒）

    -- 維修費用（bank）
    repairCost       = 5000,
    repairTimeMs     = 5000,
}

-- ─────────────────────────────────────────────────────
-- 溫度系統
-- ─────────────────────────────────────────────────────
Config.Temperature = {
    enabled              = true,
    halfClutchRiseRate   = 1.5,   -- 半離合時每秒上升 °C
    shiftAbuseRise       = 0.8,   -- 每次不正確換檔上升 °C
    cooldownRate         = 0.5,   -- 每秒冷卻 °C（靜止）
    speedCooldownBonus   = 0.02,  -- 每 m/s 額外冷卻（車速散熱）
    -- 過熱懲罰
    overheatShiftPenalty = 100,   -- 額外換檔延遲（ms）
}

-- ─────────────────────────────────────────────────────
-- 渦輪遲滯
-- ─────────────────────────────────────────────────────
Config.Turbo = {
    spoolRate = 0.8,    -- 渦輪建壓速率（/s）
    dropRate  = 3.0,    -- 渦輪壓力下降速率（換檔/鬆油後）
    -- 各車輛是否有渦輪由 Transmissions 的 turbo = true 欄位決定
}

-- ─────────────────────────────────────────────────────
-- 漂移模式（Clutch Kick）
-- ─────────────────────────────────────────────────────
Config.Drift = {
    enabled   = true,  -- 全域開關（MT 玩家均可使用）
    kickForce = 1.2,   -- 側向衝擊力倍率（越大越容易觸發甩尾）
}

-- ─────────────────────────────────────────────────────
-- 起步控制（Launch Control）
-- ─────────────────────────────────────────────────────
Config.Launch = {
    enabled       = true,
    launchRpm     = 0.72,   -- 起步保持的轉速（0.0~1.0）
    blazeWindowMs = 2000,   -- 起步後鎖 1 檔的全力時間窗口（ms）
}

-- ─────────────────────────────────────────────────────
-- 換檔音效廣播
-- ─────────────────────────────────────────────────────
Config.Sounds = {
    broadcastEnabled = true,  -- 廣播換檔 RPM 給附近玩家（讓他們也聽到引擎音效）
}

-- ─────────────────────────────────────────────────────
-- 變速箱升級系統
-- ─────────────────────────────────────────────────────
Config.Upgrade = {
    enabled = true,

    -- tier：數字越大越高級；price：購買費用（bank）
    -- tier 1 永遠免費可用，無需購買
    tiers = {
        ['AT_4']   = { tier = 1, price = 0      },
        ['AT_5']   = { tier = 2, price = 12000  },
        ['AT_6']   = { tier = 3, price = 28000  },
        ['ATMT_6'] = { tier = 4, price = 50000  },
        ['ATMT_7'] = { tier = 5, price = 72000  },
        ['ATMT_8'] = { tier = 6, price = 100000 },
        ['MT_4']   = { tier = 2, price = 15000  },
        ['MT_5']   = { tier = 3, price = 32000  },
        ['MT_6']   = { tier = 4, price = 55000  },
        ['MT_7']   = { tier = 5, price = 80000  },
    },

    -- ox_target 互動區域（修車廠 NPC 位置）
    locations = {
        {
            coords  = vector3(243.810990, -785.854920, 30.493042),  -- Los Santos Customs
            radius  = 3.5,
            label   = 'Los Santos Customs',
        },
        -- 可新增更多地點：
        -- { coords = vector3(...), radius = 3.0, label = '...' },
    },
}

-- ─────────────────────────────────────────────────────
-- 變速箱型號定義
-- ─────────────────────────────────────────────────────
Config.Transmissions = {

    -- ══════════ 自排 AT ══════════

    ['AT_4'] = {
        label        = '4速自排',
        type         = GearboxConst.Type.AT,
        maxGear      = 4,
        gearRatios   = { 5.50, 4.06, 3.31, 2.90 },
        finalDrive   = 3.80,
        upshiftRpm   = 0.82,
        downshiftRpm = 0.42,
        shiftDelay   = 180,   -- 換檔鎖定 ms
        revDropRate  = 0.25,  -- 升檔後轉速回落速率
        maxSpeedRatio = 0.80, -- 相對原廠極速比例（短齒比 4 速，限制在 80% 極速）
    },
    ['AT_5'] = {
        label        = '5速自排',
        type         = GearboxConst.Type.AT,
        maxGear      = 5,
        gearRatios   = { 3.50, 2.20, 1.50, 1.00, 0.75 },
        finalDrive   = 3.60,
        upshiftRpm   = 0.84,
        downshiftRpm = 0.42,
        shiftDelay   = 160,
        revDropRate  = 0.28,
        maxSpeedRatio = 0.95, -- 接近原廠極速
    },
    ['AT_6'] = {
        label        = '6速自排',
        type         = GearboxConst.Type.AT,
        maxGear      = 6,
        gearRatios   = { 3.80, 2.40, 1.60, 1.15, 0.85, 0.65 },
        finalDrive   = 3.50,
        upshiftRpm   = 0.86,
        downshiftRpm = 0.40,
        shiftDelay   = 140,
        revDropRate  = 0.30,
        turbo        = false,  -- 設為 true 可啟用渦輪遲滯
        maxSpeedRatio = 1.05, -- 6 速 OD 齒比稍高於原廠
    },

    -- ══════════ 手自排 AT/MT ══════════

    ['ATMT_6'] = {
        label       = '6速手自排',
        type        = GearboxConst.Type.ATMT,
        maxGear     = 6,
        gearRatios  = { 3.50, 2.10, 1.45, 1.05, 0.78, 0.58 },
        finalDrive  = 3.40,
        shiftDelay  = 80,
        revDropRate = 0.30,
        maxSpeedRatio = 1.10,
    },
    ['ATMT_7'] = {
        label       = '7速手自排',
        type        = GearboxConst.Type.ATMT,
        maxGear     = 7,
        gearRatios  = { 4.00, 2.50, 1.65, 1.22, 0.95, 0.76, 0.60 },
        finalDrive  = 3.20,
        shiftDelay  = 70,
        revDropRate = 0.28,
        maxSpeedRatio = 1.15,
    },
    ['ATMT_8'] = {
        label       = '8速手自排',
        type        = GearboxConst.Type.ATMT,
        maxGear     = 8,
        gearRatios  = { 4.71, 3.14, 2.10, 1.67, 1.29, 1.00, 0.84, 0.67 },
        finalDrive  = 3.15,
        shiftDelay  = 60,
        revDropRate = 0.25,
        turbo       = true,   -- 高階手自排預設有渦輪
        maxSpeedRatio = 1.20,
    },

    -- ══════════ 手排 MT ══════════

    ['MT_4'] = {
        label             = '4速手排',
        type              = GearboxConst.Type.MT,
        maxGear           = 4,
        gearRatios        = { 3.60, 2.10, 1.35, 0.95 },
        finalDrive        = 4.00,
        shiftDelay        = 220,
        revDropRate       = 0.35,
        minClutchToShift  = 0.70,  -- 需要的最低離合器深度
        stallChance       = 0.30,  -- 未踩離合換檔時的熄火機率
        stallRpm          = 0.08,  -- 低於此轉速有熄火風險
        maxSpeedRatio     = 0.75, -- 短齒比 4 速手排，極速受限
    },
    ['MT_5'] = {
        label             = '5速手排',
        type              = GearboxConst.Type.MT,
        maxGear           = 5,
        gearRatios        = { 3.50, 2.05, 1.39, 1.04, 0.78 },
        finalDrive        = 3.90,
        shiftDelay        = 200,
        revDropRate       = 0.33,
        minClutchToShift  = 0.70,
        stallChance       = 0.30,
        stallRpm          = 0.08,
        maxSpeedRatio     = 0.90,
    },
    ['MT_6'] = {
        label             = '6速手排',
        type              = GearboxConst.Type.MT,
        maxGear           = 6,
        gearRatios        = { 3.65, 2.11, 1.44, 1.07, 0.82, 0.62 },
        finalDrive        = 3.70,
        shiftDelay        = 190,
        revDropRate       = 0.32,
        minClutchToShift  = 0.70,
        stallChance       = 0.25,
        stallRpm          = 0.08,
        maxSpeedRatio     = 1.00,
    },
    ['MT_7'] = {
        label             = '7速手排',
        type              = GearboxConst.Type.MT,
        maxGear           = 7,
        gearRatios        = { 4.20, 2.60, 1.78, 1.32, 1.00, 0.79, 0.62 },
        finalDrive        = 3.50,
        shiftDelay        = 180,
        revDropRate       = 0.30,
        minClutchToShift  = 0.70,
        stallChance       = 0.20,
        stallRpm          = 0.08,
        maxSpeedRatio     = 1.12,
    },
}

-- ─────────────────────────────────────────────────────
-- 車輛 model → 變速箱型號（model 名稱請用小寫）
-- 未設定的車輛預設為原廠離合器（不套用自訂 handling）
-- ─────────────────────────────────────────────────────
Config.VehicleTransmissions = {
    -- ['sultan']    = 'MT_6',
    -- ['elegy2']    = 'ATMT_6',
    -- ['adder']     = 'AT_6',
    -- ['bf400']     = 'MT_5',
}

-- ─────────────────────────────────────────────────────
-- 車輛原廠 Handling 手動基準值
-- 用途：GetVehicleModelMaxSpeed 對改裝/addon 車輛可能回傳 0，
--       導致腳本從已被修改的 entity 讀取錯誤的 maxFlatVel（例如殘留的每檔速度值）。
--       在此填入正確的原廠 handling.meta 數值可完全迴避此問題。
-- 填寫方式：開啟車輛的 handling.meta，找到對應 handlingId 的項目：
--   maxFlatVel  → fInitialDriveMaxFlatVel（km/h）
--   driveForce  → fInitialDriveForce
-- ─────────────────────────────────────────────────────
Config.VehicleStockHandling = {
    ['ferrari pis'] = { maxFlatVel = 273.6, driveForce = 0.28816 },
    -- ['sultan']     = { maxFlatVel = 160.0, driveForce = 0.38    },
}
