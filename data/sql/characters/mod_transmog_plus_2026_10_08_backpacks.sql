-- Backpacks unlocked per character (individual progression phases and the intro letter's item).
CREATE TABLE IF NOT EXISTS `mod_transmog_plus_backpack_unlocks` (
    `Owner` int(10) unsigned NOT NULL,
    `BackpackId` int(10) unsigned NOT NULL,
    PRIMARY KEY (`Owner`, `BackpackId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- The backpack a character wears; no row means none.
CREATE TABLE IF NOT EXISTS `mod_transmog_plus_backpack_choice` (
    `Owner` int(10) unsigned NOT NULL,
    `BackpackId` int(10) unsigned NOT NULL,
    PRIMARY KEY (`Owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Characters that were sent the backpack introduction letter (once each).
CREATE TABLE IF NOT EXISTS `mod_transmog_plus_backpack_mail` (
    `Owner` int(10) unsigned NOT NULL,
    PRIMARY KEY (`Owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
