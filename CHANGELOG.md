# Changelog

所有版本變更紀錄。格式參照 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)。

---

## [0.4.1] — 2026-03-20

### 修正

**RPM 突然飆升 / 飆降（換檔後轉速驟變）**
- 根本原因：`physics.lua` 換檔期間 lerp rate = `revDropRate × 8.0`（約 2.0），比平時 4.0 更慢，換檔動畫期間 RPM 幾乎不動，換檔結束後才驟然跳至目標值，造成儀表板 RPM 驟變
- 修正方式：換檔 lerp 乘數從 `× 8.0` 改為 `× 32.0`（約 8.0），確保換檔窗口內 RPM 快速平滑落轉，不留殘差給換檔後驟跳

**MT/ATMT 偶發無法行駛（driveForceCutActive 卡住）**
- 根本原因：`UpdateManualClutchDriveForce` 恢復驅動力時，若 `savedDriveForce` 為 nil 且 `GetAppliedDriveForceValue()` 也回傳 nil，函式提前 return 卻未重設 `driveForceCutActive = false`，導致驅動力永遠被設為 0.0001，車輛完全無法行駛
- 修正方式：恢復分支一律先重設旗標與快取，再決定是否還原 handling float

**換檔後時速卡住、需反覆切檔才能繼續加速（GTA 未收到齒位更新）**
- 根本原因：`ExecuteShift` 對 ATMT/MT 未呼叫 `SetVehicleCurrentGear(toGear)`，GTA AT 不知道要切換到新齒位；GTA 仍以舊齒位計算驅動力，舊齒頂速一到驅動力衰減至 0，時速卡死直到 GTA AT 自行判斷升檔（可能延遲數秒）
- 誤判原因：原本以為換檔時通知一次也會引發 0.3.0 自動降檔迴圈；實際上 0.3.0 的問題是每幀持續強制，每次換檔觸發一次不會形成迴圈
- 修正方式：還原對所有類型呼叫 `SetVehicleCurrentGear(toGear)` 一次，確保 GTA 進入新齒位、驅動力正確銜接

**RPM 非線性抖動（speed 含 Z 軸噪音 + targetRpm 無緩衝）**
- 根本原因 1：`GetEntitySpeed` 含 Z 軸分量，車輛過顛簸或跳躍時速度 spike 直接影響 speedRpm 計算
- 根本原因 2：`state.targetRpm` 每幀直接賦值，輸入任何瞬間波動立即反映；即使 `state.rpm` 有 lerp，targetRpm 本身的跳變仍造成 RPM 不線性
- 修正方式 1：改用前向速度（`GetEntityVelocity` dot `GetEntityForwardVector`，水平面投影），排除 Z 軸分量
- 修正方式 2：對 `state.targetRpm` 加一層 lerp 平滑（rate 10.0，約 100ms 響應），形成雙段低通濾波；換檔期間仍用快速 rate 保持即時落轉

**⚠️ 已回退：highGear=1 修正（造成車速被鎖死）**
- 嘗試將 ATMT/MT 的 `highGear` 固定為 1 以阻止 GTA 自動換檔干擾
- 根本問題：GTA 一檔驅動力在 `speed > firstGearTopSpeed`（約 20 km/h）後衰減至 0，即使 `SetVehicleMaxSpeed` 允許更高速度，引擎也無力推動車輛，導致所有 ATMT/MT 模式被鎖死於極低速
- 已回退為 `highGear = scriptGear`

---

## [0.4.0] — 2026-03-19

### 新增

**MT 起步控制（Launch Control）**
- 起步控制（Launch Control）擴展支援 MT 手排模式
- 就位條件：離合器踩下 + 全油門（>90%）+ 全煞車 + 幾乎靜止（< 1.5 m/s）
- 就位後鬆煞車觸發起步爆發，玩家自行決定放離合器時機（放離合器即全力輸出）
- 離合器在就位期間放開會中止 Launch Control（防止意外觸發）

### 修正

**起步控制油門偵測失效**
- 根本原因：`GetVehicleThrottleOffset` 在靜止狀態下可能回傳 0（GTA 無法施力時不更新），導致 `throttle > 0.90` 判斷永遠失敗、無法進入就位狀態
- 修正方式：加入 `GetControlNormal(0, 71)` 原始按鍵輸入作為備援，取兩者最大值

---

## [0.3.0] — 2026-03-19

### 修正

**MT 手排三檔以上無法加速（核心 Bug）**
- 根本原因：`ApplyManualTransmissionLock` 每幀強制呼叫 `SetVehicleCurrentGear(scriptGear)` 時，GTA AT 在低速判定該檔位「轉速過低」而自動降檔；腳本下一幀又升回，形成每幀「升→降→升」迴圈，GTA 在每次降檔事件中切斷油門，導致車輛完全無法施加驅動力
- 修正方式：移除 `ApplyManualTransmissionLock` 中每幀強制的 `SetVehicleCurrentGear` / `SetVehicleNextGear` 呼叫
- 改由 `EnforceTransmissionGearLimit` 將 `SetVehicleHighGear` 設為腳本當前檔位（而非固定 `cfg.maxGear`），作為 GTA AT 的上限天花板；GTA AT 在 1..scriptGear 範圍內自然選擇物理檔位，`SetVehicleMaxSpeed` 負責各檔頂速硬性限制

