#include "Transmog.h"
#include "Bag.h"
#include "Chat.h"
#include "Group.h"
#include "Spell.h"
#include "SpellInfo.h"
#include <type_traits>
#include <utility>

// Retail-style collecting: an appearance unlocks when the item reaches your bags or gets
// disenchanted, and a login scan catches everything already in your bags and bank.
// Equipping is handled by TransmogPlayerScript, behind the same bot check.
namespace
{
    // The playerbots fork adds WorldSession::IsBot(); stock AzerothCore doesn't have it. Looking for
    // it at compile time lets the module build on both.
    template <typename Session, typename = void>
    struct HasIsBot : std::false_type { };

    template <typename Session>
    struct HasIsBot<Session, std::void_t<decltype(std::declval<Session&>().IsBot())>> : std::true_type { };

    template <typename Session>
    bool IsBotSession(Session* session)
    {
        if constexpr (HasIsBot<Session>::value)
            return session->IsBot();
        else
            return false;
    }
}

// Random bots have accounts of their own and would fill mod_transmog_plus_appearances with
// everything they loot or wear. Alt bots (your own characters played as bots) share your account,
// so they collect for you, but only while a real player of that account is grouped with them.
bool TransmogCollect_CanCollect(Player* player)
{
    WorldSession* session = player ? player->GetSession() : nullptr;
    if (!sTransmog->Enable || !session)
        return false;

    if (!IsBotSession(session))
        return true;

    if (!sTransmog->CollectAltBots)
        return false;

    Group* group = player->GetGroup();
    if (!group)
        return false;

    for (GroupReference* itr = group->GetFirstMember(); itr; itr = itr->next())
    {
        Player* member = itr->GetSource();
        if (member && member != player && member->GetSession() && !IsBotSession(member->GetSession())
            && member->GetSession()->GetAccountId() == session->GetAccountId())
            return true;
    }

    return false;
}

namespace
{
    uint32 CollectItem(Player* player, Item* item, CharacterDatabaseTransaction trans)
    {
        return item && sTransmog->CollectAppearance(player, item->GetTemplate(), false, trans) ? 1 : 0;
    }

    uint32 CollectBag(Player* player, uint8 bagPos, CharacterDatabaseTransaction trans)
    {
        uint32 added = 0;
        if (Bag* bag = player->GetBagByPos(bagPos))
            for (uint32 slot = 0; slot < bag->GetBagSize(); ++slot)
                added += CollectItem(player, bag->GetItemByPos(slot), trans);
        return added;
    }

    uint32 CollectEverything(Player* player, CharacterDatabaseTransaction trans)
    {
        uint32 added = 0;

        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
            added += CollectItem(player, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot), trans);

        for (uint8 slot = INVENTORY_SLOT_ITEM_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
            added += CollectItem(player, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot), trans);
        for (uint8 bagPos = INVENTORY_SLOT_BAG_START; bagPos < INVENTORY_SLOT_BAG_END; ++bagPos)
            added += CollectBag(player, bagPos, trans);

        for (uint8 slot = BANK_SLOT_ITEM_START; slot < BANK_SLOT_ITEM_END; ++slot)
            added += CollectItem(player, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot), trans);
        for (uint8 bagPos = BANK_SLOT_BAG_START; bagPos < BANK_SLOT_BAG_END; ++bagPos)
            added += CollectBag(player, bagPos, trans);

        return added;
    }
}

class TransmogCollectScript : public PlayerScript
{
public:
    TransmogCollectScript() : PlayerScript("TransmogCollectScript", {
        PLAYERHOOK_ON_STORE_NEW_ITEM,
        PLAYERHOOK_ON_AFTER_MOVE_ITEM_TO_INVENTORY,
        PLAYERHOOK_ON_SPELL_CAST,
        PLAYERHOOK_ON_LOGIN
    }) { }

// Every newly created item: loot, vendor, quest reward, crafting. Starting gear is stored before
// the character is in the world; the login scan picks that up instead.
    void OnPlayerStoreNewItem(Player* player, Item* item, uint32 /*count*/) override
    {
        if (sTransmog->CollectOnPickup && item && player->IsInWorld() && TransmogCollect_CanCollect(player))
            sTransmog->CollectAppearance(player, item->GetTemplate(), true);
    }

// Existing items changing hands: trade, mail (including the auction house), guild bank.
    void OnPlayerAfterMoveItemToInventory(Player* player, Item* item, bool /*update*/) override
    {
        if (sTransmog->CollectOnPickup && item && player->IsInWorld() && TransmogCollect_CanCollect(player))
            sTransmog->CollectAppearance(player, item->GetTemplate(), true);
    }

// Runs as the cast goes off, while the item is still there to read.
    void OnPlayerSpellCast(Player* player, Spell* spell, bool /*skipCheck*/) override
    {
        if (!sTransmog->CollectOnDisenchant || !spell || !spell->GetSpellInfo()->HasEffect(SPELL_EFFECT_DISENCHANT))
            return;

        if (Item* item = spell->m_targets.GetItemTarget(); item && TransmogCollect_CanCollect(player))
            sTransmog->CollectAppearance(player, item->GetTemplate(), true);
    }

// Unlock everything already equipped, in the bags or in the bank, and report it in one line.
    void OnPlayerLogin(Player* player) override
    {
        if (!sTransmog->CollectScanOnLogin || !TransmogCollect_CanCollect(player))
            return;

        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        uint32 added = CollectEverything(player, trans);
        if (!added)
            return;

        CharacterDatabase.CommitTransaction(trans);
        ChatHandler(player->GetSession()).PSendSysMessage("{} {}", added, Tstr(player->GetSession(), LANG_TRANSMOG_SCAN_ADDED));
    }
};

void AddSC_TransmogCollectScript()
{
    new TransmogCollectScript();
}
