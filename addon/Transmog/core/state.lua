local Transmog = _G.Transmog

transmogOutfits = {}
Transmog.availableTransmogItems = {}
Transmog.ItemButtons = {}
Transmog.currentTransmogSlotName = nil
Transmog.currentTransmogSlot = nil
Transmog.currentTransmogItemClass = nil
Transmog.currentPage = 1
Transmog.totalPages = 1
Transmog.ipp = 15
Transmog.numTransmogs = {}
Transmog.transmogDataFromServer = {}
Transmog.transmogStatusFromServer = {}
Transmog.transmogStatusToServer = {}
Transmog.tab = ''
Transmog.equippedItems = {}
Transmog.currentOutfit = nil
Transmog.equippedTransmogs = {}

Transmog.localCache = {}

-- Looks per slot and item class: each entry lists the collected items sharing one model.
Transmog.appearanceGroups = {}
-- Every item sharing a look, collected or not, fetched on hover (see GetSources).
Transmog.sourcesByItem = {}

-- Items tab filters (ui/item_filters.lua). missingLooks holds the server's answer for one
-- slot, equipped item and search; missingSeq tells a current answer from a stale one.
Transmog.searchText = ""
Transmog.showMissing = false
Transmog.missingLooks = nil
Transmog.missingSeq = 0

-- Set once the server answers the newer requests, so an older server module never leaves the
-- addon waiting (sources, outfits) or stuck with an Apply it will never confirm (illusions).
Transmog.serverSupportsExtended = false
Transmog.serverSupportsIllusions = false

-- Illusions (weapon enchant visuals), keyed by 1-based slot like the item status tables.
Transmog.illusionIds = {}
Transmog.illusionNames = {}
Transmog.illusionStatusFromServer = { [16] = 0, [17] = 0 }
Transmog.illusionStatusToServer = { [16] = 0, [17] = 0 }

-- Sets tab state
Transmog.collectedItems = {}
Transmog.selectedSet = nil
Transmog.selectedSetCategory = "ALL"
Transmog.selectedSetClass = nil
Transmog.filteredSets = {}
