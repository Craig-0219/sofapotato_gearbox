CREATE TABLE IF NOT EXISTS `sp_gearbox_unlocked_transmissions` (
    `id`           INT          AUTO_INCREMENT PRIMARY KEY,
    `citizenid`    VARCHAR(50)  NOT NULL,
    `transmission` VARCHAR(20)  NOT NULL,
    `unlocked_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_citizen_transm` (`citizenid`, `transmission`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
