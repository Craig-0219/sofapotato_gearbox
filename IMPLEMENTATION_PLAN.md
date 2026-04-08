# sofapotato_gearbox — 擬真變速箱系統 實作計劃書

> 版本：0.1.0 草稿
> 狀態：規劃中
> 作者：SofaPotato Team

---

## 一、功能總覽

| 功能 | 說明 |
|------|------|
| 三種變速箱類型 | 自排（AT）、手自排（AT/MT）、手排（MT） |
| 離合器輸入 | MT 必須踩離合才能換檔，否則不換且有機率熄火 |
| 多檔位配置 | 每種類型支援 4/5/6/7/8 速設定 |
| 可調齒比 | 每個檔位的齒比可獨立設定，影響加速/極速 |
| 換檔物理反饋 | 轉速回落、頓挫感、急加速換檔衝擊 |
| 離合器磨損 | 離合器耐久度會因操作習慣消耗，影響換檔效果 |
| 持久化設定 | 每台車或每個玩家可保存偏好設定 |

---

## 二、變速箱類型定義

### 2.1 自排（Automatic Transmission / AT）

| 屬性 | 說明 |
|------|------|
| 換檔方式 | 系統自動依轉速/速度換檔 |
| 離合器 | 無需操作（內部自動控制） |
| 可用檔位數 | 4速 / 5速 / 6速 |
| 齒比範圍 | 視等級不同，越高速越高擋位差距小 |

自動換檔觸發條件：
- 升檔：當轉速 > `upshiftRpm`（可調，預設 0.85）
- 降檔：當轉速 < `downshiftRpm`（可調，預設 0.45）
- 緊急降檔：急踩油門時下降至最低有效擋

### 2.2 手自排（Semi-Automatic / Paddle Shift / AT/MT）

| 屬性 | 說明 |
|------|------|
| 換檔方式 | 手動換檔，**不需要**踩離合 |
| 離合器 | 內部電子控制（玩家無需操作） |
| 可用檔位數 | 6速 / 7速 / 8速 |
| 特性 | 換檔有短暫延遲（~80ms 電子切換時間） |

### 2.3 手排（Manual Transmission / MT）

| 屬性 | 說明 |
|------|------|
| 換檔方式 | **必須先踩離合**，再換檔，再放離合 |
| 離合器 | 玩家控制（按鍵模擬踩踏板深度） |
| 可用檔位數 | 4速 / 5速 / 6速 / 7速 |
| 特性 | 最高自由度，最高風險，最高操駕樂趣 |

MT 離合器邏輯：
- `clutchValue` = 0.0（完全放開）→ 1.0（完全踩下）
- 換檔需要 `clutchValue >= Config.MT.minClutchToShift`（建議 0.7）
- 未達門檻強行換檔 → 換檔失敗，有機率熄火

---

## 三、技術架構

### 3.1 使用的 FiveM Natives

```lua
-- 轉速
GetVehicleCurrentRpm(vehicle)          -- 0.0 ~ 1.0
SetVehicleCurrentRpm(vehicle, rpm)     -- 強制設定轉速

-- 檔位
GetVehicleCurrentGear(vehicle)         -- 0=倒退, 1=1檔, 2=2檔...
SetVehicleCurrentGear(vehicle, gear)   -- 強制設定檔位
GetVehicleHighGear(vehicle)            -- 最高檔位
SetVehicleHighGear(vehicle, gears)     -- 設定最高檔位

-- 離合器
GetVehicleClutch(vehicle)              -- 0.0 ~ 1.0
SetVehicleClutch(vehicle, value)       -- 設定離合器

-- 油門 / 引擎
GetVehicleThrottleOffset(vehicle)      -- 0.0 ~ 1.0（油門量）
IsVehicleEngineOn(vehicle)
SetVehicleEngineOn(vehicle, bool, instant, doDisableSiren)

-- 速度 / 健康
GetEntitySpeed(vehicle)                -- m/s
GetVehicleEngineHealth(vehicle)        -- 0 ~ 1000
SetVehicleEngineHealth(vehicle, value)

-- 齒比（Handling）
GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fGearRatioFirst')
SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fGearRatioFirst', value)
-- fGearRatioFirst ~ fGearRatioEight（GTA 支援最多 8 速）
GetVehicleHandlingInt(vehicle, 'CHandlingData', 'nInitialDriveGears')
```

