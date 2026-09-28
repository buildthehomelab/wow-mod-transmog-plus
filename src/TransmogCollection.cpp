#include "Transmog.h"
#include "TransmogAddonProtocol.h"
#include "Chat.h"
#include "DBCStores.h"
#include "Log.h"
#include <algorithm>

// Keep one shared collection cache per account while logged-in players reference it.
// Load one account cache and reuse it for all characters from that account.
void Transmog::LoadCollectionForAccount(uint32 accountId)
{
    {
        // Readers can inspect the shared cache concurrently.
        std::shared_lock<std::shared_mutex> lock(collectionMutex);
        if (collectionCache.contains(accountId))
            return;
    }

    std::unordered_set<uint32> items;
    std::unordered_set<uint32> displays;
    QueryResult result = CharacterDatabase.Query("SELECT item_template_id FROM mod_transmog_plus_appearances WHERE account_id = {}", accountId);
    if (result)
    {
        do
        {
            uint32 itemId = (*result)[0].Get<uint32>();
            items.insert(itemId);
            if (ItemTemplate const* proto = sObjectMgr->GetItemTemplate(itemId); proto && proto->DisplayInfoID)
                displays.insert(proto->DisplayInfoID);
        } while (result->NextRow());
    }

    std::unordered_set<uint32> illusions;
    result = CharacterDatabase.Query("SELECT enchant_id FROM mod_transmog_plus_illusions WHERE account_id = {}", accountId);
    if (result)
    {
        do
        {
            illusions.insert((*result)[0].Get<uint32>());
        } while (result->NextRow());
    }

    std::unique_lock<std::shared_mutex> lock(collectionMutex);
    if (!collectionCache.contains(accountId))
    {
        collectionCache.emplace(accountId, std::move(items));
        displayCache[accountId] = std::move(displays);
        illusionCache[accountId] = std::move(illusions);
    }
}

// Release the account cache only after the last character stops using it.
void Transmog::UnrefCollectionForAccount(uint32 accountId)
{
    std::unique_lock<std::shared_mutex> lock(collectionMutex);
    auto refIt = collectionRefCounts.find(accountId);
    if (refIt == collectionRefCounts.end())
        return;

    if (--refIt->second == 0)
    {
        collectionRefCounts.erase(refIt);
        collectionCache.erase(accountId);
        displayCache.erase(accountId);
        illusionCache.erase(accountId);
    }
}

// Collection updates use an exclusive lock so readers never observe a partial insert.
bool Transmog::AddCollectedAppearance(uint32 accountId, uint32 itemId)
{
    std::unique_lock<std::shared_mutex> lock(collectionMutex);
    if (ItemTemplate const* proto = sObjectMgr->GetItemTemplate(itemId); proto && proto->DisplayInfoID)
        displayCache[accountId].insert(proto->DisplayInfoID);

    auto accountIt = collectionCache.find(accountId);
    if (accountIt == collectionCache.end())
    {
        collectionCache.emplace(accountId, std::unordered_set<uint32>{ itemId });
        return true;
    }

    auto result = accountIt->second.insert(itemId);
    return result.second;
}

// Every unlock trigger (equip, pickup, disenchant, login scan) goes through here.
bool Transmog::CollectAppearance(Player* player, ItemTemplate const* proto, bool announce, CharacterDatabaseTransaction trans)
{
    if (!player || !proto)
        return false;

    if (proto->Class != ITEM_CLASS_ARMOR && proto->Class != ITEM_CLASS_WEAPON)
        return false;

    if (TransmogRules_CanNeverTransmog(proto))
        return false;

    WorldSession* session = player->GetSession();
    uint32 accountId = session->GetAccountId();
    uint32 itemId = proto->ItemId;

    LoadCollectionForAccount(accountId);

    // A new source for a look the account already has is recorded without a chat line.
    bool const newLook = !IsAppearanceKnown(accountId, proto);
    if (!AddCollectedAppearance(accountId, itemId))
        return false;

    if (trans)
        trans->Append("INSERT IGNORE INTO mod_transmog_plus_appearances (account_id, item_template_id) VALUES ({}, {})", accountId, itemId);
    else
        CharacterDatabase.Execute("INSERT IGNORE INTO mod_transmog_plus_appearances (account_id, item_template_id) VALUES ({}, {})", accountId, itemId);

    if (announce)
    {
        TransmogAddon::SendCollectionUpdated(player, itemId);
        if (newLook)
            ChatHandler(session).PSendSysMessage("{} {}", GetItemLink(itemId, session), Tstr(session, LANG_TRANSMOG_APPEARANCE_ADDED));
    }

    return true;
}

