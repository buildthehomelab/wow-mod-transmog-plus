-- Removes the shaman totem looks. Run by hand (the server never applies data/sql/uninstall), on
-- acore_world and acore_characters as marked. Players can keep patch-V: unused displays do nothing.

-- acore_world
DELETE FROM `mod_transmog_plus_forms` WHERE `Form` IN ('fire', 'earth', 'water', 'air');
DELETE FROM `creature_template_model` WHERE `CreatureID` BETWEEN 9501500 AND 9501999;
DELETE FROM `creature_template` WHERE `entry` BETWEEN 9501500 AND 9501999;
DELETE FROM `creature_model_info` WHERE `DisplayID` BETWEEN 96000 AND 96999;
DELETE FROM `creaturedisplayinfo_dbc` WHERE `ID` BETWEEN 96000 AND 96999;
DELETE FROM `creaturemodeldata_dbc` WHERE `ID` BETWEEN 96000 AND 96999;
DELETE FROM `module_string` WHERE `module` = 'mod-transmog-plus' AND `id` = 25;

-- acore_characters
-- DELETE FROM `mod_transmog_plus_form_choice` WHERE `Form` BETWEEN 7 AND 10;