### 3.2 資料結構設計

```lua
-- 變速箱狀態（每台車，客戶端本地）
GearboxState = {
    vehicleNetId    = 0,
    type            = 'MT',      -- 'AT' | 'ATMT' | 'MT'
    config          = {},        -- 當前使用的 TransmissionConfig
    currentGear     = 1,
    targetGear      = 1,
    isShifting      = false,     -- 換檔動作中（鎖定期間）
    shiftCooldown   = 0,         -- 換檔冷卻計時器（毫秒）
    clutchValue     = 0.0,       -- 離合器深度 0.0~1.0
    clutchHealth    = 100.0,     -- 離合器耐久度 0~100
    clutchSlip      = 0.0,       -- 離合器滑動量（磨損後增加）
    rpm             = 0.0,       -- 模擬轉速 0.0~1.0
    stallTimer      = 0,         -- 引擎快熄火計時器
    lastThrottle    = 0.0,
}

-- 變速箱配置（存放在 Config）
TransmissionConfig = {
    type            = 'MT',
    maxGear         = 6,
    gearRatios      = { 3.5, 2.1, 1.4, 1.0, 0.75, 0.55 },  -- 各檔齒比
    finalDrive      = 3.4,       -- 最終傳動比
    upshiftRpm      = 0.85,      -- AT 自動升檔轉速
    downshiftRpm    = 0.40,      -- AT 自動降檔轉速
    shiftDelay      = 150,       -- 換檔鎖定時間（ms）
    revDropRate     = 0.3,       -- 換檔後轉速下落速率
    stallRpm        = 0.08,      -- 低於此轉速有熄火風險
    minClutchToShift = 0.7,      -- MT 換檔需要的最低離合器深度
    stallChance     = 0.35,      -- 未踩離合強行換檔熄火機率
    clutchWearRate  = 0.001,     -- 每次換檔離合器磨損量
    clutchDumpPenalty = 0.5,     -- 猛放離合器的頓挫係數
}
```

### 3.3 資料夾結構

```
sofapotato_gearbox/
├── fxmanifest.lua
├── README.md
├── CHANGELOG.md
├── IMPLEMENTATION_PLAN.md
│
├── shared/
│   ├── config.lua              # 全域設定、各變速箱型號定義
│   ├── constants.lua           # Event names, enum
│   └── locales/
│       ├── zh-TW.lua
│       └── en.lua
│
├── client/
│   ├── main.lua                # 入口：車輛偵測、狀態機初始化
│   └── modules/
│       ├── input.lua           # 按鍵綁定（離合器/升降檔）
│       ├── clutch.lua          # 離合器輸入模擬與深度計算
│       ├── gearbox.lua         # 換檔邏輯（AT/ATMT/MT 三套）
│       ├── physics.lua         # 轉速模擬、頓挫感、引擎煞車
│       ├── damage.lua          # 離合器磨損與效能衰退
│       ├── stall.lua           # 熄火偵測與恢復
│       └── hud.lua             # 儀表顯示（齒比、檔位、離合器）
│
├── server/
│   ├── main.lua
│   ├── bootstrap.lua
│   └── modules/
│       ├── persistence.lua     # 儲存玩家/車輛設定到 oxmysql
│       └── repair.lua          # 離合器維修（NPC 或物品）
│
└── server/sql/migrations/
    └── 001_init.sql            # player_gearbox_settings 資料表
```

---

## 四、核心物理邏輯說明

### 4.1 MT 換檔流程（狀態機）

```
[駕駛中]
    │
    ├─ 玩家按 [升檔/降檔]
    │       │
    │       ├─ clutchValue >= minClutchToShift？
    │       │     YES → 進入換檔序列
    │       │     NO  → 換檔失敗 ─────────────────┐
    │       │                                      │
    │       └─ 換檔序列：                         │
    │             1. isShifting = true             │
    │             2. SetVehicleClutch(1.0)         │
    │             3. RPM 回落動畫（revDropRate）   │
    │             4. SetVehicleCurrentGear(new)    │
    │             5. 等待 shiftDelay ms            │
    │             6. isShifting = false            │
    │             7. 釋放離合器                    │
    │                                              │
    └─ 換檔失敗後邏輯：◄─────────────────────────┘
          ─ 產生頓挫（SetVehicleClutch 模擬）
          ─ 隨機 stallChance → 觸發 stall.lua
```

