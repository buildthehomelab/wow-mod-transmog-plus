#include "Transmog.h"
#include "TransmogAddonProtocol.h"
#include "ScriptMgr.h"
#include "Chat.h"
#include "Player.h"
#include "WorldSession.h"
#include "Util.h"
#include "Tokenize.h"
#include "DBCStores.h"
#include <sstream>
#include <vector>
#include <string>
#include <string_view>
#include <algorithm>
#include <charconv>
#include <system_error>

// The addon protocol is carried through player chat messages using colon-delimited fields.
namespace TransmogAddon
{
    constexpr size_t MAX_IDS_PER_CHUNK = 20;
    // Keeps grouped and named messages well inside the client's 255-byte addon message limit.
    constexpr size_t MAX_PAYLOAD = 220;
    // Tooltips list at most this many sources per look.
    constexpr size_t MAX_SOURCES = 40;

    // Reject partial numeric tokens so malformed addon requests cannot be accepted.
    bool ParseUint32(std::string_view text, uint32& value)
    {
        if (text.empty())
            return false;

        auto parsed = std::from_chars(text.data(), text.data() + text.size(), value, 10);
        return parsed.ec == std::errc{} && parsed.ptr == text.data() + text.size();
    }

// Prefix every response so the addon can distinguish module traffic from normal chat.
    void SendToClient(Player* player, std::string const& payload)
    {
        if (!player || !player->GetSession())
            return;

        std::string full = std::string(PREFIX) + "\t" + payload;

        WorldPacket data;
        ChatHandler::BuildChatPacket(data, CHAT_MSG_WHISPER, LANG_ADDON, player, player, full);
        player->GetSession()->SendPacket(&data);
    }

    void SendOpen(Player* player)
    {
        SendToClient(player, "Open");
    }

    // Invalidate a client-side tooltip result when the server records a new appearance.
    void SendCollectionUpdated(Player* player, uint32 itemId)
    {
        SendToClient(player, "CollectionUpdated:" + std::to_string(itemId));
    }

    void SendIllusionCollected(Player* player, uint32 enchantId)
    {
        SendToClient(player, "IllusionCollected:" + std::to_string(enchantId));
    }

    // Splits "header + token:token:..." into messages under MAX_PAYLOAD without splitting a token.
    void SendTokens(Player* player, std::string const& header, std::vector<std::string> const& tokens)
    {
        std::string line;
        for (std::string const& token : tokens)
        {
            if (!line.empty() && header.size() + line.size() + 1 + token.size() > MAX_PAYLOAD)
            {
                SendToClient(player, header + line);
                line.clear();
            }
            if (!line.empty())
                line += ':';
            line += token;
        }
        if (!line.empty())
            SendToClient(player, header + line);
    }

