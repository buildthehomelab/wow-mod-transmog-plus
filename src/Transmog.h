#ifndef DEF_TRANSMOG_H
#define DEF_TRANSMOG_H

#include "Player.h"
#include "ItemTemplate.h"
#include "Config.h"
#include "ScriptMgr.h"
#include "ObjectGuid.h"
#include "UpdateFields.h"
#include "ObjectMgr.h"
#include "Item.h"
#include "WorldSession.h"
#include "DatabaseEnv.h"
#include "GameEventMgr.h"
#include <array>
#include <set>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <sstream>
#include <shared_mutex>
#include <mutex>

// Reserved entry used to hide an armor-slot appearance without an item template.
constexpr uint32 HIDDEN_ITEM_ID = 999999;
// Illusion sentinel that hides a weapon's enchant glow.
constexpr uint32 HIDDEN_ILLUSION_ID = 999999;
// Account outfits are capped so one account can't grow the table without bound.
constexpr uint32 MAX_OUTFITS_PER_ACCOUNT = 50;
// Maximum appearance entries shown in one gossip page.
constexpr uint8 MAX_ITEMS_PER_PAGE = 20;

// Shared result codes keep gossip and addon failures consistent.
enum class TransmogApplyResult : uint8
{
    Success,
    AlreadyApplied,
    InvalidSlot,
    EmptySlot,
    InvalidAppearance,
    NotEnoughMoney
};

enum MenuId : uint32
{
    MENU_MAIN = 1000,
    MENU_SELECT_SLOT,
    MENU_HIDE_SLOT,
    MENU_REMOVE_SLOT,
    MENU_REMOVE_ALL,
    MENU_APPLY,
    MENU_PAGE
};

enum TransmogString : uint32
{
    LANG_TRANSMOG_OK = 1,
    LANG_TRANSMOG_INVALID_SRC,
    LANG_TRANSMOG_ALL_REMOVED,
    LANG_TRANSMOG_HIDDEN,
    LANG_TRANSMOG_SLOT_REMOVED,
    LANG_TRANSMOG_NO_MONEY,
    LANG_TRANSMOG_REMOVE_ALL,
    LANG_TRANSMOG_REMOVE_ALL_ASK,
    LANG_TRANSMOG_BACK,
    LANG_TRANSMOG_HIDE_SLOT,
    LANG_TRANSMOG_REMOVE_SLOT,
    LANG_TRANSMOG_NEXT_PAGE,
    LANG_TRANSMOG_PREVIOUS_PAGE,
    LANG_TRANSMOG_NO_APPEARANCES,
    LANG_TRANSMOG_APPEARANCE_ADDED,
    LANG_TRANSMOG_FREE,
    LANG_TRANSMOG_EMPTY_SLOT,
    LANG_TRANSMOG_SCAN_ADDED,
    LANG_TRANSMOG_OPEN_ANYWHERE_DISABLED,
    LANG_TRANSMOG_ILLUSION_ADDED,
    LANG_TRANSMOG_BACKPACK_ADDED,
    LANG_TRANSMOG_BACKPACK_KNOWN,
    LANG_TRANSMOG_BACKPACK_DISABLED,
    LANG_TRANSMOG_FORMS_UNLOCKED,
    LANG_TRANSMOG_TOTEMS_UNLOCKED
};

inline std::string const& Tstr(WorldSession* session, uint32 id)
{
    return *session->GetModuleString("mod-transmog-plus", id);
}

class Transmog
{
public:
    static Transmog* instance();

    void LoadConfig();

    bool Enable;
    uint32 PriceCopper;
    std::set<uint32> Allowed;
    std::set<uint32> NotAllowed;

    bool AllowPoor;
    bool AllowCommon;
    bool AllowUncommon;
    bool AllowRare;
    bool AllowEpic;
    bool AllowLegendary;
    bool AllowArtifact;
    bool AllowHeirloom;