bool Transmog::IsAppearanceKnown(uint32 accountId, ItemTemplate const* proto) const
{
    if (!proto)
        return false;

    std::shared_lock<std::shared_mutex> lock(collectionMutex);
    if (auto it = collectionCache.find(accountId); it != collectionCache.end() && it->second.contains(proto->ItemId))
        return true;

    auto it = displayCache.find(accountId);
    return proto->DisplayInfoID && it != displayCache.end() && it->second.contains(proto->DisplayInfoID);
}

// Placeholder and developer items share models with real gear; keep them out of source lists.
static bool IsListableSource(ItemTemplate const& proto)
{
    if (proto.Class != ITEM_CLASS_ARMOR && proto.Class != ITEM_CLASS_WEAPON)
        return false;

    if (!proto.DisplayInfoID || TransmogRules_CanNeverTransmog(&proto))
        return false;

    for (char const* marker : { "Monster -", "Deprecated", "DEPRECATED", "OLD", "[PH]", "Test ", "TEST", "QA " })
        if (proto.Name1.find(marker) != std::string::npos)
            return false;

    return true;
}

void Transmog::BuildAppearanceIndex()
{
    std::unordered_map<uint32, std::vector<uint32>> index;
    for (auto const& [entry, proto] : *sObjectMgr->GetItemTemplateStore())
        if (IsListableSource(proto))
            index[proto.DisplayInfoID].push_back(entry);

    for (auto& [display, sources] : index)
        std::sort(sources.begin(), sources.end());

    displaySources = std::move(index);
    LOG_INFO("module", "mod-transmog-plus: indexed {} looks for appearance sources", displaySources.size());
}

std::vector<uint32> const* Transmog::GetDisplaySources(uint32 displayId) const
{
    auto it = displaySources.find(displayId);
    return it == displaySources.end() ? nullptr : &it->second;
}

bool Transmog::IsIllusionEnchant(uint32 enchantId)
{
    if (!enchantId || enchantId == HIDDEN_ILLUSION_ID || enchantId > 0xFFFF)
        return false;

    SpellItemEnchantmentEntry const* enchant = sSpellItemEnchantmentStore.LookupEntry(enchantId);
    return enchant && enchant->aura_id != 0;
}

bool Transmog::IsIllusionSlot(uint8 slot)
{
    return slot == EQUIPMENT_SLOT_MAINHAND || slot == EQUIPMENT_SLOT_OFFHAND;
}

// Enchant glows only render on melee weapons; shields and off-hand frills have none.
bool Transmog::CanHaveIllusion(Item const* item)
{
    if (!item)
        return false;

    ItemTemplate const* proto = item->GetTemplate();
    return proto->Class == ITEM_CLASS_WEAPON && proto->InventoryType != INVTYPE_RANGED
        && proto->InventoryType != INVTYPE_RANGEDRIGHT && proto->InventoryType != INVTYPE_THROWN
        && proto->SubClass != ITEM_SUBCLASS_WEAPON_FISHING_POLE;
}

bool Transmog::CollectIllusion(Player* player, uint32 enchantId, bool announce, CharacterDatabaseTransaction trans)
{
    if (!IllusionsEnable || !player || !IsIllusionEnchant(enchantId))
        return false;

    WorldSession* session = player->GetSession();
    uint32 accountId = session->GetAccountId();
    LoadCollectionForAccount(accountId);

    {
        std::unique_lock<std::shared_mutex> lock(collectionMutex);
        if (!illusionCache[accountId].insert(enchantId).second)
            return false;
    }

    if (trans)
        trans->Append("INSERT IGNORE INTO mod_transmog_plus_illusions (account_id, enchant_id) VALUES ({}, {})", accountId, enchantId);
    else
        CharacterDatabase.Execute("INSERT IGNORE INTO mod_transmog_plus_illusions (account_id, enchant_id) VALUES ({}, {})", accountId, enchantId);

    if (announce)
    {
        TransmogAddon::SendIllusionCollected(player, enchantId);
        SpellItemEnchantmentEntry const* enchant = sSpellItemEnchantmentStore.LookupEntry(enchantId);
        char const* name = enchant ? enchant->description[session->GetSessionDbcLocale()] : "";
        if (!name || !*name)
            name = enchant ? enchant->description[DEFAULT_LOCALE] : "";
        ChatHandler(session).PSendSysMessage("|cffff80ff[{}]|r {}", name, Tstr(session, LANG_TRANSMOG_ILLUSION_ADDED));
    }

    return true;
}

uint32 Transmog::CollectIllusionsFromItem(Player* player, Item const* item, bool announce, CharacterDatabaseTransaction trans)
{
    if (!CanHaveIllusion(item))
        return 0;

    uint32 added = 0;
    for (EnchantmentSlot slot : { PERM_ENCHANTMENT_SLOT, TEMP_ENCHANTMENT_SLOT })
        added += CollectIllusion(player, item->GetEnchantmentId(slot), announce, trans) ? 1 : 0;
    return added;
}
