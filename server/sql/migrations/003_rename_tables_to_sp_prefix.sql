SET @old_table := 'gearbox_player_settings';
SET @new_table := 'sp_gearbox_player_settings';
SET @sql := (
    SELECT IF(
        EXISTS(
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = DATABASE()
              AND table_name = @old_table
        ) AND NOT EXISTS(
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = DATABASE()
              AND table_name = @new_table
        ),
        CONCAT('RENAME TABLE `', @old_table, '` TO `', @new_table, '`'),
        'SELECT 1'
    )
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @old_table := 'gearbox_unlocked_transmissions';
SET @new_table := 'sp_gearbox_unlocked_transmissions';
SET @sql := (
    SELECT IF(
        EXISTS(
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = DATABASE()
              AND table_name = @old_table
        ) AND NOT EXISTS(
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = DATABASE()
              AND table_name = @new_table
        ),
        CONCAT('RENAME TABLE `', @old_table, '` TO `', @new_table, '`'),
        'SELECT 1'
    )
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
