-- The druid form look a character picked, per form (0 bear, 1 cat, 2 travel, 3 aquatic,
-- 4 flight, 5 moonkin, 6 tree); no row means the default look.
CREATE TABLE IF NOT EXISTS `mod_transmog_plus_form_choice` (
    `Owner` int(10) unsigned NOT NULL,
    `Form` tinyint(3) unsigned NOT NULL,
    `DisplayId` int(10) unsigned NOT NULL,
    PRIMARY KEY (`Owner`, `Form`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
