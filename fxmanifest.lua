fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'sofapotato_gearbox'
author      'SofaPotato'
description '擬真變速箱系統 (AT / AT-MT / MT)'
version     '0.1.0'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/styles.css',
    'ui/app.js',
}

shared_scripts {
    'shared/locales/*.lua',
    'shared/constants.lua',
    'shared/config.lua',
}

client_scripts {
    -- ── Phase 1 新核心（載入順序有依賴關係，勿隨意調換）
    'client/core/vehicle_state.lua',   -- GB.State + GearboxState alias
    'client/core/gear_ratios.lua',     -- 齒比系統（預算、套用、snapshot）
    'client/core/native_adapter.lua',  -- GTA native 唯一入口（分類管理）
    'client/core/gearbox_core.lua',    -- ExecuteShift、SetNeutral、ChangeTransmission
    'client/core/rpm_engine.lua',      -- RPM 模擬（ATMT/MT 用）
    'client/core/clutch_engine.lua',   -- 離合器引擎（二元，可擴展類比）
    'client/core/compat.lua',          -- 舊 API 橋接（GetLocale、IsVehicleReversingState 等）

    -- ── 新換檔模式邏輯
    'client/modes/at_logic.lua',
    'client/modes/atmt_logic.lua',
    'client/modes/mt_logic.lua',

    -- ── 新功能模組
    'client/features/stall.lua',
    'client/features/engine_braking.lua',

    -- ── 保留的舊模組（讀 GearboxState = GB.State，無需修改）
    -- 移除：modules/state.lua、modules/clutch.lua、modules/physics.lua
    --        modules/stall.lua、modules/gearbox.lua（已由新核心取代）
    'client/modules/input.lua',
    'client/modules/damage.lua',
    'client/modules/hud.lua',
    'client/modules/menu.lua',
    'client/modules/drift.lua',
    'client/modules/launch.lua',
    'client/modules/sounds.lua',
    'client/modules/upgrade.lua',

    -- ── 主循環（最後載入）
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bootstrap.lua',
    'server/modules/persistence.lua',
    'server/modules/upgrade.lua',
    'server/main.lua',
}

dependencies {
    'sp_bridge',
    'oxmysql',
}
