-- Warlock demon looks: a look per demon, shown in place of the demon's own model. They share the
-- druid forms' tables: mod_transmog_plus_forms rows with Form 'imp', 'voidwalker', 'succubus',
-- 'felhunter', 'felguard', 'infernal' or 'doomguard' (in mod_transmog_plus_form_choice: 11 imp,
-- 12 voidwalker, 13 succubus, 14 felhunter, 15 felguard, 16 infernal, 17 doomguard). The rows
-- themselves come from a look pack, a module of its own
-- (buildthehomelab/wow-mod-retail-warlock-pets). Without one, warlocks get no Demons tab.
DELETE FROM `module_string` WHERE `module` = 'mod-transmog-plus' AND `id` = 26;
INSERT INTO `module_string` (`module`, `id`, `string`) VALUES
('mod-transmog-plus', 26, 'new demon looks unlocked. Pick them in the Demons tab of the Transmogrify window (/transmog).');
