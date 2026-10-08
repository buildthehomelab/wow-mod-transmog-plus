-- Removes backpacks. Run by hand (the server never applies data/sql/uninstall), on acore_world
-- and acore_characters as marked. Also take the backpack rows out of the realm's client patch.

-- acore_world
DROP TABLE IF EXISTS `mod_transmog_plus_backpacks`;
DELETE FROM `spell_dbc` WHERE `ID` BETWEEN 90170 AND 90189;
DELETE FROM `spell_custom_attr` WHERE `spell_id` BETWEEN 90170 AND 90177;
-- item 27621 back to the stock "NPC Equip 27621" placeholder
DELETE FROM `item_template` WHERE `entry` = 27621;
INSERT INTO `item_template` VALUES
(27621,15,0,-1,'NPC Equip 27621',9632,0,0,0,1,0,0,0,-1,-1,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1000,0,0,0,0,0,0,-1,0,-1,0,0,0,0,-1,0,-1,0,0,0,0,-1,0,-1,0,0,0,0,-1,0,-1,0,0,0,0,-1,0,-1,0,'',0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,-1,0,0,0,0,'',0,0,0,0,0,1);

-- acore_characters
-- DROP TABLE IF EXISTS `mod_transmog_plus_backpack_unlocks`;
-- DROP TABLE IF EXISTS `mod_transmog_plus_backpack_choice`;
-- DROP TABLE IF EXISTS `mod_transmog_plus_backpack_mail`;
-- DELETE FROM `item_instance` WHERE `itemEntry` = 27621;
