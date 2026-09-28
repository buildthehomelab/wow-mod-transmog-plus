-- One-time migration from azerothcore/mod-transmog to mod-transmog-plus.
--
-- Run it by hand against the characters database, after mod-transmog-plus has created its
-- tables (start the worldserver once with the module, or import
-- data/sql/characters/mod_transmog_plus_characters.sql yourself). It lives outside data/sql on
-- purpose so AzerothCore never imports it automatically.
--
-- Safe to run more than once: it only adds rows and never overwrites a slot that already has a
-- mod-transmog-plus appearance. The mod-transmog tables are left alone, so you can roll back.
--
-- What carries over:
--   1. Collected appearances (custom_unlocked_appearances), account for account.
--   2. Transmogs on equipped items. mod-transmog stores a transmog per item, mod-transmog-plus per
--      equipment slot, so each equipped item's transmog becomes the transmog of the slot it's in.
--      Hidden appearances (mod-transmog's FakeEntry 1) become mod-transmog-plus's hidden entry
--      999999, on armor slots only, because mod-transmog-plus can't hide weapons.
--   3. The appearances those transmogs use get added to the account's collection, so the
--      transmogrifier lists them even if mod-transmog's collection system was off.
--
-- What doesn't:
--   - Transmogs on items in bags or the bank. There's no slot to put them on.
--   - Saved sets (custom_transmogrification_sets). mod-transmog-plus keeps outfits in the addon's
--     per-character saved variables on the player's PC, which the server can't write.
--
-- Run mod-transmog-plus instead of mod-transmog, never both: they fight over the same visible
-- item fields.

-- 1. Collections.
INSERT IGNORE INTO `mod_transmog_plus_appearances` (`account_id`, `item_template_id`)
SELECT `account_id`, `item_template_id`
FROM `custom_unlocked_appearances`;

-- 2. Transmogs on equipped items. Bag 0, slots 0-18 are the equipment slots, numbered the same
--    way as mod-transmog-plus's Slot column. Armor slots: head 0, shoulders 2, shirt 3, chest 4,
--    waist 5, legs 6, feet 7, wrists 8, hands 9, back 14, tabard 18.
INSERT IGNORE INTO `mod_transmog_plus` (`Owner`, `Slot`, `FakeEntry`)
SELECT ct.`Owner`, ci.`slot`, IF(ct.`FakeEntry` = 1, 999999, ct.`FakeEntry`)
FROM `custom_transmogrification` ct
JOIN `character_inventory` ci ON ci.`item` = ct.`GUID` AND ci.`guid` = ct.`Owner`
WHERE ci.`bag` = 0
  AND ci.`slot` < 19
  AND (ct.`FakeEntry` <> 1 OR ci.`slot` IN (0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 18));

-- 3. Make sure every appearance in use is also collected.
INSERT IGNORE INTO `mod_transmog_plus_appearances` (`account_id`, `item_template_id`)
SELECT DISTINCT c.`account`, ct.`FakeEntry`
FROM `custom_transmogrification` ct
JOIN `characters` c ON c.`guid` = ct.`Owner`
WHERE ct.`FakeEntry` > 1;
