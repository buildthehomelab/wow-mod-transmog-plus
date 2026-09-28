#include "Transmog.h"
#include "TransmogAddonProtocol.h"
#include "Chat.h"

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
    QueryResult result = CharacterDatabase.Query("SELECT item_template_id FROM mod_transmog_plus_appearances WHERE account_id = {}", accountId);
    if (result)
    {
        do
        {
            items.insert((*result)[0].Get<uint32>());
        } while (result->NextRow());
    }

    std::unique_lock<std::shared_mutex> lock(collectionMutex);
    if (!collectionCache.contains(accountId))
        collectionCache.emplace(accountId, std::move(items));
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
    }
}

// Collection updates use an exclusive lock so readers never observe a partial insert.
bool Transmog::AddCollectedAppearance(uint32 accountId, uint32 itemId)
{
    std::unique_lock<std::shared_mutex> lock(collectionMutex);
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

    if (!AddCollectedAppearance(accountId, itemId))
        return false;

    if (trans)
        trans->Append("INSERT IGNORE INTO mod_transmog_plus_appearances (account_id, item_template_id) VALUES ({}, {})", accountId, itemId);
    else
        CharacterDatabase.Execute("INSERT IGNORE INTO mod_transmog_plus_appearances (account_id, item_template_id) VALUES ({}, {})", accountId, itemId);

    if (announce)
    {
        TransmogAddon::SendCollectionUpdated(player, itemId);
        ChatHandler(session).PSendSysMessage("{} {}", GetItemLink(itemId, session), Tstr(session, LANG_TRANSMOG_APPEARANCE_ADDED));
    }

    return true;
}
