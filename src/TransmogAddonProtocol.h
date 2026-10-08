#ifndef DEF_TRANSMOG_ADDON_PROTOCOL_H
#define DEF_TRANSMOG_ADDON_PROTOCOL_H

#include "Player.h"
#include <string>

namespace TransmogAddon
{
    constexpr char const* PREFIX = "transmog";

    void SendOpen(Player* player);

    // Notify tooltip clients that an appearance became collected.
    void SendCollectionUpdated(Player* player, uint32 itemId);

    // Notify the addon that an illusion (weapon enchant visual) became collected.
    void SendIllusionCollected(Player* player, uint32 enchantId);

    // Backpacks: a newly unlocked one, and the character's current choice.
    void SendBackpackUnlocked(Player* player, uint32 backpackId);
    void SendBackpackStatus(Player* player);
    // Druid form looks: a phase that opened new looks, and the character's choice per form.
    void SendFormsUnlocked(Player* player, uint8 phase);
    void SendFormStatus(Player* player);

    void Dispatch(Player* player, std::string const& message);
}

#endif
