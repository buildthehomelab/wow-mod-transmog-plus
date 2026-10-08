# mod-transmog-plus

Slot-based transmogrification module for [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk).
Appearances are stored per slot (not per item), so your look stays when you swap gear.

This is the buildthehomelab fork. It is based on
[Saor79's fork](https://github.com/Saor79/mod-transmog-plus) including its
`feature/transmog-sets` branch (the Transmog Sets browser), which in turn forks
[Stefan2102/mod-transmog-plus](https://github.com/Stefan2102/mod-transmog-plus). On top of that
it collects appearances the retail way (see below) and ships a migration from mod-transmog.

## Features

- Slot-based transmog -- appearances stay on the equipment slot when you swap gear.
- Account-wide collection -- any appearance unlocked by one character is available account-wide.
- Appearances unlock the retail way: when you equip an item, when it lands in your bags (loot,
  vendors, quest rewards, crafting, trades, mail, the auction house, the guild bank) or when you
  disenchant it, including winning it on a Disenchant roll in a group. Turning in a quest collects every reward it offers, not only the one you
  picked. A scan on login collects everything already equipped, in your bags and in your bank,
  and the rewards of every quest already turned in. Each trigger can be switched off in the
  config.
- One tile per look: items that share a model are grouped, and the tile's tooltip lists every
  item with that look, collected or not. A look counts as collected from any of its items.
- Search box under the Items grid filters by item name (any item with the look). Tick
  **Missing** to list the looks the selected item could use that your account hasn't collected
  yet. The server builds that list and runs the search on it. Click a missing look to try it
  on; Shift-click any look to link the item in chat.
- Illusions: weapon enchant glows unlock for the account when you enchant a weapon (or own an
  enchanted one) and can be shown on the main hand or off hand from the Illusions tab, or
  hidden altogether (`Transmog.Illusions.Enable`).
- Backpacks: Blizzard's newer backpack cloaks, worn on the character's back from the Backpacks
  tab. Each character gets a letter with the Halfhill Farmer's Backpack (a chicken on a wicker
  pack) and unlocks one more backpack per individual progression phase cleared (Molten Core
  through Naxxramas). A worn backpack hides the cloak, and comes off in shapeshift forms. It
  needs the realm's client patch, which carries the models and spells 90170-90178 (built with
  [wow-mod-visible-bags](https://github.com/buildthehomelab/wow-mod-visible-bags)); the list
  is the world table `mod_transmog_plus_backpacks` (`Transmog.Backpacks.*`).
- Druid forms: druids pick a look for each shapeshift form from the Forms tab, like retail's
  barber shop. There are 265 retail form looks: the remade bear and cat colours of every druid
  race, the Legion artifact forms, Dreamsabers, Bristlebruins, stags, owls, Batbears and more.
  The classic looks are there from the start; each individual progression phase cleared unlocks
  the next batch, through the Ruby Sanctum. A look goes on whenever the form's normal model
  would, so transforms (costumes, Polymorph) still win. It needs the realm's client patch
  (patch-I, built with
  [wow-mod-retail-druid-forms](https://github.com/buildthehomelab/wow-mod-retail-druid-forms));
  the list is the world table `mod_transmog_plus_forms`, previewed through creatures
  9501000-9501499 (`Transmog.Forms.Enable`).
- Outfits are saved on the server for the whole account. Each character's old outfits are
  uploaded the first time it opens the window.
- Transmog Sets browser in the addon.
- `/transmog`, or a key bound under Key Bindings > Transmog, opens the transmog window
  anywhere, no NPC needed (switch off with `Transmog.OpenAnywhere = 0`). `/transmog anchor`
  moves the new-appearance alert.
- Preview tiles frame the part of the body the slot covers; weapon tiles zoom on the hand
  holding the weapon. If a race frames badly, `/transmog camera <depth> <side> <height>
  [rotation]` nudges the selected slot's tiles for the session (`/transmog camera reset` undoes
  it); positive depth zooms in, positive height shows lower on the body.
- Option to hide individual armor slots (helm, shoulders, chest, shirt, tabard, etc.).
- Right-click a slot in the window to strip its transmog, or click the disenchant icon next to
  the reset arrow to strip every slot and illusion at once; Apply confirms it (free).
- Set bonus tooltips count your real equipped pieces. The client counts the visible
  (transmogged) items, so without the addon a transmogged set piece showed as missing and its
  bonuses grey, although the server applied them all along.
- The character pane shows your real items' icons and quality, also on hidden slots. The client
  otherwise draws the transmog appearance's icon, and an empty slot for a hidden one.


## Optional Addon (WIP)

This module includes a WoW 3.3.5a client addon in the `addon/` directory. It provides a
visual transmog interface with 3D item preview. If the addon is not installed, the standard
gossip menu is used as a fallback.

![Addon UI](docs/addon_preview.png)

## Requirements

- An [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) WotLK (master) server. It
  also builds on the mod-playerbots core fork; no playerbot module is needed.
- A WoW 3.3.5a (12340) client.
- The `Transmog` addon (in `addon/`) for the transmog window, collection tooltips, outfits and
  sets. Without it only the NPC's gossip menu works.
- Don't run it together with [azerothcore/mod-transmog](https://github.com/azerothcore/mod-transmog);
  see "Migrating from mod-transmog".

## Installation

1. Clone the module into the `modules/` folder of your AzerothCore source directory. Keep the
   folder name `mod-transmog-plus`, because AzerothCore derives the loader function name from it:

   ```bash
   git clone https://github.com/buildthehomelab/wow-mod-transmog-plus.git mod-transmog-plus
   ```
2. Re-run CMake and build.
3. Copy `conf/mod_transmog_plus.conf.dist` to `mod_transmog_plus.conf` and adjust as needed.
4. Import the SQL files manually, or let AzerothCore auto-import them on next server start.
5. Spawn the Transmog NPC in-game: `.npc add 190012`

Addon installation (optional): copy the `addon/Transmog/` folder to your client's
`Interface/AddOns/` directory.

## Migrating from mod-transmog

mod-transmog-plus replaces [azerothcore/mod-transmog](https://github.com/azerothcore/mod-transmog).
Don't run both. To move over:

1. Remove mod-transmog (and mod-transmog-collect, whose features are built in here) from
   `modules/`, add this module and rebuild.
2. Start the worldserver once so the mod-transmog-plus tables get created, then stop it.
3. Run [`sql/migrate_from_mod_transmog.sql`](sql/migrate_from_mod_transmog.sql) against the
   characters database. It copies every account's collection and the transmogs on equipped
   items. Transmogs on items in bags or the bank and mod-transmog's saved sets don't carry over;
   the file explains why. It leaves the old tables in place and is safe to run twice.
4. Start the worldserver. mod-transmog's NPC (entry 190010) no longer does anything; spawn this
   module's NPC (190012) wherever the old one stood.

## Configuration

All prices, quality restrictions, type rules, and requirement ignores are configurable in
`mod_transmog_plus.conf`. See the distributed config file for details.

## Known Limitations

- **Hidden appearance**: When a slot is hidden, its character-sheet icon turns invisible
  instead of showing a special icon. This happens because a fake item entry number is used
  to represent the hidden state, which is necessary for proper equipment refresh.
- **Set bonus counter**: Transmogging an item that belongs to an equipment set causes the
  client to show an incorrect set count (e.g. 5/6 instead of 6/6). The set bonus still
  functions correctly -- this is a display-only issue in the character sheet.

## Troubleshooting

- **The module builds but the NPC and commands do nothing**: the folder isn't named
  `mod-transmog-plus`, so AzerothCore never calls the loader.
- **No transmog window, only a gossip menu**: the `Transmog` addon isn't installed in the
  client's `Interface/AddOns/`. `/transmog` also needs the addon and `Transmog.OpenAnywhere = 1`.
- **The NPC isn't there**: spawn it with `.npc add 190012`. The old mod-transmog NPC (190010)
  no longer does anything.
- **Two transmog modules**: remove mod-transmog before adding this one and migrate its data,
  see "Migrating from mod-transmog".
- **A hidden slot's icon turns invisible on the character sheet, or a set shows 5/6 instead of
  6/6**: both are known display-only limitations, see "Known Limitations".

## Credits

Author of this fork: [buildthehomelab](https://github.com/buildthehomelab)

Based on:
- [flekz-games](https://github.com/flekz-games) for [cmangos-transmog](https://github.com/flekz-games/cmangos-transmog)
- [malinmr](https://github.com/malinmr) for porting the addon to AzerothCore
- [Stefan2102](https://github.com/Stefan2102) for mod-transmog-plus
- [Saor79](https://github.com/Saor79) for the Transmog Sets browser

## License

GNU Affero General Public License v3, see [LICENSE](LICENSE).