### 4.2 轉速模擬公式

```
理論轉速（模擬值 0.0~1.0）：
rpm = (speed × gearRatio × finalDrive) / maxEngineRpm

換檔後轉速回落：
newRpm = rpm × (gearRatios[newGear] / gearRatios[oldGear])

頓挫感（未鬆油門換檔）：
if throttle > 0.3 and not clutchPressed then
    jerkForce = (throttle - 0.3) × 0.4
    ApplyForceToEntity(vehicle, 5, 0.0, -jerkForce, 0.0, ...)
end
```

### 4.3 離合器磨損模型

| 行為 | 磨損量 |
|------|--------|
| 正常換檔（完全踩下） | `+0.05` |
| 半離合換檔（不完全踩下） | `+0.2` |
| 猛放離合器（快速釋放） | `+0.5` |
| 長時間半離合（起步滑行） | 每秒 `+0.1` |

離合器效能隨耐久降低：
```lua
effectiveClutch = clutchValue * (clutchHealth / 100.0)
-- 耐久 50% → 同樣踩到底只有 0.5 的效果
-- 耐久 0% → 換檔完全失效，需維修
```

### 4.4 AT 自動換檔邏輯

```lua
-- 每幀執行
if rpm > upshiftRpm and currentGear < maxGear then
    Shift(currentGear + 1)
elseif rpm < downshiftRpm and currentGear > 1 then
    Shift(currentGear - 1)
end

-- 急加速降檔（kickdown）
if throttle > 0.9 and rpm < 0.5 and currentGear > 1 then
    Shift(currentGear - 1)  -- 強制降一檔提升加速力
end
```

---

## 五、設定檔結構（config.lua 摘要）

```lua
Config = {}

-- 全域設定
Config.DefaultType = 'AT'          -- 未設定車輛使用此類型
Config.HudEnabled = true
Config.PersistPerVehicle = true    -- true=每台車記住設定, false=跟玩家走

-- AT 型號定義
Config.Transmissions = {
    ['AT_4'] = {
        label = '4速自排',
        type = 'AT',
        maxGear = 4,
        gearRatios = { 3.5, 2.0, 1.3, 0.9 },
        finalDrive = 3.8,
        upshiftRpm = 0.82, downshiftRpm = 0.42,
    },
    ['AT_5'] = {
        label = '5速自排',
        type = 'AT',
        maxGear = 5,
        gearRatios = { 3.5, 2.2, 1.5, 1.0, 0.75 },
        finalDrive = 3.6,
        upshiftRpm = 0.84, downshiftRpm = 0.42,
    },
    ['AT_6'] = {
        label = '6速自排',
        type = 'AT',
        maxGear = 6,
        gearRatios = { 3.8, 2.4, 1.6, 1.15, 0.85, 0.65 },
        finalDrive = 3.5,
        upshiftRpm = 0.86, downshiftRpm = 0.40,
    },

    -- AT/MT 型號
    ['ATMT_6'] = {
        label = '6速手自排',
        type = 'ATMT',
        maxGear = 6,
        gearRatios = { 3.5, 2.1, 1.45, 1.05, 0.78, 0.58 },
        finalDrive = 3.4,
        shiftDelay = 80,    -- 更快的電子換檔
    },
    ['ATMT_7'] = { ... },
    ['ATMT_8'] = { ... },

    -- MT 型號
    ['MT_4'] = {
        label = '4速手排',
        type = 'MT',
        maxGear = 4,
        gearRatios = { 3.6, 2.1, 1.35, 0.95 },
        finalDrive = 4.0,
        minClutchToShift = 0.7,
        stallChance = 0.30,
        shiftDelay = 200,
    },
    ['MT_5'] = { ... },
    ['MT_6'] = { ... },
    ['MT_7'] = { ... },
}

-- 車輛對應變速箱（model hash → transmission key）
Config.VehicleTransmissions = {
    ['sultan']    = 'MT_6',
    ['elegy2']    = 'ATMT_6',
    ['adder']     = 'AT_6',
    -- 未設定的車輛使用 Config.DefaultType
}
```

