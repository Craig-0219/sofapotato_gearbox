# Code Review Report

資源：`sofapotato_gearbox`  
日期：`2026-03-09`  
範圍：client / server / shared / SQL migration

## 結論

本次 review 以「功能正確性、可被濫用風險、多人同步、持久化一致性」為主。

目前有 4 個高優先問題：

1. client 可直接偽造存檔資料，繞過變速箱升級購買流程。
2. 升級商店可在車外改檔並覆蓋上一台車的設定。
3. 核心換檔 RPM 公式方向相反，會導致升降檔轉速表現失真。
4. 文件宣稱的 RPM / 熄火多人同步尚未完成完整事件鏈。

另有 3 個中優先問題：

1. `SYNC_SETTINGS` 非同步回來時沒有核對車輛上下文，快速換車時可能套錯資料。
2. 升級購買流程存在重複扣款競態條件。
3. `Config.PersistPerVehicle` 與實際行為不一致，屬於未完成設定項。

---

## Findings

### 1. High
### `SAVE_SETTINGS` 完全信任 client，玩家可繞過升級購買直接寫入高階變速箱

**位置**

- `server/modules/persistence.lua:51`
- `server/modules/persistence.lua:58`
- `client/modules/menu.lua:149`

**問題說明**

`SAVE_SETTINGS` 事件直接接受 client 傳入的 `transmKey`，server 沒有驗證：

- 該型號是否存在於 `Config.Transmissions`
- 玩家是否已解鎖該型號
- 該型號是否符合 tier / 購買狀態

只要玩家手動觸發 event，就能把任意變速箱直接寫進 `gearbox_player_settings`，等同繞過 `BUY_UPGRADE` 的付費與解鎖流程。

**影響**

- 經濟系統失效
- 升級系統形同虛設
- 任意 client event 注入即可永久解鎖效果

**建議**

- server 端在 `SAVE_SETTINGS` 內重驗 `transmKey`
- 若 tier > 1，必須查 `gearbox_unlocked_transmissions`
- 不合法時拒絕寫入，必要時回傳錯誤通知

---

### 2. High
### 升級商店可在車外改檔，可能覆蓋上一台車的存檔

**位置**

- `client/modules/upgrade.lua:31`
- `client/modules/upgrade.lua:75`
- `client/modules/menu.lua:135`
- `client/modules/state.lua:123`

**問題說明**

升級商店的 `OpenUpgradeMenu()` / `ChangeTransmission()` 沒有要求玩家必須正在駕駛車輛。  
同時 `GearboxStateReset()` 離車時沒有清掉：

- `vehicleNetId`
- `modelName`
- `transmKey`

因此玩家下車後仍可能沿用上一台車的狀態資料，在技師區直接改檔並送出 `SAVE_SETTINGS`，把上一台車的設定覆寫掉。

**影響**

- 車外也能修改車輛設定
- 容易寫到錯誤 `vehicle_model`
- 行為與使用者預期不一致

**建議**

- `OpenUpgradeMenu()` 與 `ChangeTransmission()` 先驗證 `inVehicle`、`DoesEntityExist(vehicle)`、駕駛座身份
- `GearboxStateReset()` 完整清空 vehicle context
- 若升級商店設計上允許車外購買，應分離「購買解鎖」與「套用到當前車」兩條流程

---

### 3. High
### 換檔 RPM 公式方向相反，核心物理表現失真

**位置**

- `client/modules/gearbox.lua:112`
- `client/modules/physics.lua:141`

**問題說明**

`ExecuteShift()` 使用：

```lua
state.rpm * (oldRatio / newRatio)
```

但在固定車速下，換檔後轉速應與新檔齒比成正比，正確方向應為：

```lua
state.rpm * (newRatio / oldRatio)
```

目前程式會出現：

- 升檔時 RPM 被拉高
- 降檔時 RPM 反而被壓低

而 `DoRevMatch()` 又使用 `newRatio / oldRatio`，形成同資源內部邏輯互相矛盾。

**影響**

- 手排 / 手自排換檔體感錯誤
- 補油降檔邏輯與實際換檔結果不一致
- HUD、音效、動力表現都會失真

**建議**

- 將 `ExecuteShift()` 的轉速換算公式改為 `newRatio / oldRatio`
- 連同 `rev match`、換檔後 `targetRpm`、同步 RPM 一起驗證

---

### 4. High
### 多人 RPM / 熄火同步事件鏈未完成

