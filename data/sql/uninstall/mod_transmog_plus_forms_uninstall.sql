-- Removes the druid form looks. Run by hand (the server never applies data/sql/uninstall), on
-- acore_world and acore_characters as marked. Players can keep patch-R: unused displays do nothing.

-- acore_world
-- The table also holds the shaman totem looks (mod_transmog_plus_totems_uninstall.sql): drop it
-- only when both are gone.
DELETE FROM `mod_transmog_plus_forms` WHERE `Form` IN ('bear', 'cat', 'travel', 'aquatic', 'flight', 'moonkin', 'tree');
-- DROP TABLE IF EXISTS `mod_transmog_plus_forms`;
DELETE FROM `creature_template_model` WHERE `CreatureID` BETWEEN 9501000 AND 9501499;
DELETE FROM `creature_template` WHERE `entry` BETWEEN 9501000 AND 9501499;
DELETE FROM `creature_model_info` WHERE `DisplayID` BETWEEN 95000 AND 95999;
DELETE FROM `creaturedisplayinfo_dbc` WHERE `ID` BETWEEN 95000 AND 95999;
DELETE FROM `creaturemodeldata_dbc` WHERE `ID` BETWEEN 9500 AND 9599;
DELETE FROM `module_string` WHERE `module` = 'mod-transmog-plus' AND `id` = 24;

-- acore_characters
-- DELETE FROM `mod_transmog_plus_form_choice` WHERE `Form` BETWEEN 0 AND 6;
-- DROP TABLE IF EXISTS `mod_transmog_plus_form_choice`;