    // Grouped variant, requested by addons that understand it (GetAvailableTransmogs:grouped).
    // A token is one look: "lead,source,source". A look too long for one message continues in
    // tokens starting with '+'. The count in the header is the number of looks.
    void SendAvailableGroupsForSlot(Player* player, uint8 slot)
    {
        Item* targetItem = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
        ItemTemplate const* targetTemplate = targetItem ? targetItem->GetTemplate() : nullptr;
        uint32 bucket = targetTemplate ? uint32(targetTemplate->Class) + uint32(targetTemplate->SubClass) : 0;

        auto groups = Transmog::GetValidAppearanceGroups(player, targetTemplate, slot);
        std::string header = "AvailableTransmogs:" + std::to_string(uint32(slot)) + ":" + std::to_string(bucket) + ":" + std::to_string(groups.size()) + ":";

        std::vector<std::string> tokens;
        size_t const tokenBudget = MAX_PAYLOAD - header.size();
        for (auto const& group : groups)
        {
            std::string token;
            for (ItemTemplate const* proto : group)
            {
                std::string id = std::to_string(proto->ItemId);
                if (!token.empty() && token.size() + 1 + id.size() > tokenBudget)
                {
                    tokens.push_back(token);
                    token = "+" + id;
                    continue;
                }
                token += token.empty() ? id : "," + id;
            }
            tokens.push_back(token);
        }

        SendToClient(player, header + "start");
        SendTokens(player, header, tokens);
        SendToClient(player, header + "end");
    }

// Status contains only non-empty slot overrides for compact client synchronization.
    void SendStatus(Player* player)
    {
        std::ostringstream out;
        uint32 count = 0;
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
        {
            uint32 fakeEntry = sTransmog->GetSlotAppearance(player->GetGUID(), slot);
            if (fakeEntry == 0)
                continue;

            out << ":" << uint32(slot) << "," << fakeEntry;
            ++count;
        }

        if (count == 0)
        {
            SendToClient(player, "TransmogStatus:0");
            return;
        }

        SendToClient(player, "TransmogStatus:" + std::to_string(count) + out.str());
    }

// Send one slot in bounded chunks because appearance lists can be large.
    void SendAvailableForSlot(Player* player, uint8 slot)
    {
        Item* targetItem = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
        ItemTemplate const* targetTemplate = targetItem ? targetItem->GetTemplate() : nullptr;
        uint32 bucket = targetTemplate ? uint32(targetTemplate->Class) + uint32(targetTemplate->SubClass) : 0;

        std::vector<ItemTemplate const*> appearances = Transmog::GetValidAppearances(player, targetTemplate);
        uint32 amount = static_cast<uint32>(appearances.size());

        std::string header = "AvailableTransmogs:" + std::to_string(uint32(slot)) + ":" + std::to_string(bucket) + ":" + std::to_string(amount) + ":";

        SendToClient(player, header + "start");

        size_t i = 0;
        while (i < appearances.size())
        {
            std::ostringstream chunk;
            // Send appearance IDs in bounded chunks to match the addon protocol.
            size_t end = std::min(i + MAX_IDS_PER_CHUNK, appearances.size());
            for (size_t j = i; j < end; ++j)
            {
                if (j != i)
                    chunk << ":";
                chunk << appearances[j]->ItemId;
            }
            SendToClient(player, header + chunk.str());
            i = end;
        }

        SendToClient(player, header + "end");
    }

    void SendAvailableAll(Player* player, bool grouped)
    {
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
        {
            if (Transmog::GetSlotName(slot).empty())
                continue;

            if (grouped)
                SendAvailableGroupsForSlot(player, slot);
            else
                SendAvailableForSlot(player, slot);
        }
    }

// The client receives either a failure flag or the applied slot and entry pair.
    void SendApplyResult(Player* player, bool success, uint8 slot, uint32 itemEntry)
    {
        if (!success)
        {
            SendToClient(player, "ApplyTransmogResult:0");
            return;
        }

        SendToClient(player, "ApplyTransmogResult:1:" + std::to_string(uint32(slot)) + "," + std::to_string(itemEntry));
    }

    void SendCost(Player* player, uint32 cost)
    {
        uint32 canPurchase = player->GetMoney() >= cost ? 1 : 0;
        SendToClient(player, "TransmogCost:" + std::to_string(cost) + ":" + std::to_string(canPurchase));
    }

    void HandleGetTransmogStatus(Player* player, std::string const&)
    {
        SendStatus(player);
    }

    // Answer collection-status requests from the account collection cache.
    void HandleGetCollectionStatus(Player* player, std::string const& args)
    {
        uint32 itemId;
        if (!ParseUint32(args, itemId) || itemId == 0)
            return;

        ItemTemplate const* itemTemplate = sObjectMgr->GetItemTemplate(itemId);
        if (!itemTemplate ||
            (itemTemplate->Class != ITEM_CLASS_ARMOR && itemTemplate->Class != ITEM_CLASS_WEAPON) ||
            TransmogRules_CanNeverTransmog(itemTemplate))
        {
            SendToClient(player, "CollectionStatus:" + std::to_string(itemId) + ":2");
            return;
        }

        uint32 accountId = player->GetSession()->GetAccountId();
        sTransmog->LoadCollectionForAccount(accountId);

        // Like retail, the look counts as collected when any item with the same model is.
        bool collected = sTransmog->IsAppearanceKnown(accountId, itemTemplate);

        SendToClient(player, "CollectionStatus:" + std::to_string(itemId) + ":" + (collected ? "1" : "0"));
    }

    void HandleGetAvailableTransmogs(Player* player, std::string const& args)
    {
        SendAvailableAll(player, args == "grouped");
    }

