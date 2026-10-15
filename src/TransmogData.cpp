#include "Transmog.h"

namespace
{
// Ignore stale rows so invalid database data cannot affect login.
void ReadSlotRow(std::array<uint32, EQUIPMENT_SLOT_END>& slots, uint8 slot, uint32 fakeEntry)
{
    if (slot >= EQUIPMENT_SLOT_END)
        return;
    if (fakeEntry == HIDDEN_ITEM_ID && !TransmogRules_IsArmorSlot(slot))
        return;
    if (fakeEntry == HIDDEN_ITEM_ID || sObjectMgr->GetItemTemplate(fakeEntry))
        slots[slot] = fakeEntry;
}

void ReadIllusionRow(std::array<uint32, 2>& illusions, uint8 slot, uint32 enchantId)
{
    if (Transmog::IsIllusionSlot(slot) && (enchantId == HIDDEN_ILLUSION_ID || Transmog::IsIllusionEnchant(enchantId)))
        illusions[slot - EQUIPMENT_SLOT_MAINHAND] = enchantId;
}
}

// Restore slot overrides before visible-item refreshes run for the player.
void Transmog::LoadPlayerSlots(ObjectGuid guid)
{
    std::array<uint32, EQUIPMENT_SLOT_END> localSlots;
    localSlots.fill(0);

    QueryResult result = CharacterDatabase.Query("SELECT Slot, FakeEntry FROM mod_transmog_plus WHERE Owner = {}", guid.GetCounter());
    if (result)
    {
        do
        {
            ReadSlotRow(localSlots, (*result)[0].Get<uint8>(), (*result)[1].Get<uint32>());
        } while (result->NextRow());
    }

    std::array<uint32, 2> localIllusions{ 0, 0 };
    result = CharacterDatabase.Query("SELECT Slot, EnchantId FROM mod_transmog_plus_illusion_slots WHERE Owner = {}", guid.GetCounter());
    if (result)
    {
        do
        {
            ReadIllusionRow(localIllusions, (*result)[0].Get<uint8>(), (*result)[1].Get<uint32>());
        } while (result->NextRow());
    }

    std::unique_lock<std::shared_mutex> lock(slotMapMutex);
    slotMap[guid] = localSlots;
    illusionMap[guid] = localIllusions;
}

// Bots load their slots asynchronously. The callback runs from the session's own query
// processor, which Map::Update drives for bots too.
void Transmog::QueueBotSlotLoad(Player* player)
{
    WorldSession* session = player->GetSession();
    ObjectGuid const guid = player->GetGUID();
    session->GetQueryProcessor().AddCallback(CharacterDatabase.AsyncQuery(Acore::StringFormat(
        "SELECT 0, Slot, FakeEntry FROM mod_transmog_plus WHERE Owner = {0} "
        "UNION ALL SELECT 1, Slot, EnchantId FROM mod_transmog_plus_illusion_slots WHERE Owner = {0}", guid.GetCounter()))
        .WithCallback([this, session, guid](QueryResult result)
        {
            // Random bots have no rows; alt bots only when transmogged as a player.
            if (!result)
                return;

            Player* player = session->GetPlayer();
            if (!player || player->GetGUID() != guid)
                return;

            std::array<uint32, EQUIPMENT_SLOT_END> localSlots;
            localSlots.fill(0);
            std::array<uint32, 2> localIllusions{ 0, 0 };
            do
            {
                if ((*result)[0].Get<uint64>() == 0) // literal column: BIGINT
                    ReadSlotRow(localSlots, (*result)[1].Get<uint8>(), (*result)[2].Get<uint32>());
                else
                    ReadIllusionRow(localIllusions, (*result)[1].Get<uint8>(), (*result)[2].Get<uint32>());
            } while (result->NextRow());

            {
                std::unique_lock<std::shared_mutex> lock(slotMapMutex);
                slotMap[guid] = localSlots;
                illusionMap[guid] = localIllusions;
            }

            RefreshAllSlots(player);
        }));
}

// Slot state is removed from memory when the player leaves the world.
void Transmog::UnloadPlayerSlots(ObjectGuid guid)
{
    std::unique_lock<std::shared_mutex> lock(slotMapMutex);
    slotMap.erase(guid);
    illusionMap.erase(guid);
}

uint32 Transmog::GetSlotIllusion(ObjectGuid guid, uint8 slot) const
{
    if (!IsIllusionSlot(slot))
        return 0;

    std::shared_lock<std::shared_mutex> lock(slotMapMutex);
    auto it = illusionMap.find(guid);
    return it == illusionMap.end() ? 0 : it->second[slot - EQUIPMENT_SLOT_MAINHAND];
}

// A zero enchant removes the illusion; HIDDEN_ILLUSION_ID hides the weapon's glow.
void Transmog::SetSlotIllusion(Player* player, uint8 slot, uint32 enchantId)
{
    if (!IsIllusionSlot(slot))
        return;

    ObjectGuid guid = player->GetGUID();
    {
        std::unique_lock<std::shared_mutex> lock(slotMapMutex);
        illusionMap[guid][slot - EQUIPMENT_SLOT_MAINHAND] = enchantId;
    }

    if (enchantId == 0)
        CharacterDatabase.Execute("DELETE FROM mod_transmog_plus_illusion_slots WHERE Owner = {} AND Slot = {}", guid.GetCounter(), slot);
    else
        CharacterDatabase.Execute("REPLACE INTO mod_transmog_plus_illusion_slots (Owner, Slot, EnchantId) VALUES ({}, {}, {})", guid.GetCounter(), slot, enchantId);
}

