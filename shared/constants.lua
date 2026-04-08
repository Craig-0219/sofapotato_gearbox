GearboxConst = {
    Events = {
        -- Server → Client
        SYNC_SETTINGS   = 'sofapotato_gearbox:client:SyncSettings',
        REPAIR_RESULT   = 'sofapotato_gearbox:client:RepairResult',
        UNLOCK_RESULT   = 'sofapotato_gearbox:client:UnlockResult',
        -- Client → Server
        LOAD_SETTINGS   = 'sofapotato_gearbox:server:LoadSettings',
        SAVE_SETTINGS   = 'sofapotato_gearbox:server:SaveSettings',
        REPAIR_CLUTCH   = 'sofapotato_gearbox:server:RepairClutch',
        BUY_UPGRADE     = 'sofapotato_gearbox:server:BuyUpgrade',
        -- Net（Client ↔ Client，附近玩家同步）
        NET_SYNC_RPM    = 'sofapotato_gearbox:net:SyncRpm',
        NET_SYNC_STALL  = 'sofapotato_gearbox:net:SyncStall',
    },

    Type = {
        AT   = 'AT',
        ATMT = 'ATMT',
        MT   = 'MT',
    },

    ClutchState = {
        ENGAGED    = 'engaged',    -- 0.0  放開
        SLIPPING   = 'slipping',   -- 0~1  半離合
        DISENGAGED = 'disengaged', -- 1.0  完全踩下
    },

    ShiftDir = {
        UP   =  1,
        DOWN = -1,
    },

    -- 轉速門檻（GTA RPM 0.0 ~ 1.0）
    Rpm = {
        STALL      = 0.05,
        IDLE       = 0.12,
        SHIFT_UP   = 0.85,
        SHIFT_DOWN = 0.42,
        REDLINE    = 0.95,
    },

    -- 離合器耐久度門檻
    ClutchHealth = {
        GOOD   = 70.0,
        WORN   = 40.0,
        BAD    = 15.0,
        BROKEN =  0.0,
    },

    -- 溫度門檻（°C）
    Temp = {
        NORMAL   =  80.0,
        HOT      = 100.0,
        OVERHEAT = 120.0,
    },
}
