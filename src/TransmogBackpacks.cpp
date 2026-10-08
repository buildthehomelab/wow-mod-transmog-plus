#include "Transmog.h"
#include "TransmogAddonProtocol.h"
#include "Chat.h"
#include "DBCStores.h"
#include "Mail.h"
#include "SpellAuras.h"
#include "SpellMgr.h"
#include "StringFormat.h"
#include <atomic>
#include <memory>

// Backpacks: a model on the character's back, shown through a hidden dummy aura whose spell
// visual attaches the model (the realm's client patch carries the spells, visuals and models).
// Each character unlocks backpacks one at a time: most by clearing an individual progression
// phase, the first one from an item in an introduction letter. The chosen one shows on the
// back and hides the cloak while it does.

namespace
{
    // How often a logged-in player's backpack aura is checked against what it should be.
    constexpr uint32 RECONCILE_MS = 1000;
    // Individual progression phases are quests base+1 .. base+MAX_PHASE.
    constexpr uint8 MAX_PHASE = 18;

    // The letter waits in the mailbox this long (default NPC mail lasts 30 days, then its
    // item is deleted).
    constexpr uint32 MAIL_EXPIRE_DAYS = 5 * 365;

    // unlocked and chosen change under the map's exclusive lock. The reconcile timer and the
    // dirty flag are touched by map update threads under the shared lock, so they're atomic.
    struct BackpackPlayerState
    {
        std::unordered_set<uint32> unlocked;
        uint32 chosen = 0;
        std::atomic<uint32> timer{ 0 };
        std::atomic<bool> dirty{ true };
    };

    std::unordered_map<ObjectGuid, std::unique_ptr<BackpackPlayerState>> playerStates;
    std::shared_mutex playerStatesMutex;
}

void Transmog::LoadBackpacks()
{
    backpacks.clear();
    backpackSpells.clear();
    if (!BackpacksEnable)
        return;

    QueryResult result = WorldDatabase.Query("SELECT Id, Name, SpellId, UnlockPhase, UnlockItem, Model FROM mod_transmog_plus_backpacks ORDER BY SortOrder, Id");
    if (!result)
        return;

    do
    {
        Field* fields = result->Fetch();
        BackpackEntry entry;
        entry.id = fields[0].Get<uint32>();
        entry.name = fields[1].Get<std::string>();
        entry.spellId = fields[2].Get<uint32>();
        entry.unlockPhase = fields[3].Get<uint8>();
        entry.unlockItem = fields[4].Get<uint32>();
        entry.model = fields[5].Get<std::string>();

        if (!entry.id || !sSpellMgr->GetSpellInfo(entry.spellId))
        {
            LOG_ERROR("module", "mod-transmog-plus: backpack {} skipped, spell {} doesn't exist (spell_dbc)", entry.id, entry.spellId);
            continue;
        }
        backpackSpells.insert(entry.spellId);
        backpacks.push_back(std::move(entry));
    } while (result->NextRow());

    LOG_INFO("module", "mod-transmog-plus: {} backpacks loaded", backpacks.size());
}

Transmog::BackpackEntry const* Transmog::GetBackpack(uint32 id) const
{
    for (BackpackEntry const& entry : backpacks)
        if (entry.id == id)
            return &entry;
    return nullptr;
}

Transmog::BackpackEntry const* Transmog::GetBackpackByItem(uint32 itemEntry) const
{
    for (BackpackEntry const& entry : backpacks)
        if (entry.unlockItem && entry.unlockItem == itemEntry)
            return &entry;
    return nullptr;
}

void Transmog::LoadPlayerBackpacks(ObjectGuid guid)
{
    auto state = std::make_unique<BackpackPlayerState>();
    if (QueryResult result = CharacterDatabase.Query("SELECT BackpackId FROM mod_transmog_plus_backpack_unlocks WHERE Owner = {}", guid.GetCounter()))
    {
        do
            state->unlocked.insert(result->Fetch()[0].Get<uint32>());
        while (result->NextRow());
    }
    if (QueryResult result = CharacterDatabase.Query("SELECT BackpackId FROM mod_transmog_plus_backpack_choice WHERE Owner = {}", guid.GetCounter()))
        state->chosen = result->Fetch()[0].Get<uint32>();

    // A removed backpack, or one that is no longer unlocked, isn't shown.
    if (state->chosen && (!GetBackpack(state->chosen) || !state->unlocked.contains(state->chosen)))
        state->chosen = 0;

    std::unique_lock<std::shared_mutex> lock(playerStatesMutex);
    playerStates[guid] = std::move(state);
}

