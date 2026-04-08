CREATE TABLE IF NOT EXISTS `sp_gearbox_player_settings` (
    `id`            INT           AUTO_INCREMENT PRIMARY KEY,
    `citizenid`     VARCHAR(50)   NOT NULL,
    `vehicle_model` VARCHAR(50)   NOT NULL DEFAULT 'default',
    `vehicle_plate` VARCHAR(16)   NOT NULL DEFAULT '*',
    `transmission`  VARCHAR(20)   NOT NULL DEFAULT 'STOCK',
    `clutch_health` FLOAT         NOT NULL DEFAULT 100.0,
    `gear_ratios`   JSON          NULL,
    `handling_overrides` JSON     NULL,
    `updated_at`    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                  ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_player_vehicle_scope` (`citizenid`, `vehicle_plate`, `vehicle_model`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