    bool AllowMixedArmorTypes;
    bool AllowMixedOffhandArmorTypes;
    bool AllowLowerTiers;
    bool AllowMixedWeaponHandedness;
    bool AllowFishingPoles;
    // 0 = strict, 1 = modern grouped weapons, 2 = unrestricted.
    uint8 AllowMixedWeaponTypes;

    bool IgnoreReqRace;
    bool IgnoreReqClass;
    bool IgnoreReqSkill;
    bool IgnoreReqSpell;
    bool IgnoreReqEvent;
    bool IgnoreReqStats;

    // Extra ways to unlock an appearance besides equipping the item.
    bool CollectOnPickup;
    bool CollectOnDisenchant;
    bool CollectScanOnLogin;
    bool CollectQuestRewards;
    bool CollectAltBots;

    // Let /transmog open the transmog window away from a transmogrifier NPC.
    bool OpenAnywhere;

    // Weapon enchant visuals collected from enchanting and shown through transmog.
    bool IllusionsEnable;

    // Backpacks (TransmogBackpacks.cpp): a model on the back from a hidden aura, per character.
    bool BackpacksEnable;
    bool BackpacksHideCloak;
    uint32 BackpackPhaseQuestBase;
    bool BackpackMailEnable;
    uint32 BackpackMailItem;
    uint32 BackpackMailSender;
    std::string BackpackMailSubject;
    std::string BackpackMailBody;

    struct BackpackEntry
    {
        uint32 id = 0;
        std::string name;
        uint32 spellId = 0;
        uint8 unlockPhase = 0; // individual progression phase that unlocks it; 0 = not by phase
        uint32 unlockItem = 0; // item that unlocks it on use; 0 = none
        std::string model;     // client model path, for the addon's preview
    };
    // Loaded at startup, read-only afterwards.
    std::vector<BackpackEntry> backpacks;
    std::unordered_set<uint32> backpackSpells;

    void LoadBackpacks();
    BackpackEntry const* GetBackpack(uint32 id) const;
    BackpackEntry const* GetBackpackByItem(uint32 itemEntry) const;
    void LoadPlayerBackpacks(ObjectGuid guid);
    void UnloadPlayerBackpacks(ObjectGuid guid);
    bool IsBackpackUnlocked(ObjectGuid guid, uint32 id) const;
    uint32 GetChosenBackpack(ObjectGuid guid) const;
    // Returns true when the backpack is new to the character.
    bool UnlockBackpack(Player* player, uint32 id, bool announce);
    uint8 GetProgressionPhase(Player const* player) const;
    void SyncPhaseUnlocks(Player* player, bool announce);
    // 0 takes the backpack off.
    TransmogApplyResult ApplyBackpack(Player* player, uint32 id);
    bool CanShowBackpack(Player const* player) const;
    void ShowBackpack(Player* player);
    bool IsBackpackShown(Player const* player) const;
    void MarkBackpackDirty(ObjectGuid guid);
    void UpdateBackpack(Player* player, uint32 diff);
    void SendBackpackIntroMail(Player* player);

    // Druid form looks and shaman totem looks (TransmogForms.cpp): retail models from the realm's
    // client patches, one choice per form or totem element, unlocked by individual progression
    // phase. A totem element is a form kind like any other; only how the look goes on differs.
    bool FormsEnable;
    bool TotemsEnable;

    // Stored in mod_transmog_plus_form_choice: add new kinds at the end.
    enum FormKind : uint8
    {
        FORM_KIND_BEAR, FORM_KIND_CAT, FORM_KIND_TRAVEL, FORM_KIND_AQUATIC, FORM_KIND_FLIGHT,
        FORM_KIND_MOONKIN, FORM_KIND_TREE,
        FORM_KIND_TOTEM_FIRE, FORM_KIND_TOTEM_EARTH, FORM_KIND_TOTEM_WATER, FORM_KIND_TOTEM_AIR,
        FORM_KIND_COUNT, FORM_KIND_NONE = FORM_KIND_COUNT
    };
    struct FormEntry
    {
        uint32 displayId = 0;
        FormKind kind = FORM_KIND_NONE;
        std::string name;
        uint8 unlockPhase = 0;      // individual progression phase that unlocks it; 0 = from the start
        uint32 previewCreature = 0; // creature_template entry using the display, for the addon preview
    };
    // Loaded at startup, read-only afterwards.
    std::vector<FormEntry> forms;

