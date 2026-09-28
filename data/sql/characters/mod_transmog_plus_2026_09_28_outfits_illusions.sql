-- Account-wide outfits, saved from the addon (data is "slot,item;slot,item" with 1-based slots).
CREATE TABLE IF NOT EXISTS `mod_transmog_plus_outfits` (
    `account_id` int(10) unsigned NOT NULL,
    `name` varchar(48) NOT NULL,
    `data` varchar(255) NOT NULL DEFAULT '',
    PRIMARY KEY (`account_id`, `name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- Illusions (weapon enchant visuals, SpellItemEnchantment IDs) collected per account.
CREATE TABLE IF NOT EXISTS `mod_transmog_plus_illusions` (
    `account_id` int(10) unsigned NOT NULL,
    `enchant_id` int(10) unsigned NOT NULL,
    PRIMARY KEY (`account_id`, `enchant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- The illusion shown on a character's main hand (15) and off hand (16); 999999 hides the glow.
CREATE TABLE IF NOT EXISTS `mod_transmog_plus_illusion_slots` (
    `Owner` int(10) unsigned NOT NULL,
    `Slot` tinyint(3) unsigned NOT NULL,
    `EnchantId` int(10) unsigned NOT NULL,
    PRIMARY KEY (`Owner`, `Slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
