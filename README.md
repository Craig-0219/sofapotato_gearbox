# sofapotato_gearbox

擬真變速箱系統，支援 AT（自排）、AT/MT（手自排）、MT（手排）三種模式。

## 需求

| 依賴 | 用途 |
|------|------|
| `sp_bridge` | 框架橋接（金錢、玩家資料、通知） |
| `oxmysql` | 資料庫持久化 |
| `ox_lib` | Context 選單、對話框 |
| `ox_target` | 技師升級互動點 |

## 安裝

1. 將資源放入伺服器 resources 目錄
2. 確認 `sp_bridge`、`oxmysql`、`ox_lib`、`ox_target` 已啟動
3. 新安裝執行 `server/sql/migrations/001_init.sql` 與 `002_add_unlocked_transmissions.sql`
4. 舊版升級到 `sp_` 前綴表名時，額外執行 `server/sql/migrations/003_rename_tables_to_sp_prefix.sql`
5. 在 `server.cfg` 加入 `ensure sofapotato_gearbox`

## 功能

### 變速箱類型

| 類型 | 說明 |
|------|------|
| AT | 全自動，含 Kickdown 急加速降檔，支援起步控制 |
| AT/MT | 手自排，可手動操作但無離合器需求，支援起步控制 |
| MT | 全手排，需使用離合器換檔，未踩離合器有熄火風險，支援起步控制 |

每種類型細分多種型號（4～8 速），可在 `shared/config.lua` 的 `Config.Transmissions` 自訂齒比。

### 進階功能

- **離合器磨損**：換檔或不當操作會磨損離合器，耐久歸零後無法換檔
- **溫度系統**：頻繁換檔使溫度上升，過熱加重換檔延遲；行駛中自然冷卻
- **渦輪遲滯**：特定型號（如 ATMT_8）啟用渦輪，低轉時動力不足需等待增壓
- **補油降檔（Rev Match）**：降檔時自動補油使轉速吻合，減少頓挫
- **漂移模式（Clutch Kick）**：MT 模式快速踩離合可觸發側滑
- **起步控制（Launch Control）**：AT/ATMT — 油門 + 煞車蓄力，放煞車後全力發車；MT — 離合器踩下 + 油門 + 煞車就位，放煞車觸發，玩家自行決定放離合器時機
- **換檔音效廣播**：換檔 RPM 同步給附近玩家，引擎聲與視覺一致
- **技師商店升級**：至指定地點購買解鎖更高階變速箱型號

### 按鍵（預設）

| 按鍵 | 功能 |
|------|------|
| `Left Ctrl` | 離合器（按住） |
| `E` | 升檔 |
| `Q` | 降檔 |
| `N` | 空檔切換 |
| `F6` | 開啟變速箱選單 |
| `L` | 取消起步控制 |

> 所有按鍵可在遊戲設定中重新綁定（`RegisterKeyMapping`）

## 設定

主要設定位於 `shared/config.lua`：

```lua
Config.HudEnabled = false         -- 開關 HUD（預設關閉）
Config.Debug = false              -- 除錯輸出
Config.MTStartInNeutral = true    -- MT 進車時預設空檔

Config.Clutch.repairCost = 5000   -- 離合器維修費用
Config.Temperature.enabled = true -- 溫度系統
Config.Drift.enabled = true       -- 漂移模式
Config.Launch.enabled = true      -- 起步控制

-- 車輛專屬變速箱（以 model 名稱為鍵）
Config.VehicleTransmissions = {
    ['adder'] = 'AT_6',
    ['t20']   = 'ATMT_8',
}
```

## 資料庫

| 表格 | 說明 |
|------|------|
| `sp_gearbox_player_settings` | 每位玩家各車型的變速箱與離合器耐久存檔 |
| `sp_gearbox_unlocked_transmissions` | 玩家已購買解鎖的變速箱型號 |

---

詳細版本紀錄請見 [CHANGELOG.md](CHANGELOG.md)