**MT 靜止高檔油門輸入遺失**
- 根本原因：靜止時 `GetVehicleThrottleOffset` 在 GTA 無法施力的狀態下回傳 0，導致腳本判定為零油門 → 轉速鎖在怠速 → GTA 仍無法施力的循環依賴
- 修正方式：新增 `GetControlNormal(0, 71)` 原始按鍵輸入作為備援，取兩者最大值，打破循環依賴

**Debug 日誌強化**
- physics.lua 除錯輸出新增 `base=`（baseTopSpeedKmh）、`gr=`（gearRatio）、`tr=`（topRatio）三個欄位，便於診斷各檔頂速計算異常

---

## [0.2.0] — 2026-03-10

### 新增

**齒比調整 UI**
- 設定選單新增「齒比調整」面板，以 2 欄網格顯示所有可用檔位的輸入框
- 修改值時即時以橘色 `is-modified` 樣式標示已變更欄位
- 「全部重設」一鍵還原至變速箱預設齒比
- 「套用並儲存」將變更寫入 Handling Float 並立即同步至伺服器 SQL

**極速控制**
- 每種變速箱新增 `maxSpeedRatio` 設定欄位，直接指定相對於原車極速的比例上限（`0.25 ~ 2.0`）
- `SetVehicleMaxSpeed` 硬性上限，確保 AT 全自動模式下 GTA 原生物理仍受控制
- 調整齒比後即時重新計算極速上限（`originalTopRatio / newTopRatio` 比例縮放）
- 極速計算下限從 0.55 降至 0.25，支援齒比較短的型號

### 修正

- **購買變速箱後無回應**：`UNLOCK_RESULT`、`SYNC_SETTINGS`、`REPAIR_RESULT` 三個 Server→Client 事件補上 `RegisterNetEvent`，修正 FiveM 靜默丟棄未登記事件的問題
- **套用齒比後極速未更新**：`applyGearRatios` 回調補上極速重算，確保低頂檔齒比能正確提升尾速上限

---

## [0.1.0] — 2026-03-09

### 新增

**核心系統**
- AT / ATMT / MT 三種變速箱模式
- 10 種內建型號：AT_4 / AT_5 / AT_6、ATMT_6 / ATMT_7 / ATMT_8、MT_4 / MT_5 / MT_6 / MT_7
- 以車輛 model 名稱自訂預設變速箱（`Config.VehicleTransmissions`）
- 可調整齒比，自動套用至 GTA Handling（`SetVehicleHandlingFloat`）
- AT 全自動換檔，含 Kickdown 急加速強制降檔邏輯

**MT 手排物理**
- 離合器深度輸入（Hold 按鍵，平滑插值）
- 離合器未踩換檔 → 頓挫 + 熄火風險
- 空檔切換（N 鍵）

**損耗 & 環境**
- 離合器磨損系統（一般換檔 / 粗暴換檔分級磨損，耐久歸零後無法換檔）
- 溫度系統：換檔 / 粗暴操作升溫，行駛中冷卻，過熱增加換檔延遲
- 渦輪遲滯：per-transmission `turbo` 旗標，低增壓時動力輸出受限（`ATMT_8` 預設啟用）

**進階駕駛**
- 補油降檔（Rev Match Assist）：降檔前自動預調轉速，減少頓挫
- 漂移模式（Clutch Kick）：MT 快速踩放離合觸發側滑力 + 短暫降低牽引力
- 起步控制（Launch Control）：AT/ATMT 油門 + 煞車蓄力，放煞車後全力加速（2 秒發射窗口）

**多人同步**
- 換檔 RPM 廣播：換檔後同步附近玩家引擎轉速，音效與視覺一致
- 熄火廣播：熄火狀態同步附近玩家

**UI / HUD**
- HUD：檔位文字（含換檔中橘黃 / 紅線紅色）、轉速條（水平）、離合器深度條（MT 專用）
- 閃爍警告：離合器耐久過低、溫度過高
- 起步控制指示器：就位綠色閃爍 `LC ●`、發射中橘色快閃 `🚀 LC`

**持久化 & 升級**
- 伺服器存檔：離合器耐久、變速箱型號、齒比（`gearbox_player_settings`）
- 技師商店維修離合器（扣款 bank）
- 技師商店升級系統：tier 分級，tier 1 免費，tier 2+ 購買解鎖（`gearbox_unlocked_transmissions`）
- ox_target 技師互動點（可在 config 設定多個地點）

**整合**
- F5 選單整合（sofapotato_menu `gearbox_menu` 按鈕）
- 雙語 locale（`zh-TW` / `en`）
- 資源啟動依賴檢查（bootstrap，缺少依賴自動停止）
