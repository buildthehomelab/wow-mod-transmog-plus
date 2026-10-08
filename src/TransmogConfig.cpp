#include "Transmog.h"

namespace
{
    // Config strings can't hold real line breaks, so "\n" stands for one.
    std::string ExpandNewlines(std::string const& text)
    {
        std::string out;
        out.reserve(text.size());
        for (std::size_t i = 0; i < text.size(); ++i)
        {
            if (text[i] == '\\' && i + 1 < text.size() && text[i + 1] == 'n')
            {
                out += '\n';
                ++i;
            }
            else
                out += text[i];
        }
        return out;
    }

    std::set<uint32> ParseEntryList(std::string const& value)
    {
    // Configuration entry lists are whitespace-separated numeric item IDs.
    std::set<uint32> entries;
        std::istringstream stream(value);
        for (uint32 entry; stream >> entry;)
            entries.insert(entry);
        return entries;
    }
}

// Load all policy switches before any player or appearance request is handled.
void Transmog::LoadConfig()
{
    Enable = sConfigMgr->GetOption<bool>("Transmog.Enable", true);
    PriceCopper = sConfigMgr->GetOption<uint32>("Transmog.PriceCopper", 1000);

    Allowed = ParseEntryList(sConfigMgr->GetOption<std::string>("Transmog.Allowed", ""));
    NotAllowed = ParseEntryList(sConfigMgr->GetOption<std::string>("Transmog.NotAllowed", ""));

    AllowPoor = sConfigMgr->GetOption<bool>("Transmog.AllowPoor", true);
    AllowCommon = sConfigMgr->GetOption<bool>("Transmog.AllowCommon", true);
    AllowUncommon = sConfigMgr->GetOption<bool>("Transmog.AllowUncommon", true);
    AllowRare = sConfigMgr->GetOption<bool>("Transmog.AllowRare", true);
    AllowEpic = sConfigMgr->GetOption<bool>("Transmog.AllowEpic", true);
    AllowLegendary = sConfigMgr->GetOption<bool>("Transmog.AllowLegendary", true);
    AllowArtifact = sConfigMgr->GetOption<bool>("Transmog.AllowArtifact", true);
    AllowHeirloom = sConfigMgr->GetOption<bool>("Transmog.AllowHeirloom", true);

    AllowMixedArmorTypes = sConfigMgr->GetOption<bool>("Transmog.AllowMixedArmorTypes", false);
    AllowMixedOffhandArmorTypes = sConfigMgr->GetOption<bool>("Transmog.AllowMixedOffhandArmorTypes", false);
    AllowLowerTiers = sConfigMgr->GetOption<bool>("Transmog.AllowLowerTiers", false);
    AllowMixedWeaponHandedness = sConfigMgr->GetOption<bool>("Transmog.AllowMixedWeaponHandedness", true);
    AllowFishingPoles = sConfigMgr->GetOption<bool>("Transmog.AllowFishingPoles", false);
    AllowMixedWeaponTypes = sConfigMgr->GetOption<uint8>("Transmog.AllowMixedWeaponTypes", 1);

    IgnoreReqRace = sConfigMgr->GetOption<bool>("Transmog.IgnoreReqRace", false);
    IgnoreReqClass = sConfigMgr->GetOption<bool>("Transmog.IgnoreReqClass", false);
    IgnoreReqSkill = sConfigMgr->GetOption<bool>("Transmog.IgnoreReqSkill", false);
    IgnoreReqSpell = sConfigMgr->GetOption<bool>("Transmog.IgnoreReqSpell", false);
    IgnoreReqEvent = sConfigMgr->GetOption<bool>("Transmog.IgnoreReqEvent", false);
    IgnoreReqStats = sConfigMgr->GetOption<bool>("Transmog.IgnoreReqStats", false);

    CollectOnPickup = sConfigMgr->GetOption<bool>("Transmog.Collect.OnPickup", true);
    CollectOnDisenchant = sConfigMgr->GetOption<bool>("Transmog.Collect.OnDisenchant", true);
    CollectScanOnLogin = sConfigMgr->GetOption<bool>("Transmog.Collect.ScanOnLogin", true);
    CollectQuestRewards = sConfigMgr->GetOption<bool>("Transmog.Collect.QuestRewards", true);
    CollectAltBots = sConfigMgr->GetOption<bool>("Transmog.Collect.AltBots", true);

    OpenAnywhere = sConfigMgr->GetOption<bool>("Transmog.OpenAnywhere", true);

    IllusionsEnable = sConfigMgr->GetOption<bool>("Transmog.Illusions.Enable", true);

    BackpacksEnable = sConfigMgr->GetOption<bool>("Transmog.Backpacks.Enable", true);
    FormsEnable = sConfigMgr->GetOption<bool>("Transmog.Forms.Enable", true);
    BackpacksHideCloak = sConfigMgr->GetOption<bool>("Transmog.Backpacks.HideCloak", true);
    BackpackPhaseQuestBase = sConfigMgr->GetOption<uint32>("Transmog.Backpacks.PhaseQuestBase", 66000);
    BackpackMailEnable = sConfigMgr->GetOption<bool>("Transmog.Backpacks.Mail.Enable", true);
    BackpackMailItem = sConfigMgr->GetOption<uint32>("Transmog.Backpacks.Mail.Item", 27621);
    BackpackMailSender = sConfigMgr->GetOption<uint32>("Transmog.Backpacks.Mail.Sender", 9500000);
    BackpackMailSubject = sConfigMgr->GetOption<std::string>("Transmog.Backpacks.Mail.Subject", "Something for your back");
    BackpackMailBody = ExpandNewlines(sConfigMgr->GetOption<std::string>("Transmog.Backpacks.Mail.Body",
        "Adventurers have started carrying their gear on their backs!\n\n"
        "Use the enclosed Halfhill Farmer's Backpack to add it to your collection. It goes on right away.\n\n"
        "Every raid tier you clear unlocks another backpack. Pick between them, or take yours off, "
        "in the Backpacks tab of the Transmogrify window (/transmog). A backpack hides your cloak while you wear it."));
}
