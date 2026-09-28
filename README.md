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
  disenchant it. Turning in a quest collects every reward it offers, not only the one you
  picked. A scan on login collects everything already equipped, in your bags and in your bank,
  and the rewards of every quest already turned in. Each trigger can be switched off in the
  config.
- One tile per look: items that share a model are grouped, and the tile's tooltip lists every
  item with that look, collected or not. A look counts as collected from any of its items.
- Illusions: weapon enchant glows unlock for the account when you enchant a weapon (or own an
  enchanted one) and can be shown on the main hand or off hand from the Illusions tab, or
  hidden altogether (`Transmog.Illusions.Enable`).
- Outfits are saved on the server for the whole account. Each character's old outfits are
  uploaded the first time it opens the window.
- Transmog Sets browser in the addon.
- `/transmog`, or a key bound under Key Bindings > Transmog, opens the transmog window
  anywhere, no NPC needed (switch off with `Transmog.OpenAnywhere = 0`). `/transmog anchor`
  moves the new-appearance alert.
- Option to hide individual armor slots (helm, shoulders, chest, etc.).


## Optional Addon (WIP)

This module includes a WoW 3.3.5a client addon in the `addon/` directory. It provides a
visual transmog interface with 3D item preview. If the addon is not installed, the standard
gossip menu is used as a fallback.

![Addon UI](docs/addon_preview.png)

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

## Credits

- [flekz-games](https://github.com/flekz-games) for [cmangos-transmog](https://github.com/flekz-games/cmangos-transmog)
- [malinmr](https://github.com/malinmr) for porting the addon to AzerothCore
- [Stefan2102](https://github.com/Stefan2102) for mod-transmog-plus
- [Saor79](https://github.com/Saor79) for the Transmog Sets browser

## License

GNU Affero General Public License v3 -- see `LICENSE`.
