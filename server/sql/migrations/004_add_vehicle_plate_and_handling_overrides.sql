ALTER TABLE `sp_gearbox_player_settings`
    ADD COLUMN `vehicle_plate` VARCHAR(16) NOT NULL DEFAULT '*' AFTER `vehicle_model`,
    ADD COLUMN `handling_overrides` JSON NULL AFTER `gear_ratios`;

ALTER TABLE `sp_gearbox_player_settings`
    DROP INDEX `uq_player_vehicle`,
    ADD UNIQUE KEY `uq_player_vehicle_scope` (`citizenid`, `vehicle_plate`, `vehicle_model`);
