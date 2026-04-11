# Phase 0 Review — FiveM Drivetrain 架構現況盤點

日期：2026-04-08  
範圍：`client/` drivetrain 相關核心與功能模組

---

## 1) 專案結構快照（Client）

### 1.1 新核心（已存在，部分接管）
- `client/core/vehicle_state.lua`
- `client/core/gearbox_core.lua`
- `client/core/gear_ratios.lua`
- `client/core/rpm_engine.lua`
- `client/core/clutch_engine.lua`
- `client/core/native_adapter.lua`
- `client/core/compat.lua`

### 1.2 模式層（已拆分）
- `client/modes/at_logic.lua`
- `client/modes/atmt_logic.lua`
- `client/modes/mt_logic.lua`

### 1.3 舊 modules（仍大量被 main 呼叫）
- `client/modules/state.lua`
- `client/modules/gearbox.lua`
- `client/modules/physics.lua`
- `client/modules/clutch.lua`
- `client/modules/launch.lua`
- `client/modules/drift.lua`
- `client/modules/sounds.lua`
- `client/modules/menu.lua`
- `client/modules/hud.lua`
- `client/modules/upgrade.lua`
- `client/modules/damage.lua`
- `client/modules/input.lua`

---

## 2) 目前 drivetrain authority 現況

## 2.1 已有正向進展
1. **`main.lua` 主循環已優先走 GB 核心鏈**：`GB.State.ReadInputs → GB.Clutch.Tick → GB.RPM.Tick → GB.Core.Tick → modes`。  
2. **`GearboxState` 與 `GB.State` 已 alias**，可讓舊模組仍可跑。  
3. **`gear_ratios.lua` 已具備 snapshot / per-gear cache / dirty 更新概念**。  
4. **`native_adapter.lua` 已建立「集中輸出」雛形**。

## 2.2 主要風險（核心問題仍存在）
1. **Native authority 尚未真正收斂**：`core` 與 `modules` 同時在寫 `SetVehicle* / SetVehicleHandling*`。  
2. **雙核心並存**：`client/modules/gearbox.lua`、`client/modules/physics.lua` 仍保留完整 drivetrain 決策能力。  
3. **compat 越權**：`client/core/compat.lua` 目前仍直接寫 handling/native（不只 bridge）。  
4. **功能模組越權**：`launch.lua`、`drift.lua`、`sounds.lua` 仍可直接改 RPM/gear/traction。  
5. **gear / rpm 真相來源混雜**：AT、ATMT、MT 在舊路徑與新路徑的寫入時機還可能互相覆蓋。

---

## 3) 直接碰 native/handling 的位置盤點

> 目標 native：
> `SetVehicleCurrentGear / SetVehicleNextGear / SetVehicleHighGear / SetVehicleCurrentRpm / SetVehicleHandlingFloat / SetVehicleHandlingInt / SetVehicleMaxSpeed / SetVehicleEngineTorqueMultiplier`

## 3.1 核心層（理應保留）
- `client/core/native_adapter.lua`：集中封裝上述大多數寫入。  
- `client/core/gear_ratios.lua`：仍直接執行 handling 套用與還原（可接受，但需逐步改為透過 adapter）。  
- `client/core/gearbox_core.lua`：透過 `GB.Native.*` 同步 gear/rpm/clutch。

## 3.2 仍在越權寫入的舊層（需遷移/封鎖）
- `client/modules/physics.lua`：每幀 `SetVehicleHandlingFloat`、`SetVehicleMaxSpeed`、`SetVehicleCurrentRpm`。  
- `client/modules/gearbox.lua`：多處 `SetVehicleCurrentGear/SetVehicleNextGear`。  
- `client/modules/state.lua`：大量 handling / gear / torque / maxSpeed 寫入與還原。  
- `client/modules/menu.lua`：直接 `SetVehicleCurrentGear` 與 `SetVehicleMaxSpeed`。  
- `client/modules/launch.lua`：直接 `SetVehicleCurrentRpm`、`SetVehicleCurrentGear`。  
- `client/modules/drift.lua`：直接 `SetVehicleHandlingFloat`（traction）。  
- `client/modules/sounds.lua`：對遠端車直接 `SetVehicleCurrentRpm/SetVehicleCurrentGear`。  
- `client/modules/stall.lua`：直接 `SetVehicleCurrentRpm(0.0)`。  
- `client/core/compat.lua`：bridge 層內仍有 `SetVehicleHandlingFloat/Int`、`SetVehicleHighGear` 等寫入。

---

## 4) 直接影響 drivetrain 的模組清單（功能責任）