    static char const* FormKindName(FormKind kind);
    static FormKind FormKindByName(std::string const& name);
    static FormKind FormKindOf(ShapeshiftForm form);
    static FormKind FormKindOfTotemSlot(uint32 slot);
    // The class that owns a kind: druids the forms, shamans the totems.
    static uint8 FormKindClass(FormKind kind);
    // The player's class has looks to pick, and they're switched on.
    bool HasFormLooks(Player const* player) const;
    void LoadForms();
    FormEntry const* GetForm(uint32 displayId) const;
    void LoadPlayerForms(ObjectGuid guid);
    void UnloadPlayerForms(ObjectGuid guid);
    bool IsFormUnlocked(Player const* player, FormEntry const& entry) const;
    uint32 GetChosenForm(ObjectGuid guid, FormKind kind) const;
    // displayId 0 goes back to the default look.
    TransmogApplyResult ApplyForm(Player* player, FormKind kind, uint32 displayId);
    void ApplyFormLook(Player* player, uint32 displayId);
    void ApplyTotemLook(Unit* totem, uint32 displayId);
    void AnnounceFormUnlocks(Player* player, uint8 phase);

    // Account appearance data is shared while logged-in characters reference it.
    std::unordered_map<uint32, std::unordered_set<uint32>> collectionCache;
    std::unordered_map<uint32, uint32> collectionRefCounts;
    // Looks (item DisplayInfoID) the account has from any source, and its collected illusions.
    // Both live and die with collectionCache, under collectionMutex.
    std::unordered_map<uint32, std::unordered_set<uint32>> displayCache;
    std::unordered_map<uint32, std::unordered_set<uint32>> illusionCache;
    // Every transmogrifiable item per DisplayInfoID, built once at startup; read-only afterwards.
    std::unordered_map<uint32, std::vector<uint32>> displaySources;
    // Illusion per weapon slot (main hand, off hand), under slotMapMutex.
    std::unordered_map<ObjectGuid, std::array<uint32, 2>> illusionMap;
    // Slot state is protected separately because it changes during equipment hooks.
    std::unordered_map<ObjectGuid, std::array<uint32, EQUIPMENT_SLOT_END>> slotMap;
    std::unordered_map<ObjectGuid, uint8> selectionCache;
    mutable std::shared_mutex slotMapMutex;
    mutable std::shared_mutex collectionMutex;

    // Player login and logout hooks own the collection cache lifecycle.
    void LoadCollectionForAccount(uint32 accountId);
    void UnrefCollectionForAccount(uint32 accountId);
    bool AddCollectedAppearance(uint32 accountId, uint32 itemId);
    // Unlock path shared by every trigger. Returns true when the appearance is new to the account.
    // A transaction batches the insert (login scan); announcing also notifies the addon.
    bool CollectAppearance(Player* player, ItemTemplate const* proto, bool announce, CharacterDatabaseTransaction trans = nullptr);
    // True when the account has this look from this or any other item.
    bool IsAppearanceKnown(uint32 accountId, ItemTemplate const* proto) const;
    void BuildAppearanceIndex();
    std::vector<uint32> const* GetDisplaySources(uint32 displayId) const;