---

## 六、資料庫設計

```sql
-- 001_init.sql
CREATE TABLE IF NOT EXISTS `gearbox_player_settings` (
    `id`            INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid`     VARCHAR(50)  NOT NULL,
    `vehicle_model` VARCHAR(50)  NOT NULL,   -- 或 'default' 代表玩家預設
    `transmission`  VARCHAR(20)  NOT NULL,   -- 對應 Config.Transmissions key
    `clutch_health` FLOAT        NOT NULL DEFAULT 100.0,
    `gear_ratios`   JSON         NULL,        -- NULL=使用預設齒比
    `updated_at`    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_player_vehicle` (`citizenid`, `vehicle_model`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

---

## 七、按鍵綁定（預設）

| 動作 | 預設按鍵 | 備註 |
|------|---------|------|
| 升檔 | `Scroll Up` / `E` | 可設定 |
| 降檔 | `Scroll Down` / `Q` | 可設定 |
| 離合器（MT） | `Left Ctrl` | 長按模擬踩下 |
| 開啟設定選單 | `F6`（或整合進 sofapotato_menu） | |

---

## 八、HUD 顯示（client/modules/hud.lua）

在螢幕左下或駕駛儀表附近顯示：
- 當前檔位（R / N / 1~8）
- 轉速條（模擬 RPM）
- 離合器深度指示（MT 專用）
- 離合器耐久警示（耐久 < 30% 顯示警告）
- 當前變速箱型號標籤

---

## 九、實作階段

### 階段 1：核心框架建立
**目標**：資源可正常啟動，可偵測車輛並載入對應變速箱設定
**成功標準**：`fxmanifest.lua` 無錯誤，`bootstrap.lua` 輸出正確框架偵測結果
**狀態**：未開始

### 階段 2：AT 自排系統
**目標**：自排邏輯完整，轉速隨速度正確模擬
**成功標準**：駕駛 AT 車輛會自動升降檔，轉速條有反應
**狀態**：未開始

### 階段 3：離合器輸入與 MT 換檔
**目標**：MT 完整實作，含熄火、頓挫、離合器深度
**成功標準**：未踩離合換檔 → 失敗/熄火；正確操作 → 順暢換檔並有轉速回落
**狀態**：未開始

### 階段 4：AT/MT 手自排系統
**目標**：按鍵換檔不需離合，有換檔延遲
**成功標準**：撥片換檔反應正確，延遲符合 `shiftDelay` 設定
**狀態**：未開始

### 階段 5：齒比系統與物理微調
**目標**：齒比實際影響加速/極速，換檔感更真實
**成功標準**：不同齒比設定下車輛表現有明顯差異
**狀態**：未開始

### 階段 6：離合器磨損系統
**目標**：離合器耐久度會損耗，影響換檔效果
**成功標準**：耐久降低後換檔成功率下降，維修後恢復
**狀態**：未開始

### 階段 7：HUD 與持久化
**目標**：儀表顯示正確，玩家設定存入資料庫
**成功標準**：換伺服器後設定不會消失
**狀態**：未開始

---

## 十、待確認問題

- [ ] 離合器維修方式：NPC 修車廠（ox_target）？還是使用物品？
- [ ] 玩家是否可以在遊戲中自行更換變速箱型號（例如改裝選單）？
- [ ] 齒比是否對所有玩家同步（網路同步），還是只有本地模擬？
- [ ] 是否整合進 `sofapotato_menu`（F5）選單？
- [ ] 音效需求：換檔聲、回火聲、熄火聲？

---

## 十一、Claude 建議補強項目

> 見下方第十二節

---

## 十二、建議新增功能（Claude 評估）

以下是建議補強或新增的功能，依優先度排序：

### 🔴 高優先度（強烈建議加入）

#### 1. 防熄火輔助開關（Anti-Stall Assist）
讓不熟練的玩家可開啟輔助，低轉速時自動補一點油門防止熄火。
```lua
Config.AntiStallAssist = false  -- 預設關閉，讓玩家自行決定
```

#### 2. 空檔（Neutral）支援
MT 操作最重要的一環，車子靜止時可掛空檔保護引擎：
- 按住離合器 + 降到 1 檔以下 = 空檔
- 空檔下引擎不會熄火
- 空檔下不能行駛（失去驅動力）

#### 3. 引擎煞車（Engine Braking）
鬆油門時，依當前齒比降低車速（不只是引擎轉速）：
- 低檔＋高速 → 強烈引擎煞車
- 高檔＋低速 → 輕微引擎煞車
- MT 特別明顯，AT/ATMT 也有但較輕

#### 4. 車輛類別預設（Class-based Defaults）
讓每種車輛類型有合適的預設變速箱，而不是全靠 model 手動設定：
```lua
Config.ClassDefaults = {
    [0]  = 'AT_4',    -- Compacts → 4速自排
    [1]  = 'AT_5',    -- Sedans
    [6]  = 'ATMT_8',  -- Super
    [8]  = 'MT_6',    -- Motorcycles
    [14] = 'MT_4',    -- Muscle（老車手排）
    -- ...
}
```

---

### 🟡 中優先度（有空加入）

#### 5. 轉速匹配輔助（Rev Match / Heel-Toe）
MT 降檔時，自動補一下油門讓轉速匹配，減少頓挫感。現實中這是高階駕駛技巧：
```lua
Config.RevMatchAssist = false   -- 玩家手動開關
-- 降檔時：新齒比對應轉速比舊齒比高，自動補油讓轉速先升上去再接合
```

#### 6. 渦輪遲滯（Turbo Lag）整合
換檔瞬間渦輪壓力降低，之後重新建壓：
- 換檔後有 0.3~0.8 秒的動力缺口
- 與 `GetVehicleHandlingFloat('fTurboI')` 整合

#### 7. 溫度系統（Transmission Temperature）
- 長時間半離合、激烈換檔 → 變速箱溫度升高
- 高溫 → 換檔延遲增加、換檔成功率下降
- 停車靜置 → 降溫
- 可整合修車廠換油服務

#### 8. 維修介面（sofapotato_menu 整合）
在 F5 選單中加入「車輛調校」子選單：
- 查看目前離合器耐久度
- 更換變速箱型號（需物品或費用）
- 調整齒比（高端調校選項）

---

### 🟢 低優先度（未來可考慮）

#### 9. 漂移模式（Drift Mode）
對 MT 車輛：
- 特殊離合器操作：踩下 + 快速釋放（clutch kick）
- 後輪瞬間失去驅動力然後猛然接合 → 觸發打滑
- 與 `SetVehicleHandlingFloat('fTractionCurveLateral', ...)` 整合

#### 10. 起步控制（Launch Control）
- AT/ATMT 高階功能
- 油門保持在設定轉速，鬆煞車後瞬間爆發加速
- 防止輪胎打滑的優化起步

#### 11. 網路同步（換檔音效廣播）
對附近玩家廣播：
- 升降檔引擎聲變化
- 熄火後重新啟動聲
- 換檔不當的頓挫音效

#### 12. 車行改裝系統整合
配合 `sofapotato_garages` 或獨立改裝 NPC：
- 更換更好的變速箱（例如 4速自排 → 6速手自排）
- 需要花費金錢與時間
- 改裝記錄存在 DB

---

## 十三、技術限制說明

| 限制 | 說明 | 解決方案 |
|------|------|---------|
| GTA 實際齒比同步 | `SetVehicleHandlingFloat` 只影響本地端 | 只在本地計算，不同步齒比；或用 trigger 讓每個玩家各自 apply |
| 轉速模擬精度 | FiveM 的 RPM 是 0.0~1.0 正規化值，非真實 rpm | 用速度＋齒比反推，近似值已足夠 |
| GTA 引擎易熄火防護 | GTA 預設有防熄火保護 | 需要用 `SetVehicleClutch` + 持續偵測狀態來覆蓋 |
| 多人同步 | 其他玩家看到的換檔只有視覺，無法感受到你的物理 | 這是 FiveM 客戶端物理分離的正常限制 |

---

*計劃書最後更新：2026-03-08*