## 4.1 核心模組（Core Drivetrain）
- `client/core/vehicle_state.lua`（狀態真相）
- `client/core/gearbox_core.lua`（換檔狀態機）
- `client/core/rpm_engine.lua`（rpm 計算）
- `client/core/clutch_engine.lua`（離合器軸與切斷）
- `client/core/gear_ratios.lua`（snapshot/cache/齒比）
- `client/core/native_adapter.lua`（native 輸出）
- `client/modes/*.lua`（AT / ATMT / MT 模式決策）

## 4.2 功能模組（Feature）
- `client/modules/launch.lua`（launch control）
- `client/modules/drift.lua`（drift assist）
- `client/modules/sounds.lua`（音效同步）
- `client/modules/hud.lua`（顯示）
- `client/modules/menu.lua`（UI + 參數調整）
- `client/modules/upgrade.lua`（升級）
- `client/modules/damage.lua`（溫度 / 耐久）
- `client/features/*.lua`（新 feature 子系統，目前與 modules 並行）

---

## 5) 模組處置建議（保留 / 搬遷 / 淘汰）

## 5.1 應保留（主幹）
1. `client/main.lua`（主循環骨幹可保留）
2. `client/core/vehicle_state.lua`
3. `client/core/gearbox_core.lua`
4. `client/core/rpm_engine.lua`
5. `client/core/clutch_engine.lua`
6. `client/core/gear_ratios.lua`
7. `client/core/native_adapter.lua`
8. `client/modes/at_logic.lua`
9. `client/modes/atmt_logic.lua`
10. `client/modes/mt_logic.lua`

## 5.2 應搬遷（移入新分層接口）
1. `client/modules/launch.lua` → `client/features/launch_control.lua`（只產生 request，不直接寫 native）
2. `client/modules/drift.lua` → `client/features/drift.lua`（改成 traction modifier request）
3. `client/modules/sounds.lua` → `client/features/sounds.lua`（只做廣播/播放，不寫遠端 drivetrain native）
4. `client/modules/menu.lua` → `client/features/menu.lua`（只改 config/state，不碰 handling 計算）
5. `client/modules/hud.lua` → `client/features/hud.lua`（只讀 state）
6. `client/modules/upgrade.lua` → `client/features/upgrade.lua`（資料流維持）

## 5.3 應淘汰或下線（舊 drivetrain 主控）
1. `client/modules/physics.lua`：淘汰「每幀 handling/maxSpeed/RPM 重設」路徑。  
2. `client/modules/gearbox.lua`：淘汰「第二套換檔核心」。  
3. `client/modules/state.lua`：淘汰「第二套 state + handling override 套用器」。

> 備註：以上 3 個檔可先保留檔案，但停止被主循環引用，待 Phase 3 再實際刪除舊邏輯。

---

## 6) Phase 1~4 建議落地順序（最小可用重構）

## Phase 1（分層就位）
1. 新增/整理核心邊界：`state/snapshot/cache`、`drivetrain core`、`native adapter`。  
2. 把 **所有 drivetrain native 寫入入口** 收斂到 `native_adapter.lua`。  
3. 在 `main.lua` 明確禁用舊 `physics/gearbox/state` drivetrain 路徑。

## Phase 2（authority 收斂）
1. 定義 truth source：`currentGear/desiredGear/rpm/clutchAxis` 由腳本主控；`nativeGear` 只參考。  
2. AT / ATMT / MT 拆開規則：AT 全腳本主導、ATMT 手排指令+防互打、MT 定義 neutral/clutch/stall/rev-match。  
3. 引入 feature request 機制（launch/drift/sounds 不直寫 native）。

## Phase 3（清理舊殘留）
1. menu 不再算 handlingOverrides 與 `fInitialDriveMaxFlatVel`。  
2. physics 不再每幀重設 handling/maxSpeed。  
3. launch/drift/sounds 改走 core API。  
4. 停用舊 modules 的 drivetrain 寫入代碼區段。

## Phase 4（compat 保留但可退場）
1. `client/core/compat.lua` 標記 temporary alias。  
2. 對每個 alias 補 `TODO(remove in phase-X)`。  
3. 新核心不得反向依賴 compat。  
4. 完成 HUD/menu/sounds/upgrade 遷移後逐步刪除 compat API。

---

## 7) 本次 Phase 0 結論

目前專案已具備「新核心雛形」，但尚未達成「單一 drivetrain authority」。
阻礙點不是齒比演算法本身，而是 **舊 modules 與 compat 仍可繞過 core/native_adapter 直接寫 native**。  

下一步（Phase 1）應以「封裝與封口」為第一優先：
- **所有 drivetrain native 統一出口**（native_adapter）
- **所有 feature 改 request/modifier**（不再直寫）
- **停用舊雙路徑主控**（physics/gearbox/state 的 drivetrain 主邏輯）