void Transmog::UnloadPlayerBackpacks(ObjectGuid guid)
{
    std::unique_lock<std::shared_mutex> lock(playerStatesMutex);
    playerStates.erase(guid);
}

bool Transmog::IsBackpackUnlocked(ObjectGuid guid, uint32 id) const
{
    std::shared_lock<std::shared_mutex> lock(playerStatesMutex);
    auto it = playerStates.find(guid);
    return it != playerStates.end() && it->second->unlocked.contains(id);
}

uint32 Transmog::GetChosenBackpack(ObjectGuid guid) const
{
    std::shared_lock<std::shared_mutex> lock(playerStatesMutex);
    auto it = playerStates.find(guid);
    return it == playerStates.end() ? 0 : it->second->chosen;
}

bool Transmog::UnlockBackpack(Player* player, uint32 id, bool announce)
{
    BackpackEntry const* entry = GetBackpack(id);
    if (!entry)
        return false;

    ObjectGuid guid = player->GetGUID();
    {
        std::unique_lock<std::shared_mutex> lock(playerStatesMutex);
        auto it = playerStates.find(guid);
        if (it == playerStates.end() || !it->second->unlocked.insert(id).second)
            return false;
    }

    CharacterDatabase.Execute("REPLACE INTO mod_transmog_plus_backpack_unlocks (Owner, BackpackId) VALUES ({}, {})", guid.GetCounter(), id);

    if (announce)
    {
        ChatHandler(player->GetSession()).PSendSysMessage("|cffff80ff[{}]|r {}", entry->name, Tstr(player->GetSession(), LANG_TRANSMOG_BACKPACK_ADDED));
        TransmogAddon::SendBackpackUnlocked(player, id);
    }
    return true;
}

// The highest individual progression phase this character has cleared.
uint8 Transmog::GetProgressionPhase(Player const* player) const
{
    uint8 phase = 0;
    for (uint8 n = 1; n <= MAX_PHASE; ++n)
        if (player->GetQuestRewardStatus(BackpackPhaseQuestBase + n))
            phase = n;
    return phase;
}

void Transmog::SyncPhaseUnlocks(Player* player, bool announce)
{
    uint8 phase = GetProgressionPhase(player);
    if (!phase)
        return;

    for (BackpackEntry const& entry : backpacks)
        if (entry.unlockPhase && entry.unlockPhase <= phase)
            UnlockBackpack(player, entry.id, announce);
}

TransmogApplyResult Transmog::ApplyBackpack(Player* player, uint32 id)
{
    ObjectGuid guid = player->GetGUID();
    if (id && (!GetBackpack(id) || !IsBackpackUnlocked(guid, id)))
        return TransmogApplyResult::InvalidAppearance;

    {
        std::unique_lock<std::shared_mutex> lock(playerStatesMutex);
        auto it = playerStates.find(guid);
        if (it == playerStates.end())
            return TransmogApplyResult::InvalidAppearance;
        if (it->second->chosen == id)
            return TransmogApplyResult::AlreadyApplied;
        it->second->chosen = id;
    }

    if (id)
        CharacterDatabase.Execute("REPLACE INTO mod_transmog_plus_backpack_choice (Owner, BackpackId) VALUES ({}, {})", guid.GetCounter(), id);
    else
        CharacterDatabase.Execute("DELETE FROM mod_transmog_plus_backpack_choice WHERE Owner = {}", guid.GetCounter());

    ShowBackpack(player);
    return TransmogApplyResult::Success;
}

// Backpacks stay off while dead and in forms that swap the model (druid forms, Ghost Wolf,
// Metamorphosis), whose models have no sensible back attachment. Warrior stances, Stealth and
// Shadowform are shapeshift forms too, but keep the character's own model.
bool Transmog::CanShowBackpack(Player const* player) const
{
    if (!player->IsAlive())
        return false;

    ShapeshiftForm form = player->GetShapeshiftForm();
    if (form == FORM_NONE)
        return true;

    SpellShapeshiftFormEntry const* entry = sSpellShapeshiftFormStore.LookupEntry(form);
    return entry && !entry->modelID_A && !entry->modelID_H;
}

