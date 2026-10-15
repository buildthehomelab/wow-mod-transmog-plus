-- Looks that also wait for a spell: a character has the look once it knows the spell (and has
-- cleared the look's UnlockPhase). A mount module lists its mount's spell here, so buying the
-- mount brings its druid form look along. Rows come from such modules (mod-retail-pets), and the
-- table starts empty. Their SQL makes this table too (same definition), so either can apply first.
CREATE TABLE IF NOT EXISTS `mod_transmog_plus_form_spells` (
    `DisplayId` int(10) unsigned NOT NULL COMMENT 'mod_transmog_plus_forms look',
    `SpellId` int(10) unsigned NOT NULL COMMENT 'a character who knows this spell has the look (on top of its UnlockPhase)',
    PRIMARY KEY (`DisplayId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DELETE FROM `module_string` WHERE `module` = 'mod-transmog-plus' AND `id` = 27;
INSERT INTO `module_string` (`module`, `id`, `string`) VALUES
('mod-transmog-plus', 27, 'look unlocked. Pick it in the Transmogrify window (/transmog).');
