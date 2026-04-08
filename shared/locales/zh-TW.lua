Locales = Locales or {}
Locales['zh-TW'] = {
    -- 通知
    StallNotify       = '⚠ 引擎熄火！',
    ShiftFailed       = '換檔失敗',
    ClutchWarn        = '⚠ 離合器損壞',
    ClutchBroken      = '❌ 離合器故障，無法換檔',
    RepairSuccess     = '離合器已維修完成',
    RepairFailed      = '資金不足，無法維修離合器',
    InputNeedTransmission = '目前車輛未安裝可操作的變速箱',
    InputClutchMtOnly = '離合器只會在 MT 手排生效',
    InputShiftManualOnly = '目前是自排，無法手動換檔',
    InputNeutralMtOnly = '空檔切換只會在 MT 手排生效',

    -- 選單（變速箱設定）
    MenuTitle         = '變速箱設定',
    MenuCurrentTransm = '目前：%s',
    MenuClutchHealth  = '離合器耐久：%.0f%%',
    MenuTemp          = '變速箱溫度：%.0f°C',
    MenuAntiStall     = '防熄火輔助',
    MenuRevMatch      = '轉速匹配輔助',
    MenuDriftMode     = '漂移模式（Clutch Kick）',
    MenuRepairClutch  = '維修離合器（$%d）',
    MenuChangeTransm  = '更換 / 購買變速箱',
    MenuStockClutch   = '原廠離合器',
    MenuStockDesc     = '不套用改裝變速箱，使用原廠 handling',
    MenuStockInfo     = '目前未安裝改裝離合器，使用原廠 handling',
    MenuEnabled       = '✔ 開啟',
    MenuDisabled      = '✘ 關閉',
    MenuLaunchArmed   = '起步控制：就位',
    MenuLaunchInfo    = '全油門 + 全煞車 + 靜止 → 鬆煞車發車',
    MenuNeedVehicle   = '請先坐上駕駛座再開啟變速箱選單',
    MenuNeedDriverSeat = '只有駕駛可以開啟變速箱選單',
    MenuNotReady      = '變速箱資料尚未載入，請稍後再試',
    MenuUiUnavailable = '變速箱選單 UI 尚未初始化，請確認 ox_lib 已正確載入',

    -- 溫度
    TempHot           = '⚠ 變速箱過熱！',

    -- 升級系統
    UpgradeLabel        = '變速箱升級',
    UpgradeMenuTitle    = '變速箱升級商店',
    UpgradeTitle        = '選擇型號購買',
    UpgradeOwned        = ' ✔ 已擁有',
    UpgradeBuy          = '點擊購買',
    UpgradeConfirmTitle = '確認購買',
    UpgradeConfirmMsg   = '購買 %s 需要 $%d，確定嗎？',
    UpgradeSuccess      = '已解鎖：%s',
    UpgradeEquipHint    = '變速箱已解鎖，進入車輛後重新開啟選單以裝備',
    UpgradeNoFunds      = '資金不足',
    UpgradeFailed       = '購買失敗',
}
