local Transmog = _G.Transmog

-- The client answers GetInventoryItemTexture and GetInventoryItemQuality for your own gear from
-- the visible item fields, which the server fills with the transmog appearance. The character
-- pane then showed the appearance's icon, and a hidden slot (no such item) looked empty.
-- The item link still names the real item, so both answer from it for your equipped slots.
-- DragonUI's quality borders and other addons read the same functions and follow along.

local GetVisibleTexture = GetInventoryItemTexture
local GetVisibleQuality = GetInventoryItemQuality

local function realItemInfo(unit, slot)
    if not unit or type(slot) ~= "number" or slot < 1 or slot > 19 or not UnitIsUnit(unit, "player") then
        return nil
    end

    local link = GetInventoryItemLink(unit, slot)
    if not link then
        return nil
    end

    local _, _, quality, _, _, _, _, _, _, texture = GetItemInfo(link)
    return texture, quality
end

function GetInventoryItemTexture(unit, slot)
    local texture = realItemInfo(unit, slot)
    if texture then
        return texture
    end
    return GetVisibleTexture(unit, slot)
end

function GetInventoryItemQuality(unit, slot)
    local _, quality = realItemInfo(unit, slot)
    if quality then
        return quality
    end
    return GetVisibleQuality(unit, slot)
end