    // Every item sharing this item's look, collected or not: "Sources:<item>:<id>,<0|1>:...".
    void HandleGetSources(Player* player, std::string const& args)
    {
        uint32 itemId;
        if (!ParseUint32(args, itemId))
            return;

        std::string header = "Sources:" + std::to_string(itemId) + ":";
        ItemTemplate const* proto = sObjectMgr->GetItemTemplate(itemId);
        std::vector<uint32> const* sources = proto ? sTransmog->GetDisplaySources(proto->DisplayInfoID) : nullptr;

        uint32 accountId = player->GetSession()->GetAccountId();
        std::vector<std::string> tokens;
        if (sources)
        {
            std::shared_lock<std::shared_mutex> lock(sTransmog->collectionMutex);
            auto accountIt = sTransmog->collectionCache.find(accountId);
            for (uint32 source : *sources)
            {
                if (tokens.size() >= MAX_SOURCES)
                    break;
                bool collected = accountIt != sTransmog->collectionCache.end() && accountIt->second.contains(source);
                tokens.push_back(std::to_string(source) + (collected ? ",1" : ",0"));
            }
        }

        SendToClient(player, header + "start");
        SendTokens(player, header, tokens);
        SendToClient(player, header + "end");
    }

    // Outfit data is "slot,item;slot,item" with the addon's 1-based slot numbers.
    bool NormalizeOutfitData(std::string_view data, std::string& out)
    {
        out.clear();
        for (std::string_view pair : Acore::Tokenize(data, ';', false))
        {
            size_t comma = pair.find(',');
            uint32 slot;
            uint32 item;
            if (comma == std::string_view::npos || !ParseUint32(pair.substr(0, comma), slot) ||
                !ParseUint32(pair.substr(comma + 1), item) || slot < 1 || slot > EQUIPMENT_SLOT_END)
                return false;
            if (!out.empty())
                out += ';';
            out += std::to_string(slot) + "," + std::to_string(item);
        }
        return !out.empty() || data.empty();
    }

    bool IsValidOutfitName(std::string const& name)
    {
        if (name.empty() || name.size() > 48)
            return false;
        for (unsigned char c : name)
            if (c < 0x20 || c == '|' || c == 0x7F)
                return false;
        return true;
    }

    void HandleGetOutfits(Player* player, std::string const&)
    {
        SendToClient(player, "Outfits:start");
        QueryResult result = CharacterDatabase.Query("SELECT name, data FROM mod_transmog_plus_outfits WHERE account_id = {} ORDER BY name",
            player->GetSession()->GetAccountId());
        if (result)
        {
            do
            {
                SendToClient(player, "Outfit:" + (*result)[1].Get<std::string>() + ":" + (*result)[0].Get<std::string>());
            } while (result->NextRow());
        }
        SendToClient(player, "Outfits:end");
    }

    // "SaveOutfit:<data>:<name>"; the name comes last so it may contain ':'.
    void HandleSaveOutfit(Player* player, std::string const& args)
    {
        size_t colon = args.find(':');
        if (colon == std::string::npos)
            return;

        std::string data;
        std::string name = args.substr(colon + 1);
        if (!NormalizeOutfitData(std::string_view(args).substr(0, colon), data) || !IsValidOutfitName(name))
            return;

        uint32 accountId = player->GetSession()->GetAccountId();
        std::string escaped = name;
        CharacterDatabase.EscapeString(escaped);

        QueryResult count = CharacterDatabase.Query("SELECT COUNT(*), CAST(COALESCE(SUM(name = '{}'), 0) AS UNSIGNED) FROM mod_transmog_plus_outfits WHERE account_id = {}", escaped, accountId);
        if (count && (*count)[0].Get<uint64>() >= MAX_OUTFITS_PER_ACCOUNT && !(*count)[1].Get<uint64>())
        {
            SendToClient(player, "OutfitRejected:" + name);
            return;
        }

        CharacterDatabase.Execute("REPLACE INTO mod_transmog_plus_outfits (account_id, name, data) VALUES ({}, '{}', '{}')", accountId, escaped, data);
    }

    void HandleDeleteOutfit(Player* player, std::string const& name)
    {
        if (!IsValidOutfitName(name))
            return;

        std::string escaped = name;
        CharacterDatabase.EscapeString(escaped);
        CharacterDatabase.Execute("DELETE FROM mod_transmog_plus_outfits WHERE account_id = {} AND name = '{}'", player->GetSession()->GetAccountId(), escaped);
    }

    void SendIllusionStatus(Player* player)
    {
        SendToClient(player, "IllusionStatus:" + std::to_string(sTransmog->GetSlotIllusion(player->GetGUID(), EQUIPMENT_SLOT_MAINHAND)) + ":"
            + std::to_string(sTransmog->GetSlotIllusion(player->GetGUID(), EQUIPMENT_SLOT_OFFHAND)));
    }

