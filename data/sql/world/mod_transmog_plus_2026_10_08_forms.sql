-- Druid form looks: a look shown in place of the stock form model. The table starts empty: the
-- looks come from a look pack, a module of its own that fills it and ships the client patch with
-- the models (buildthehomelab/wow-mod-retail-druid-forms). Without one, druids get no Forms tab.
-- A pack's SQL makes this table too (same definition), so either can apply first.
CREATE TABLE IF NOT EXISTS `mod_transmog_plus_forms` (
    `DisplayId` int(10) unsigned NOT NULL COMMENT 'CreatureDisplayInfo id from the client patch',
    `Form` varchar(16) NOT NULL COMMENT 'bear, cat, travel, aquatic, flight, moonkin or tree',
    `Name` varchar(80) NOT NULL,
    `UnlockPhase` tinyint(3) unsigned NOT NULL DEFAULT 0 COMMENT 'individual progression phase cleared (quest 66000+n); 0 = from the start',
    `PreviewCreature` int(10) unsigned NOT NULL DEFAULT 0 COMMENT 'creature_template entry with this display, for the addon preview',
    `SortOrder` int(10) unsigned NOT NULL DEFAULT 0,
    PRIMARY KEY (`DisplayId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DELETE FROM `module_string` WHERE `module` = 'mod-transmog-plus' AND `id` = 24;
INSERT INTO `module_string` (`module`, `id`, `string`) VALUES
('mod-transmog-plus', 24, 'new druid form looks unlocked. Pick them in the Forms tab of the Transmogrify window (/transmog).');