    // Illusions: collected per account, applied per weapon slot.
    static bool IsIllusionEnchant(uint32 enchantId);
    static bool IsIllusionSlot(uint8 slot);
    static bool CanHaveIllusion(Item const* item);
    bool CollectIllusion(Player* player, uint32 enchantId, bool announce, CharacterDatabaseTransaction trans = nullptr);
    // Collects the permanent and temporary enchant visuals on a weapon.
    uint32 CollectIllusionsFromItem(Player* player, Item const* item, bool announce, CharacterDatabaseTransaction trans = nullptr);
    uint32 GetSlotIllusion(ObjectGuid guid, uint8 slot) const;
    void SetSlotIllusion(Player* player, uint8 slot, uint32 enchantId);
    TransmogApplyResult ApplyIllusion(Player* player, uint8 slot, uint32 enchantId);
    // The permanent-enchant half of the visible enchant field, with any illusion applied.
    uint16 GetVisiblePermEnchantForSlot(Player const* player, uint8 slot, Item const* item) const;
    // The temporary-enchant half; only "hide enchant" changes it.
    uint16 GetVisibleTempEnchantForSlot(Player const* player, uint8 slot, Item const* item) const;

    uint32 GetAppearanceCost(uint32 fakeEntry) const;
    // Gossip and addon adapters use one server-side mutation path.
    TransmogApplyResult ApplyAppearance(Player* player, uint8 slot, uint32 fakeEntry);

    void LoadPlayerSlots(ObjectGuid guid);
    void UnloadPlayerSlots(ObjectGuid guid);
    void SetSlotAppearance(Player* player, uint8 slot, uint32 fakeEntry);
    uint32 GetSlotAppearance(ObjectGuid guid, uint8 slot) const;
    void ApplySlot(Player* player, uint8 slot, Item* item);
    // Refresh methods synchronize stored state with client-visible item fields.
    void RefreshSlot(Player* player, uint8 slot);
    void RefreshAllSlots(Player* player);
    void ClearAllSlots(Player* player);
    uint32 GetVisibleEntryForSlot(Player const* player, uint8 slot, Item const* item) const;

    uint8 GetSelectedSlot(ObjectGuid guid) const;
    void SetSelectedSlot(ObjectGuid guid, uint8 slot);
    void ClearSelection(ObjectGuid guid);

    static std::string GetSlotName(uint8 slot);
    static std::string GetSlotIcon(uint8 slot, uint32 width, uint32 height, int x, int y);
    static std::string GetItemIcon(uint32 entry, uint32 width, uint32 height, int x, int y);
    static std::string GetItemLink(uint32 entry, WorldSession* session);
    static std::string GetSlotGossipIcon(Player* player, uint8 slot);
    static uint16 GetVisibleItemIndex(uint8 slot);

    // Gossip and addon list responses share the same filtered appearance set.
    static std::vector<ItemTemplate const*> GetValidAppearances(Player* player, ItemTemplate const* targetTemplate);
    // The same set grouped by look (DisplayInfoID). Each group keeps every collected source; the
    // slot's current appearance, if present, leads its group.
    static std::vector<std::vector<ItemTemplate const*>> GetValidAppearanceGroups(Player* player, ItemTemplate const* targetTemplate, uint8 slot);
};

#define sTransmog Transmog::instance()

// False for random bots, and for alt bots unless grouped with their account's real player.
bool TransmogCollect_CanCollect(Player* player);
// True for any session without a socket (random and alt bots).
bool Transmog_IsBotSession(Player* player);

bool TransmogRules_IsArmorSlot(uint8 slot);
bool TransmogRules_IsArmorProficiencySpell(uint32 spellId);
bool TransmogRules_IsAllowed(uint32 entry);
bool TransmogRules_IsValidOffhandArmor(uint32 subClass, uint32 invType);
bool TransmogRules_IsTieredArmorSubclass(uint32 subClass);
bool TransmogRules_TierAvailable(Player const* player, uint32 tier);
bool TransmogRules_IsRangedWeapon(uint32 itemClass, uint32 subClass);
bool TransmogRules_CanNeverTransmog(ItemTemplate const* proto);
bool TransmogRules_IsItemTransmogrifiable(Player const* player, ItemTemplate const* proto);
bool TransmogRules_SuitableForTransmogrification(Player const* player, ItemTemplate const* proto);
bool TransmogRules_CanTransmogrifyItemWithItem(Player const* player, ItemTemplate const* target, ItemTemplate const* source);

#endif
