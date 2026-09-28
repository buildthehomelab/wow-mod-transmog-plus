#include "Transmog.h"
#include "ByteBuffer.h"
#include "UpdateFields.h"

class TransmogUnitScript : public UnitScript
{
public:
    TransmogUnitScript() : UnitScript("TransmogUnitScript", true, {
        UNITHOOK_SHOULD_TRACK_VALUES_UPDATE_POS_BY_INDEX,
        UNITHOOK_ON_PATCH_VALUES_UPDATE
    }) { }

// Limit patch tracking to player visible-item fields to avoid unrelated updates.
    bool ShouldTrackValuesUpdatePosByIndex(Unit const* unit, uint8, uint16 index) override
    {
        return unit->IsPlayer() && (IsEntryField(index) || IllusionSlotOfField(index) != EQUIPMENT_SLOT_END);
    }

    static bool IsEntryField(uint16 index)
    {
        return index >= PLAYER_VISIBLE_ITEM_1_ENTRYID && index <= PLAYER_VISIBLE_ITEM_19_ENTRYID && (index & 1);
    }

    // Weapon enchant fields, so illusions survive the core writing enchants directly
    // (Player::ApplyEnchantment sets the visible enchant without SetVisibleItemSlot).
    static uint8 IllusionSlotOfField(uint16 index)
    {
        for (uint8 slot : { EQUIPMENT_SLOT_MAINHAND, EQUIPMENT_SLOT_OFFHAND })
            if (index == PLAYER_VISIBLE_ITEM_1_ENCHANTMENT + slot * 2)
                return slot;
        return EQUIPMENT_SLOT_END;
    }

// Replace visible-item data in the outgoing update while preserving the packet shape.
    void OnPatchValuesUpdate(Unit const* unit, ByteBuffer& valuesUpdateBuf, BuildValuesCachePosPointers& posPointers, Player*) override
    {
        if (!unit->IsPlayer())
            return;

        Player const* player = unit->ToPlayer();
        if (!player)
            return;

        for (auto const& pair : posPointers.other)
        {
            if (!pair.second)
                continue;

            uint16 index = pair.first;

            if (uint8 weaponSlot = IllusionSlotOfField(index); weaponSlot != EQUIPMENT_SLOT_END)
            {
                Item const* weapon = player->GetItemByPos(INVENTORY_SLOT_BAG_0, weaponSlot);
                uint32 perm = weapon ? weapon->GetEnchantmentId(PERM_ENCHANTMENT_SLOT) : 0;
                uint32 temp = weapon ? weapon->GetEnchantmentId(TEMP_ENCHANTMENT_SLOT) : 0;
                if (sTransmog->Enable)
                {
                    perm = sTransmog->GetVisiblePermEnchantForSlot(player, weaponSlot, weapon);
                    temp = sTransmog->GetVisibleTempEnchantForSlot(player, weaponSlot, weapon);
                }
                valuesUpdateBuf.put(pair.second, uint32((perm & 0xFFFF) | (temp << 16)));
                continue;
            }

            // Transmog display data is patched through the odd visible-item update fields.
            if (!IsEntryField(index))
                continue;

            uint8 slot = (index - PLAYER_VISIBLE_ITEM_1_ENTRYID) / 2;
            if (slot >= EQUIPMENT_SLOT_END)
                continue;

            Item const* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
            uint32 entry;

            if (sTransmog->Enable)
                entry = sTransmog->GetVisibleEntryForSlot(player, slot, item);
            else
                entry = item ? item->GetEntry() : 0;

            valuesUpdateBuf.put(pair.second, entry);
        }
    }
};

void AddSC_TransmogUnitScript()
{
    new TransmogUnitScript();
}
