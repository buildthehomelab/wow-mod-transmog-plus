-- Shaman totem looks: a look per totem element, shown in place of the race's stock totem. They
-- share the druid forms' tables: mod_transmog_plus_forms rows with Form 'fire', 'earth', 'water'
-- or 'air' (in mod_transmog_plus_form_choice: 7 fire, 8 earth, 9 water, 10 air). The rows
-- themselves come from a look pack, a module of its own that also ships the client patch with the
-- retail totem models (buildthehomelab/wow-mod-retail-shaman-totems). Without one, shamans get no
-- Totems tab.
DELETE FROM `module_string` WHERE `module` = 'mod-transmog-plus' AND `id` = 25;
INSERT INTO `module_string` (`module`, `id`, `string`) VALUES
('mod-transmog-plus', 25, 'new totem looks unlocked. Pick them in the Totems tab of the Transmogrify window (/transmog).');