// Puts the backpack aura in line with the choice, then refreshes the cloak slot so it hides or
// comes back.
void Transmog::ShowBackpack(Player* player)
{
    uint32 wanted = 0;
    if (BackpacksEnable && CanShowBackpack(player))
        if (BackpackEntry const* entry = GetBackpack(GetChosenBackpack(player->GetGUID())))
            wanted = entry->spellId;

    bool changed = false;
    for (uint32 spellId : backpackSpells)
    {
        if (spellId != wanted && player->HasAura(spellId))
        {
            player->RemoveAurasDueToSpell(spellId);
            changed = true;
        }
    }
    if (wanted && !player->HasAura(wanted))
    {
        player->AddAura(wanted, player);
        changed = true;
    }

    // Refresh the cloak whenever what it shows disagrees with the backpack, not only after this
    // function changed the aura: death, a saved aura from an older build, or anything else that
    // adds or removes the aura behind our back. A cloak hidden by us shows entry 0; transmog's own
    // "Hidden Back" uses HIDDEN_ITEM_ID.
    if (player->GetItemByPos(INVENTORY_SLOT_BAG_0, EQUIPMENT_SLOT_BACK))
    {
        bool cloakHidden = player->GetUInt32Value(GetVisibleItemIndex(EQUIPMENT_SLOT_BACK)) == 0;
        if (changed || cloakHidden != (BackpacksHideCloak && IsBackpackShown(player)))
            RefreshSlot(player, EQUIPMENT_SLOT_BACK);
    }
}

bool Transmog::IsBackpackShown(Player const* player) const
{
    if (!BackpacksEnable || backpackSpells.empty())
        return false;

    BackpackEntry const* entry = GetBackpack(GetChosenBackpack(player->GetGUID()));
    return entry && player->HasAura(entry->spellId);
}

void Transmog::MarkBackpackDirty(ObjectGuid guid)
{
    std::shared_lock<std::shared_mutex> lock(playerStatesMutex);
    if (auto it = playerStates.find(guid); it != playerStates.end())
        it->second->dirty = true;
}

void Transmog::UpdateBackpack(Player* player, uint32 diff)
{
    // Runs for every player on the map update threads, under the shared lock only: each
    // player's timer is touched by its own map thread, and the flags are atomic.
    {
        std::shared_lock<std::shared_mutex> lock(playerStatesMutex);
        auto it = playerStates.find(player->GetGUID());
        if (it == playerStates.end())
            return;

        BackpackPlayerState& state = *it->second;
        uint32 elapsed = state.timer.fetch_add(diff) + diff;
        if (!state.dirty.load() && elapsed < RECONCILE_MS)
            return;
        state.timer = 0;
        state.dirty = false;
    }
    ShowBackpack(player);
}

// The introduction letter: sent once per character, with the item that unlocks the first
// backpack.
void Transmog::SendBackpackIntroMail(Player* player)
{
    if (!BackpackMailEnable || !BackpackMailItem)
        return;

    ObjectGuid::LowType low = player->GetGUID().GetCounter();
    if (CharacterDatabase.Query("SELECT 1 FROM mod_transmog_plus_backpack_mail WHERE Owner = {}", low))
        return;

    if (!sObjectMgr->GetItemTemplate(BackpackMailItem))
    {
        LOG_ERROR("module", "mod-transmog-plus: Transmog.Backpacks.Mail.Item {} doesn't exist, no letter sent", BackpackMailItem);
        return;
    }

    Item* item = Item::CreateItem(BackpackMailItem, 1, player);
    if (!item)
        return;

    MailDraft draft(BackpackMailSubject, BackpackMailBody);
    CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
    item->SaveToDB(trans); // must be in the DB before the mail references it
    draft.AddItem(item);
    MailSender sender(MAIL_CREATURE, BackpackMailSender, MAIL_STATIONERY_GM);
    draft.SendMailTo(trans, MailReceiver(player, low), sender, MAIL_CHECK_MASK_NONE, 0, MAIL_EXPIRE_DAYS);
    trans->Append("REPLACE INTO mod_transmog_plus_backpack_mail (Owner) VALUES ({})", low);
    CharacterDatabase.CommitTransaction(trans);
}

class TransmogBackpackPlayerScript : public PlayerScript
{
public:
    TransmogBackpackPlayerScript() : PlayerScript("TransmogBackpackPlayerScript", {
        PLAYERHOOK_ON_LOGIN,
        PLAYERHOOK_ON_LOGOUT,
        PLAYERHOOK_ON_DELETE,
        PLAYERHOOK_ON_UPDATE,
        PLAYERHOOK_ON_PLAYER_COMPLETE_QUEST,
        PLAYERHOOK_ON_PLAYER_RESURRECT
    }) { }

    // Bots never pick a backpack, so they skip the queries, the phase sync and the letter.
    static bool Tracked(Player* player)
    {
        return sTransmog->Enable && sTransmog->BackpacksEnable && !Transmog_IsBotSession(player);
    }

    void OnPlayerLogin(Player* player) override
    {
        if (!Tracked(player))
            return;

        sTransmog->LoadPlayerBackpacks(player->GetGUID());
        sTransmog->SyncPhaseUnlocks(player, false);
        sTransmog->SendBackpackIntroMail(player);
        sTransmog->ShowBackpack(player);
        // The slots were filled before this state existed (inventory load, then
        // TransmogPlayerScript's login refresh), so show the cloak the way the backpack wants it.
        sTransmog->RefreshSlot(player, EQUIPMENT_SLOT_BACK);
    }

