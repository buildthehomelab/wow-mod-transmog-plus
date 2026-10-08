#include "Transmog.h"
#include "TransmogAddonProtocol.h"
#include "Chat.h"
#include "SpellAuraEffects.h"
#include <array>
#include <memory>

// Druid form looks: retail form models (from the realm's client patch) shown in place of the
// stock bear, cat, travel, aquatic, flight, moonkin and tree models. The druid picks one look per
// form in the Forms tab; looks unlock with individual progression phases, and the stock look is
// always there. The look goes on whenever the core sets the form's stock model.

namespace
{
    struct FormPlayerState
    {
        std::array<uint32, Transmog::FORM_KIND_COUNT> chosen{};
    };

    std::unordered_map<ObjectGuid, std::unique_ptr<FormPlayerState>> formStates;
    std::shared_mutex formStatesMutex;

    constexpr char const* FORM_KIND_NAMES[Transmog::FORM_KIND_COUNT] = {
        "bear", "cat", "travel", "aquatic", "flight", "moonkin", "tree"
    };

    // Individual progression phases are quests base+1 .. base+MAX_PHASE.
    constexpr uint8 MAX_PHASE = 18;

    // Bots never pick a look, so they skip the queries and the hook.
    bool Tracked(Player* player)
    {
        return sTransmog->Enable && sTransmog->FormsEnable && player->getClass() == CLASS_DRUID
            && !Transmog_IsBotSession(player);
    }
}

char const* Transmog::FormKindName(FormKind kind)
{
    return kind < FORM_KIND_COUNT ? FORM_KIND_NAMES[kind] : "";
}

Transmog::FormKind Transmog::FormKindByName(std::string const& name)
{
    for (uint8 i = 0; i < FORM_KIND_COUNT; ++i)
        if (name == FORM_KIND_NAMES[i])
            return FormKind(i);
    return FORM_KIND_NONE;
}

Transmog::FormKind Transmog::FormKindOf(ShapeshiftForm form)
{
    switch (form)
    {
        case FORM_BEAR:
        case FORM_DIREBEAR:    return FORM_KIND_BEAR;
        case FORM_CAT:         return FORM_KIND_CAT;
        case FORM_TRAVEL:      return FORM_KIND_TRAVEL;
        case FORM_AQUA:        return FORM_KIND_AQUATIC;
        case FORM_FLIGHT:
        case FORM_FLIGHT_EPIC: return FORM_KIND_FLIGHT;
        case FORM_MOONKIN:     return FORM_KIND_MOONKIN;
        case FORM_TREE:        return FORM_KIND_TREE;
        default:               return FORM_KIND_NONE;
    }
}

void Transmog::LoadForms()
{
    forms.clear();
    if (!FormsEnable)
        return;

    QueryResult result = WorldDatabase.Query("SELECT DisplayId, Form, Name, UnlockPhase, PreviewCreature FROM mod_transmog_plus_forms ORDER BY SortOrder, DisplayId");
    if (!result)
        return;

    do
    {
        Field* fields = result->Fetch();
        FormEntry entry;
        entry.displayId = fields[0].Get<uint32>();
        entry.kind = FormKindByName(fields[1].Get<std::string>());
        entry.name = fields[2].Get<std::string>();
        entry.unlockPhase = fields[3].Get<uint8>();
        entry.previewCreature = fields[4].Get<uint32>();

        if (!entry.displayId || entry.kind == FORM_KIND_NONE)
        {
            LOG_ERROR("module", "mod-transmog-plus: form look {} skipped, unknown form '{}'", entry.displayId, fields[1].Get<std::string>());
            continue;
        }
        forms.push_back(std::move(entry));
    } while (result->NextRow());

    LOG_INFO("module", "mod-transmog-plus: {} druid form looks loaded", forms.size());
}

Transmog::FormEntry const* Transmog::GetForm(uint32 displayId) const
{
    for (FormEntry const& entry : forms)
        if (entry.displayId == displayId)
            return &entry;
    return nullptr;
}

void Transmog::LoadPlayerForms(ObjectGuid guid)
{
    auto state = std::make_unique<FormPlayerState>();
    if (QueryResult result = CharacterDatabase.Query("SELECT Form, DisplayId FROM mod_transmog_plus_form_choice WHERE Owner = {}", guid.GetCounter()))
    {
        do
        {
            Field* fields = result->Fetch();
            uint8 kind = fields[0].Get<uint8>();
            FormEntry const* entry = GetForm(fields[1].Get<uint32>());
            // A look removed from the table, or moved to another form, falls back to the default.
            if (kind < FORM_KIND_COUNT && entry && entry->kind == kind)
                state->chosen[kind] = entry->displayId;
        } while (result->NextRow());
    }

    std::unique_lock<std::shared_mutex> lock(formStatesMutex);
    formStates[guid] = std::move(state);
}

void Transmog::UnloadPlayerForms(ObjectGuid guid)
{
    std::unique_lock<std::shared_mutex> lock(formStatesMutex);
    formStates.erase(guid);
}

bool Transmog::IsFormUnlocked(Player const* player, FormEntry const& entry) const
{
    return entry.unlockPhase <= GetProgressionPhase(player);
}

uint32 Transmog::GetChosenForm(ObjectGuid guid, FormKind kind) const
{
    if (kind >= FORM_KIND_COUNT)
        return 0;
    std::shared_lock<std::shared_mutex> lock(formStatesMutex);
    auto it = formStates.find(guid);
    return it == formStates.end() ? 0 : it->second->chosen[kind];
}

