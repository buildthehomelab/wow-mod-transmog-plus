#include "Transmog.h"
#include "Bag.h"
#include "Chat.h"
#include "Group.h"
#include "Spell.h"
#include "SpellInfo.h"
#include <atomic>
#include <mutex>
#include <type_traits>
#include <unordered_map>
#include <utility>
#include <vector>

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
    struct ScanCounts
    {
        uint32 appearances = 0;
        uint32 illusions = 0;
    };

    void CollectItem(Player* player, Item* item, CharacterDatabaseTransaction trans, ScanCounts& counts)
    {
        if (!item)
            return;

        counts.appearances += sTransmog->CollectAppearance(player, item->GetTemplate(), false, trans) ? 1 : 0;
        counts.illusions += sTransmog->CollectIllusionsFromItem(player, item, false, trans);
    }

    void CollectBag(Player* player, uint8 bagPos, CharacterDatabaseTransaction trans, ScanCounts& counts)
    {
        if (Bag* bag = player->GetBagByPos(bagPos))
            for (uint32 slot = 0; slot < bag->GetBagSize(); ++slot)
                CollectItem(player, bag->GetItemByPos(slot), trans, counts);
    }

    ScanCounts CollectEverything(Player* player, CharacterDatabaseTransaction trans)
    {
        ScanCounts counts;

        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
            CollectItem(player, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot), trans, counts);

        for (uint8 slot = INVENTORY_SLOT_ITEM_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
            CollectItem(player, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot), trans, counts);
        for (uint8 bagPos = INVENTORY_SLOT_BAG_START; bagPos < INVENTORY_SLOT_BAG_END; ++bagPos)
            CollectBag(player, bagPos, trans, counts);

        for (uint8 slot = BANK_SLOT_ITEM_START; slot < BANK_SLOT_ITEM_END; ++slot)
            CollectItem(player, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot), trans, counts);
        for (uint8 bagPos = BANK_SLOT_BAG_START; bagPos < BANK_SLOT_BAG_END; ++bagPos)
            CollectBag(player, bagPos, trans, counts);

        return counts;
    }

    // The spell-cast hook fires before the cast's last checks, and trade-window enchants only
    // land once the trade completes. So a cast is remembered, and the illusion is collected when
    // the enchant actually shows up on the weapon within a few seconds.
    struct PendingEnchant
    {
        ObjectGuid item;
        uint32 enchantId;
        int32 msLeft;
    };

    constexpr int32 PENDING_ENCHANT_MS = 3000;
    std::mutex pendingMutex;
    std::unordered_map<ObjectGuid, std::vector<PendingEnchant>> pendingEnchants;
    // Lets every player update skip the lock while nothing is pending.
    std::atomic<uint32> pendingCount{ 0 };

    void AddPendingEnchant(Player* player, Item* item, uint32 enchantId)
    {
        std::lock_guard<std::mutex> lock(pendingMutex);
        pendingEnchants[player->GetGUID()].push_back({ item->GetGUID(), enchantId, PENDING_ENCHANT_MS });
        ++pendingCount;
    }

    void CheckPendingEnchants(Player* player, uint32 diff)
    {
        if (!pendingCount.load())
            return;

        std::vector<uint32> landed;
        {
            std::lock_guard<std::mutex> lock(pendingMutex);
            auto it = pendingEnchants.find(player->GetGUID());
            if (it == pendingEnchants.end())
                return;

            auto& list = it->second;
            for (auto entry = list.begin(); entry != list.end();)
            {
                Item* item = player->GetItemByGuid(entry->item);
                bool const applied = item && (item->GetEnchantmentId(PERM_ENCHANTMENT_SLOT) == entry->enchantId
                    || item->GetEnchantmentId(TEMP_ENCHANTMENT_SLOT) == entry->enchantId);
                entry->msLeft -= int32(diff);
                if (applied || entry->msLeft <= 0)
                {
                    if (applied)
                        landed.push_back(entry->enchantId);
                    entry = list.erase(entry);
                    --pendingCount;
                }
                else
                    ++entry;
            }
            if (list.empty())
                pendingEnchants.erase(it);
        }

        for (uint32 enchantId : landed)
            sTransmog->CollectIllusion(player, enchantId, true);
    }

    void DropPendingEnchants(Player* player)
    {
        std::lock_guard<std::mutex> lock(pendingMutex);
        auto it = pendingEnchants.find(player->GetGUID());
        if (it == pendingEnchants.end())
            return;
        pendingCount -= uint32(it->second.size());
        pendingEnchants.erase(it);
    }

    // Enchanting a weapon teaches its illusion. Temporary enchants (shaman imbues, oils) without
    // an item target land on the main hand.
    void CollectCastIllusions(Player* player, Spell* spell)
    {
        // Effects (not GetEffects()) so older AzerothCore builds compile too.
        for (SpellEffectInfo const& effect : spell->GetSpellInfo()->Effects)
        {
            if (effect.Effect != SPELL_EFFECT_ENCHANT_ITEM && effect.Effect != SPELL_EFFECT_ENCHANT_ITEM_TEMPORARY)
                continue;

            Item* target = spell->m_targets.GetItemTarget();
            if (!target && effect.Effect == SPELL_EFFECT_ENCHANT_ITEM_TEMPORARY)
                target = player->GetItemByPos(INVENTORY_SLOT_BAG_0, EQUIPMENT_SLOT_MAINHAND);

            if (Transmog::CanHaveIllusion(target) && Transmog::IsIllusionEnchant(uint32(effect.MiscValue)))
                AddPendingEnchant(player, target, uint32(effect.MiscValue));
        }
    }
}