    void OnPlayerLogout(Player* player) override
    {
        sTransmog->UnloadPlayerBackpacks(player->GetGUID());
    }

    void OnPlayerDelete(ObjectGuid guid, uint32) override
    {
        CharacterDatabase.Execute("DELETE FROM mod_transmog_plus_backpack_unlocks WHERE Owner = {}", guid.GetCounter());
        CharacterDatabase.Execute("DELETE FROM mod_transmog_plus_backpack_choice WHERE Owner = {}", guid.GetCounter());
        CharacterDatabase.Execute("DELETE FROM mod_transmog_plus_backpack_mail WHERE Owner = {}", guid.GetCounter());
    }

    void OnPlayerUpdate(Player* player, uint32 diff) override
    {
        if (sTransmog->Enable && sTransmog->BackpacksEnable && !Transmog_IsBotSession(player))
            sTransmog->UpdateBackpack(player, diff);
    }

    // Individual progression records a cleared phase by rewarding quest base+phase.
    void OnPlayerCompleteQuest(Player* player, Quest const* quest) override
    {
        if (!quest || !Tracked(player))
            return;

        uint32 id = quest->GetQuestId();
        if (id > sTransmog->BackpackPhaseQuestBase && id <= sTransmog->BackpackPhaseQuestBase + MAX_PHASE)
            sTransmog->SyncPhaseUnlocks(player, true);
    }

    void OnPlayerResurrect(Player* player, float, bool&) override
    {
        if (!Transmog_IsBotSession(player))
            sTransmog->MarkBackpackDirty(player->GetGUID());
    }
};

// Shapeshifting happens inside aura handling, so the backpack is only flagged here and the
// next player update adds or removes it.
class TransmogBackpackUnitScript : public UnitScript
{
public:
    TransmogBackpackUnitScript() : UnitScript("TransmogBackpackUnitScript", true, {
        UNITHOOK_ON_UNIT_SET_SHAPESHIFT_FORM
    }) { }

    void OnUnitSetShapeshiftForm(Unit* unit, uint8) override
    {
        // Bots switch forms constantly and never wear backpacks.
        Player* player = unit ? unit->ToPlayer() : nullptr;
        if (player && sTransmog->BackpacksEnable && !Transmog_IsBotSession(player))
            sTransmog->MarkBackpackDirty(player->GetGUID());
    }
};

// The item in the introduction letter: unlocks its backpack and puts it on.
class TransmogBackpackItemScript : public ItemScript
{
public:
    TransmogBackpackItemScript() : ItemScript("transmog_backpack_unlock") { }

    bool OnUse(Player* player, Item* item, SpellCastTargets const&) override
    {
        // Every "handled, nothing cast" return sends an equip error so the client un-greys the item.
        Transmog::BackpackEntry const* entry = sTransmog->GetBackpackByItem(item->GetEntry());
        if (!sTransmog->Enable || !sTransmog->BackpacksEnable || !entry)
        {
            ChatHandler(player->GetSession()).SendSysMessage(Tstr(player->GetSession(), LANG_TRANSMOG_BACKPACK_DISABLED));
            player->SendEquipError(EQUIP_ERR_NONE, item, nullptr);
            return true;
        }

        if (sTransmog->IsBackpackUnlocked(player->GetGUID(), entry->id))
        {
            ChatHandler(player->GetSession()).PSendSysMessage("|cffff80ff[{}]|r {}", entry->name, Tstr(player->GetSession(), LANG_TRANSMOG_BACKPACK_KNOWN));
            player->SendEquipError(EQUIP_ERR_NONE, item, nullptr);
            return true;
        }

        // Fails for characters without backpack state (bots): keep the item then.
        if (!sTransmog->UnlockBackpack(player, entry->id, true))
        {
            ChatHandler(player->GetSession()).SendSysMessage(Tstr(player->GetSession(), LANG_TRANSMOG_BACKPACK_DISABLED));
            player->SendEquipError(EQUIP_ERR_NONE, item, nullptr);
            return true;
        }

        sTransmog->ApplyBackpack(player, entry->id);
        TransmogAddon::SendBackpackStatus(player);
        player->DestroyItemCount(item->GetEntry(), 1, true);
        return true;
    }
};

void AddSC_TransmogBackpacks()
{
    new TransmogBackpackPlayerScript();
    new TransmogBackpackUnitScript();
    new TransmogBackpackItemScript();
}