**位置**

- `client/modules/sounds.lua:7`
- `client/modules/sounds.lua:19`
- `server/main.lua:1`

**問題說明**

目前 client 端會呼叫：

- `TriggerNetEvent(GearboxConst.Events.NET_SYNC_RPM, ...)`
- `TriggerNetEvent(GearboxConst.Events.NET_SYNC_STALL, ...)`

但 server 沒有對應 relay handler，且 client 接收端只寫了 `AddEventHandler(...)`，未見完整 `RegisterNetEvent(...)` 配套。

因此文件中宣稱的：

- 換檔 RPM 廣播
- 熄火廣播

目前並沒有完成可驗證的 client -> server -> nearby clients 事件鏈。

**影響**

- 功能名義存在、實際未完成
- README / CHANGELOG 與實際行為不一致
- 附近玩家無法穩定聽到/看到同步結果

**建議**

- 在 server 建立 relay event，依距離或 scope 廣播給附近玩家
- client 接收端明確使用 `RegisterNetEvent`
- 補一輪多人實測確認是否真的跨客戶端生效

---

### 5. Medium
### `SYNC_SETTINGS` 沒有核對請求對應車輛，快速換車可能套錯資料

**位置**

- `client/main.lua:26`
- `client/modules/damage.lua:56`

**問題說明**

進車後 client 非同步向 server 請求資料，但回來時只要收到 `SYNC_SETTINGS` 就直接套用，沒有驗證：

- 是否仍在同一台車
- `modelName` 是否仍一致
- 是否為最新一次請求

若玩家在短時間內連續換車，車 A 的查詢回應可能在車 B 上被套用。

**影響**

- 套錯 transmission
- 離合器耐久錯亂
- 已解鎖清單狀態覆寫

**建議**

- 在請求與回應中加入 request token 或 vehicle/model snapshot
- client 套用前核對當前 `vehicleNetId` / `modelName`

---

### 6. Medium
### 升級購買流程有競態條件，可能重複扣款

**位置**

- `server/modules/upgrade.lua:17`
- `server/modules/upgrade.lua:41`
- `server/modules/upgrade.lua:49`

**問題說明**

目前流程是：

1. `SELECT COUNT(*)`
2. 扣款
3. `INSERT IGNORE`

若玩家短時間內重複觸發購買，可能兩個請求都在插入前通過檢查，最終：

- 只成功插入一筆解鎖
- 但 bank 被扣兩次

**影響**

- 玩家金流異常
- 客訴風險高

**建議**

- 改為 transaction 或先 `INSERT` 成功後再扣款
- 至少要對同一 `src + transmKey` 做 server-side in-flight 鎖

---

### 7. Medium
### `Config.PersistPerVehicle` 與實際持久化邏輯不一致

**位置**

- `shared/config.lua:9`
- `server/modules/persistence.lua:13`
- `server/sql/migrations/001_init.sql:10`

**問題說明**

設定註解寫的是：

- `true = 每台車記住設定`
- `false = 跟玩家走`

但目前實作始終使用：

- `citizenid + vehicle_model`

這代表：

- 不是每台「實體車」記錄，而是每個「車種 model」共用
- `false` 也沒有任何實作分支

**影響**

- 設定名稱與實際行為不符
- 容易讓後續維護者誤判功能已完成

**建議**

- 若只打算做 per-model，請更名並修正文案
- 若真的要支援 per-vehicle / per-player，需補唯一車輛識別與分支邏輯

---

## 建議修正順序

1. 先修 `SAVE_SETTINGS` server 驗證，堵住繞過購買漏洞。
2. 再修升級商店車外操作與 `GearboxStateReset()` 殘留狀態。
3. 修正換檔 RPM 公式，重新驗證 AT / ATMT / MT 的換檔體感。
4. 補齊多人同步事件鏈，避免文件與功能不一致。
5. 最後處理 `SYNC_SETTINGS` token 化、購買競態與 `PersistPerVehicle` 設計落差。

## 測試缺口

目前尚未看到以下驗證：

- 單人 AT / ATMT / MT 換檔行為實測
- 快速換車下的非同步載入一致性測試
- 多 client 的 RPM / 熄火同步測試
- 升級購買重入 / spam 測試
- 車外開啟升級商店與狀態殘留測試

## 備註

本報告為靜態 code review，未在 FiveM runtime 上執行整合測試。