TransmogApplyResult Transmog::ApplyForm(Player* player, FormKind kind, uint32 displayId)
{
    if (kind >= FORM_KIND_COUNT || !Tracked(player))
        return TransmogApplyResult::InvalidAppearance;

    if (displayId)
    {
        FormEntry const* entry = GetForm(displayId);
        if (!entry || entry->kind != kind || !IsFormUnlocked(player, *entry))
            return TransmogApplyResult::InvalidAppearance;
    }

    ObjectGuid guid = player->GetGUID();
    {
        std::unique_lock<std::shared_mutex> lock(formStatesMutex);
        auto it = formStates.find(guid);
        if (it == formStates.end())
            return TransmogApplyResult::InvalidAppearance;
        if (it->second->chosen[kind] == displayId)
            return TransmogApplyResult::AlreadyApplied;
        it->second->chosen[kind] = displayId;
    }

    if (displayId)
        CharacterDatabase.Execute("REPLACE INTO mod_transmog_plus_form_choice (Owner, Form, DisplayId) VALUES ({}, {}, {})", guid.GetCounter(), uint32(kind), displayId);
    else
        CharacterDatabase.Execute("DELETE FROM mod_transmog_plus_form_choice WHERE Owner = {} AND Form = {}", guid.GetCounter(), uint32(kind));

    // Already in that form: put the new look on now. RestoreDisplayId sets the form's stock
    // model again, which comes back through ApplyFormLook.
    if (player->IsInWorld() && FormKindOf(player->GetShapeshiftForm()) == kind)
        player->RestoreDisplayId();
    return TransmogApplyResult::Success;
}

// Runs from every SetDisplayId. Only the form's stock model is swapped, so a transform (a costume,
// a polymorph that didn't break the form) is left alone.
void Transmog::ApplyFormLook(Player* player, uint32 displayId)
{
    FormKind kind = FormKindOf(player->GetShapeshiftForm());
    if (kind == FORM_KIND_NONE)
        return;

    uint32 look = GetChosenForm(player->GetGUID(), kind);
    if (!look || look == displayId)
        return;

    // A look whose phase the character no longer has (an individual progression reset) stays off.
    FormEntry const* entry = GetForm(look);
    if (!entry || !IsFormUnlocked(player, *entry))
        return;

    Unit::AuraEffectList const& shapeshifts = player->GetAuraEffectsByType(SPELL_AURA_MOD_SHAPESHIFT);
    if (shapeshifts.empty())
        return;
    if (displayId != player->GetModelForForm(player->GetShapeshiftForm(), shapeshifts.front()->GetId()))
        return;

    // Not SetDisplayId: that would come back through this hook.
    player->SetUInt32Value(UNIT_FIELD_DISPLAYID, look);
}

// After a phase is cleared: how many looks it opened up, in chat and to the addon.
void Transmog::AnnounceFormUnlocks(Player* player, uint8 phase)
{
    uint32 count = 0;
    for (FormEntry const& entry : forms)
        if (entry.unlockPhase == phase)
            ++count;
    if (!count)
        return;

    ChatHandler(player->GetSession()).PSendSysMessage("|cffff80ff{}|r {}", count, Tstr(player->GetSession(), LANG_TRANSMOG_FORMS_UNLOCKED));
    TransmogAddon::SendFormsUnlocked(player, phase);
}

class TransmogFormPlayerScript : public PlayerScript
{
public:
    TransmogFormPlayerScript() : PlayerScript("TransmogFormPlayerScript", {
        PLAYERHOOK_ON_LOGIN,
        PLAYERHOOK_ON_LOGOUT,
        PLAYERHOOK_ON_DELETE,
        PLAYERHOOK_ON_PLAYER_COMPLETE_QUEST
    }) { }

    void OnPlayerLogin(Player* player) override
    {
        if (!Tracked(player))
            return;

        sTransmog->LoadPlayerForms(player->GetGUID());
        // Shapeshift auras come back before this state exists: put the look on now.
        if (Transmog::FormKindOf(player->GetShapeshiftForm()) != Transmog::FORM_KIND_NONE)
            player->RestoreDisplayId();
    }

    void OnPlayerLogout(Player* player) override
    {
        sTransmog->UnloadPlayerForms(player->GetGUID());
    }

    void OnPlayerDelete(ObjectGuid guid, uint32) override
    {
        CharacterDatabase.Execute("DELETE FROM mod_transmog_plus_form_choice WHERE Owner = {}", guid.GetCounter());
    }

    // Individual progression records a cleared phase by rewarding quest base+phase.
    void OnPlayerCompleteQuest(Player* player, Quest const* quest) override
    {
        if (!quest || !Tracked(player))
            return;

        uint32 id = quest->GetQuestId();
        uint32 base = sTransmog->BackpackPhaseQuestBase;
        if (id > base && id <= base + MAX_PHASE)
            sTransmog->AnnounceFormUnlocks(player, uint8(id - base));
    }
};

class TransmogFormUnitScript : public UnitScript
{
public:
    TransmogFormUnitScript() : UnitScript("TransmogFormUnitScript", true, {
        UNITHOOK_ON_DISPLAYID_CHANGE
    }) { }

    void OnDisplayIdChange(Unit* unit, uint32 displayId) override
    {
        Player* player = unit ? unit->ToPlayer() : nullptr;
        if (player && Tracked(player))
            sTransmog->ApplyFormLook(player, displayId);
    }
};

void AddSC_TransmogForms()
{
    new TransmogFormPlayerScript();
    new TransmogFormUnitScript();
}