    // Collected illusions ("Illusions:start", id lists, "Illusions:end"), each with its
    // localized name ("IllusionName:<id>:<name>"), then the current weapon slot illusions.
    void HandleGetIllusions(Player* player, std::string const&)
    {
        if (!sTransmog->IllusionsEnable)
            return;

        WorldSession* session = player->GetSession();
        uint32 accountId = session->GetAccountId();
        std::vector<uint32> ids;
        {
            std::shared_lock<std::shared_mutex> lock(sTransmog->collectionMutex);
            if (auto it = sTransmog->illusionCache.find(accountId); it != sTransmog->illusionCache.end())
                ids.assign(it->second.begin(), it->second.end());
        }
        std::sort(ids.begin(), ids.end());

        SendToClient(player, "Illusions:start");
        std::vector<std::string> tokens;
        for (uint32 id : ids)
        {
            SpellItemEnchantmentEntry const* enchant = sSpellItemEnchantmentStore.LookupEntry(id);
            if (!enchant)
                continue;
            char const* name = enchant->description[session->GetSessionDbcLocale()];
            if (!name || !*name)
                name = enchant->description[DEFAULT_LOCALE];
            SendToClient(player, "IllusionName:" + std::to_string(id) + ":" + std::string(name ? name : ""));
            tokens.push_back(std::to_string(id));
        }
        SendTokens(player, "Illusions:", tokens);
        SendToClient(player, "Illusions:end");
        SendIllusionStatus(player);
    }

    // "ApplyIllusion:<slot>:<enchant>" with 0 to remove and HIDDEN_ILLUSION_ID to hide the glow.
    void HandleApplyIllusion(Player* player, std::string const& args)
    {
        std::vector<std::string_view> parts = Acore::Tokenize(args, ':', false);
        uint32 slot;
        uint32 enchantId;
        if (parts.size() != 2 || !ParseUint32(parts[0], slot) || !ParseUint32(parts[1], enchantId) || slot >= EQUIPMENT_SLOT_END)
        {
            SendToClient(player, "ApplyIllusionResult:0:0:0");
            return;
        }

        TransmogApplyResult result = sTransmog->ApplyIllusion(player, uint8(slot), enchantId);
        bool success = result == TransmogApplyResult::Success || result == TransmogApplyResult::AlreadyApplied;
        SendToClient(player, "ApplyIllusionResult:" + std::string(success ? "1" : "0") + ":" + std::to_string(slot) + ":" + std::to_string(enchantId));
        SendIllusionStatus(player);
    }


// Parse and validate untrusted addon input before calling the shared apply path.
    void HandleApply(Player* player, std::string const& args)
    {
        std::vector<std::string_view> parts = Acore::Tokenize(args, ':', false);
        if (parts.size() != 2)
        {
            SendApplyResult(player, false, 0, 0);
            return;
        }

        uint32 parsedSlot;
        uint32 itemEntry;
        if (!ParseUint32(parts[0], parsedSlot) || !ParseUint32(parts[1], itemEntry) ||
            parsedSlot >= EQUIPMENT_SLOT_END || itemEntry == 0)
        {
            SendApplyResult(player, false, 0, 0);
            return;
        }

        uint8 slot = static_cast<uint8>(parsedSlot);
        TransmogApplyResult result = sTransmog->ApplyAppearance(player, slot, itemEntry);
        bool success = result == TransmogApplyResult::Success ||
            result == TransmogApplyResult::AlreadyApplied;
        SendApplyResult(player, success, slot, itemEntry);
    }

// Removal is a state reset and does not require an appearance collection check.
    void HandleRemove(Player* player, std::string const& args)
    {
        uint32 parsedSlot;
        if (!ParseUint32(args, parsedSlot) || parsedSlot >= EQUIPMENT_SLOT_END)
        {
            SendApplyResult(player, false, 0, 0);
            return;
        }

        uint8 slot = static_cast<uint8>(parsedSlot);

        sTransmog->SetSlotAppearance(player, slot, 0);
        sTransmog->RefreshSlot(player, slot);
        SendApplyResult(player, true, slot, 0);
    }

