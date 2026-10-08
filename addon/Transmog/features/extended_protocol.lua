local Transmog = _G.Transmog

-- Server messages added with outfits, appearance sources and illusions. They are matched by
-- exact prefix before the older substring checks in event_handlers.lua, because outfit and
-- illusion names are free text and could contain words like "Open".

local function startsWith(message, prefix)
    return string.sub(message, 1, string.len(prefix)) == prefix
end

-- Returns true when the message was handled here.
function Transmog:HandleExtendedMessage(message)
    if message == "Outfits:start" then
        self:OnOutfitsStart()
        return true
    end
    if message == "Outfits:end" then
        self.serverSupportsExtended = true
        self:OnOutfitsEnd()
        return true
    end
    if startsWith(message, "Outfit:") then
        local data, name = string.match(message, "^Outfit:([%d,;]*):(.*)$")
        self:OnOutfit(data, name)
        return true
    end
    if startsWith(message, "OutfitRejected:") then
        self:OnOutfitRejected(string.sub(message, 16))
        return true
    end

    if startsWith(message, "MissingLooks:") then
        local seq, total, rest = string.match(message, "^MissingLooks:(%d+):(%d+):(.*)$")
        self:OnMissingLooks(tonumber(seq), tonumber(total), rest)
        return true
    end

    if startsWith(message, "Sources:") then
        local itemID, rest = string.match(message, "^Sources:(%d+):(.*)$")
        self:OnSources(tonumber(itemID), rest)
        return true
    end

    if message == "Illusions:start" then
        self.illusionIds = {}
        return true
    end
    if message == "Illusions:end" then
        self:OnIllusionsLoaded()
        return true
    end
    if startsWith(message, "Illusions:") then
        for id in string.gmatch(string.sub(message, 11), "(%d+)") do
            table.insert(self.illusionIds, tonumber(id))
        end
        return true
    end
    if startsWith(message, "IllusionName:") then
        local id, name = string.match(message, "^IllusionName:(%d+):(.*)$")
        if id then
            self.illusionNames[tonumber(id)] = name
        end
        return true
    end
    if startsWith(message, "IllusionStatus:") then
        self.serverSupportsIllusions = true
        local mainHand, offHand = string.match(message, "^IllusionStatus:(%d+):(%d+)$")
        self:OnIllusionStatus(tonumber(mainHand), tonumber(offHand))
        return true
    end
    if startsWith(message, "ApplyIllusionResult:") then
        local success, slot, enchant = string.match(message, "^ApplyIllusionResult:(%d+):(%d+):(%d+)$")
        self:ApplyIllusionResult(tonumber(success), tonumber(slot), tonumber(enchant))
        return true
    end
    if startsWith(message, "IllusionCollected:") then
        if TransmogFrame:IsVisible() then
            self:aSend("GetIllusions")
        end
        return true
    end

    if message == "Backpacks:start" then
        self:OnBackpacksStart()
        return true
    end
    if message == "Backpacks:end" then
        self:OnBackpacksLoaded()
        return true
    end
    if startsWith(message, "Backpack:") then
        local id, unlocked, phase, byItem, model, name = string.match(message, "^Backpack:(%d+):(%d):(%d+):(%d):([^:]*):(.*)$")
        if id then
            self:OnBackpack(tonumber(id), tonumber(unlocked), tonumber(phase), tonumber(byItem), model, name)
        end
        return true
    end
    if startsWith(message, "BackpackStatus:") then
        self:OnBackpackStatus(tonumber(string.sub(message, 16)))
        return true
    end
    if startsWith(message, "ApplyBackpackResult:") then
        local success, id = string.match(message, "^ApplyBackpackResult:(%d+):(%d+)$")
        self:ApplyBackpackResult(tonumber(success), tonumber(id))
        return true
    end
    if startsWith(message, "BackpackUnlocked:") then
        self:OnBackpackUnlocked(tonumber(string.sub(message, 18)))
        return true
    end

    return false
end
