#include "Transmog.h"

class TransmogWorldScript : public WorldScript
{
public:
    TransmogWorldScript() : WorldScript("TransmogWorldScript", {
        WORLDHOOK_ON_STARTUP
    }) { }

// Load configuration and remove slot rows for characters no longer in the database.
    void OnStartup() override
    {
        sTransmog->LoadConfig();
        sTransmog->BuildAppearanceIndex();
        sTransmog->LoadBackpacks();

        CharacterDatabase.Execute("DELETE FROM mod_transmog_plus WHERE NOT EXISTS (SELECT 1 FROM characters WHERE characters.guid = mod_transmog_plus.Owner)");
        CharacterDatabase.Execute("DELETE FROM mod_transmog_plus_illusion_slots WHERE NOT EXISTS (SELECT 1 FROM characters WHERE characters.guid = mod_transmog_plus_illusion_slots.Owner)");
        for (char const* table : { "mod_transmog_plus_backpack_unlocks", "mod_transmog_plus_backpack_choice", "mod_transmog_plus_backpack_mail" })
            CharacterDatabase.Execute("DELETE FROM {0} WHERE NOT EXISTS (SELECT 1 FROM characters WHERE characters.guid = {0}.Owner)", table);
    }
};

void AddSC_TransmogWorldScript()
{
    new TransmogWorldScript();
}
