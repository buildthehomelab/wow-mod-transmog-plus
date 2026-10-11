-- Removes mod-transmog-plus's side of the druid form, shaman totem and warlock demon looks. Run by
-- hand (the server never applies data/sql/uninstall), on acore_world and acore_characters as marked.
-- The looks themselves belong to the look packs: run their uninstall SQL too
-- (mod-retail-druid-forms, mod-retail-shaman-totems, mod-retail-warlock-pets), or the rows stay
-- behind unused.

-- acore_world
DROP TABLE IF EXISTS `mod_transmog_plus_forms`;
DELETE FROM `module_string` WHERE `module` = 'mod-transmog-plus' AND `id` IN (24, 25, 26);

-- acore_characters
-- DROP TABLE IF EXISTS `mod_transmog_plus_form_choice`;