class TransmogCollectScript : public PlayerScript
{
public:
    TransmogCollectScript() : PlayerScript("TransmogCollectScript", {
        PLAYERHOOK_ON_STORE_NEW_ITEM,
        PLAYERHOOK_ON_AFTER_MOVE_ITEM_TO_INVENTORY,
        PLAYERHOOK_ON_SPELL_CAST,
        PLAYERHOOK_ON_LOGIN,
        PLAYERHOOK_ON_LOGOUT,
        PLAYERHOOK_ON_UPDATE
    }) { }

    void OnPlayerUpdate(Player* player, uint32 diff) override
    {
        CheckPendingEnchants(player, diff);
    }

    void OnPlayerLogout(Player* player) override
    {
        DropPendingEnchants(player);
    }

// Every newly created item: loot, vendor, quest reward, crafting. Starting gear is stored before
// the character is in the world; the login scan picks that up instead.
    void OnPlayerStoreNewItem(Player* player, Item* item, uint32 /*count*/) override
    {
        if (sTransmog->CollectOnPickup && item && player->IsInWorld() && TransmogCollect_CanCollect(player))
        {
            sTransmog->CollectAppearance(player, item->GetTemplate(), true);
            sTransmog->CollectIllusionsFromItem(player, item, true);
        }
    }

// Existing items changing hands: trade, mail (including the auction house), guild bank.
    void OnPlayerAfterMoveItemToInventory(Player* player, Item* item, bool /*update*/) override
    {
        if (sTransmog->CollectOnPickup && item && player->IsInWorld() && TransmogCollect_CanCollect(player))
        {
            sTransmog->CollectAppearance(player, item->GetTemplate(), true);
            sTransmog->CollectIllusionsFromItem(player, item, true);
        }
    }

// Runs as the cast goes off, while the item is still there to read.
    void OnPlayerSpellCast(Player* player, Spell* spell, bool /*skipCheck*/) override
    {
        if (!spell || !TransmogCollect_CanCollect(player))
            return;

        if (sTransmog->IllusionsEnable)
            CollectCastIllusions(player, spell);

        if (!sTransmog->CollectOnDisenchant || !spell->GetSpellInfo()->HasEffect(SPELL_EFFECT_DISENCHANT))
            return;

        if (Item* item = spell->m_targets.GetItemTarget())
            sTransmog->CollectAppearance(player, item->GetTemplate(), true);
    }

// Unlock everything already equipped, in the bags or in the bank, and report it in one line.
    void OnPlayerLogin(Player* player) override
    {
        if (!sTransmog->CollectScanOnLogin || !TransmogCollect_CanCollect(player))
            return;

        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        ScanCounts counts = CollectEverything(player, trans);
        if (!counts.appearances && !counts.illusions)
            return;

        CharacterDatabase.CommitTransaction(trans);
        if (counts.appearances)
            ChatHandler(player->GetSession()).PSendSysMessage("{} {}", counts.appearances, Tstr(player->GetSession(), LANG_TRANSMOG_SCAN_ADDED));
    }
};

void AddSC_TransmogCollectScript()
{
    new TransmogCollectScript();
}