    void HandleRemoveAll(Player* player, std::string const&)
    {
        sTransmog->ClearAllSlots(player);
        sTransmog->RefreshAllSlots(player);
        SendStatus(player);
    }

// Calculate the same per-entry pricing used by appearance application.
    void HandleCalculateCost(Player* player, std::string const& args)
    {
        uint32 totalCost = 0;

        for (std::string_view pairStr : Acore::Tokenize(args, ',', false))
        {
            if (pairStr.empty())
                continue;

            // Illusions come as "i<slot>:<enchant>"; removing or hiding one is free.
            if (pairStr[0] == 'i')
            {
                size_t sep = pairStr.find(':');
                uint32 enchantId;
                if (sep != std::string_view::npos && ParseUint32(pairStr.substr(sep + 1), enchantId) &&
                    enchantId != 0 && enchantId != HIDDEN_ILLUSION_ID)
                    totalCost += sTransmog->PriceCopper;
                continue;
            }

            size_t colon = pairStr.find(':');
            if (colon == std::string_view::npos)
                continue;

            uint32 parsedSlot;
            uint32 itemEntry;
            if (!ParseUint32(pairStr.substr(0, colon), parsedSlot) ||
                !ParseUint32(pairStr.substr(colon + 1), itemEntry) ||
                parsedSlot >= EQUIPMENT_SLOT_END || itemEntry == 0)
                continue;

            totalCost += sTransmog->GetAppearanceCost(itemEntry);
        }

        SendCost(player, totalCost);
    }

// /transmog asks to open the window away from an NPC; the server has the final say.
    void HandleRequestPortable(Player* player, std::string const&)
    {
        if (!sTransmog->OpenAnywhere)
        {
            ChatHandler(player->GetSession()).SendSysMessage(Tstr(player->GetSession(), LANG_TRANSMOG_OPEN_ANYWHERE_DISABLED));
            return;
        }

        sTransmog->ClearSelection(player->GetGUID());
        SendToClient(player, "Portable");
    }

// Dispatch only recognized module commands and ignore unrelated chat traffic.
    void Dispatch(Player* player, std::string const& message)
    {
        size_t colon = message.find(':');
        std::string command = colon == std::string::npos ? message : message.substr(0, colon);
        std::string args = colon == std::string::npos ? std::string() : message.substr(colon + 1);

        if (command == "GetTransmogStatus")
            HandleGetTransmogStatus(player, args);
        // Keep tooltip collection requests on the same authenticated addon channel.
        else if (command == "GetCollectionStatus")
            HandleGetCollectionStatus(player, args);
        else if (command == "GetAvailableTransmogs")
            HandleGetAvailableTransmogs(player, args);
        else if (command == "Apply")
            HandleApply(player, args);
        else if (command == "Remove")
            HandleRemove(player, args);
        else if (command == "RemoveAll")
            HandleRemoveAll(player, args);
        else if (command == "CalculateCost")
            HandleCalculateCost(player, args);
        else if (command == "RequestPortable")
            HandleRequestPortable(player, args);
        else if (command == "GetSources")
            HandleGetSources(player, args);
        else if (command == "GetOutfits")
            HandleGetOutfits(player, args);
        else if (command == "SaveOutfit")
            HandleSaveOutfit(player, args);
        else if (command == "DeleteOutfit")
            HandleDeleteOutfit(player, args);
        else if (command == "GetIllusions")
            HandleGetIllusions(player, args);
        else if (command == "ApplyIllusion")
            HandleApplyIllusion(player, args);
    }
}

class TransmogAddonProtocolScript : public PlayerScript
{
public:
    TransmogAddonProtocolScript() : PlayerScript("TransmogAddonProtocolScript",
        {
            PLAYERHOOK_CAN_PLAYER_USE_PRIVATE_CHAT
        }) { }

// Consume addon whisper commands without interfering with ordinary player chat.
    bool OnPlayerCanUseChat(Player* player, uint32 /*type*/, uint32 lang, std::string& msg, Player* receiver) override
    {
        if (!sTransmog->Enable)
            return true;

        if (lang != LANG_ADDON || !receiver || receiver != player)
            return true;

        std::string const prefixTab = std::string(TransmogAddon::PREFIX) + "\t";
        if (msg.compare(0, prefixTab.size(), prefixTab) != 0)
            return true;

        TransmogAddon::Dispatch(player, msg.substr(prefixTab.size()));
        return false;
    }
};

void AddSC_TransmogAddonProtocol()
{
    new TransmogAddonProtocolScript();
}