uint16 Transmog::GetVisiblePermEnchantForSlot(Player const* player, uint8 slot, Item const* item) const
{
    if (!item)
        return 0;

    uint16 real = uint16(item->GetEnchantmentId(PERM_ENCHANTMENT_SLOT));
    if (!IllusionsEnable || !CanHaveIllusion(item))
        return real;

    uint32 illusion = GetSlotIllusion(player->GetGUID(), slot);
    if (illusion == HIDDEN_ILLUSION_ID)
        return 0;
    return illusion ? uint16(illusion) : real;
}

uint16 Transmog::GetVisibleTempEnchantForSlot(Player const* player, uint8 slot, Item const* item) const
{
    if (!item)
        return 0;

    if (IllusionsEnable && CanHaveIllusion(item) && GetSlotIllusion(player->GetGUID(), slot) == HIDDEN_ILLUSION_ID)
        return 0;
    return uint16(item->GetEnchantmentId(TEMP_ENCHANTMENT_SLOT));
}

// A zero entry removes the override; other entries replace it in storage.
void Transmog::SetSlotAppearance(Player* player, uint8 slot, uint32 fakeEntry)
{
    if (slot >= EQUIPMENT_SLOT_END)
        return;

    ObjectGuid guid = player->GetGUID();

    {
        std::unique_lock<std::shared_mutex> lock(slotMapMutex);
        slotMap[guid][slot] = fakeEntry;
    }

    if (fakeEntry == 0)
        CharacterDatabase.Execute("DELETE FROM mod_transmog_plus WHERE Owner = {} AND Slot = {}", guid.GetCounter(), slot);
    else
        CharacterDatabase.Execute("REPLACE INTO mod_transmog_plus (Owner, Slot, FakeEntry) VALUES ({}, {}, {})", guid.GetCounter(), slot, fakeEntry);
}

// Missing or invalid slots intentionally resolve to no appearance.
uint32 Transmog::GetSlotAppearance(ObjectGuid guid, uint8 slot) const
{
    if (slot >= EQUIPMENT_SLOT_END)
        return 0;

    std::shared_lock<std::shared_mutex> lock(slotMapMutex);
    auto it = slotMap.find(guid);
    if (it == slotMap.end())
        return 0;
    return it->second[slot];
}

// Apply the stored appearance through the normal player visible-item fields.
void Transmog::ApplySlot(Player* player, uint8 slot, Item* item)
{
    if (slot >= EQUIPMENT_SLOT_END)
        return;

    uint16 index = GetVisibleItemIndex(slot);
    uint32 entry = GetVisibleEntryForSlot(player, slot, item);
    uint32 fakeEntry = item ? GetSlotAppearance(player->GetGUID(), slot) : 0;

    player->SetUInt32Value(index, entry);

    if (!item)
    {
        player->SetUInt32Value(index + 1, 0);
        return;
    }

    if (fakeEntry == HIDDEN_ITEM_ID && TransmogRules_IsArmorSlot(slot))
    {
        player->SetUInt16Value(index + 1, 0, 0);
        player->SetUInt16Value(index + 1, 1, 0);
    }
    else
    {
        player->SetUInt16Value(index + 1, 0, GetVisiblePermEnchantForSlot(player, slot, item));
        player->SetUInt16Value(index + 1, 1, GetVisibleTempEnchantForSlot(player, slot, item));
    }
}

// Reapply one slot after equipment, appearance, or visibility state changes.
void Transmog::RefreshSlot(Player* player, uint8 slot)
{
    if (slot >= EQUIPMENT_SLOT_END)
        return;

    Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
    player->SetVisibleItemSlot(slot, item);
}

// Login and broad state changes refresh every equipment slot together.
void Transmog::RefreshAllSlots(Player* player)
{
    for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
        RefreshSlot(player, slot);
}

// Clear persisted overrides without changing the player equipment itself.
void Transmog::ClearAllSlots(Player* player)
{
    ObjectGuid guid = player->GetGUID();
    {
        std::unique_lock<std::shared_mutex> lock(slotMapMutex);
        auto it = slotMap.find(guid);
        if (it != slotMap.end())
            it->second.fill(0);
        if (auto ill = illusionMap.find(guid); ill != illusionMap.end())
            ill->second.fill(0);
    }
    CharacterDatabase.Execute("DELETE FROM mod_transmog_plus WHERE Owner = {}", guid.GetCounter());
    CharacterDatabase.Execute("DELETE FROM mod_transmog_plus_illusion_slots WHERE Owner = {}", guid.GetCounter());
}

// Selection is UI state and defaults to the first equipment slot.
uint8 Transmog::GetSelectedSlot(ObjectGuid guid) const
{
    std::shared_lock<std::shared_mutex> lock(slotMapMutex);
    auto it = selectionCache.find(guid);
    if (it == selectionCache.end())
        return EQUIPMENT_SLOT_END;
    return it->second;
}

// The selected slot is kept separate from persisted appearance data.
void Transmog::SetSelectedSlot(ObjectGuid guid, uint8 slot)
{
    std::unique_lock<std::shared_mutex> lock(slotMapMutex);
    selectionCache[guid] = slot;
}

void Transmog::ClearSelection(ObjectGuid guid)
{
    std::unique_lock<std::shared_mutex> lock(slotMapMutex);
    selectionCache.erase(guid);
}
