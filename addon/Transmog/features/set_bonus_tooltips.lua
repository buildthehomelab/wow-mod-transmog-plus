local Transmog = _G.Transmog

-- The client counts a tooltip's set pieces from the player's visible item fields, which the
-- server fills with transmog appearances. A transmogged set piece then counts as missing and
-- its bonuses show grey, although the server still applies them from the real items.
-- This recounts the pieces from the real equipment and recolors the set lines.

local PIECE_ON = { 1, 1, 0.6 }
local PIECE_OFF = { 0.5, 0.5, 0.5 }
local BONUS_OFF = { 0.5, 0.5, 0.5 }

-- Turns a format string such as ITEM_SET_NAME ("%s (%d/%d)") into an anchored Lua pattern.
local function formatToPattern(fmt)
    local pattern = fmt:gsub("%%%d%$([sd])", "%%%1")
    pattern = pattern:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
    pattern = pattern:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. pattern .. "$"
end

local SET_NAME_PATTERN = formatToPattern(ITEM_SET_NAME)
local BONUS_ON_PATTERN = formatToPattern(ITEM_SET_BONUS)
local BONUS_OFF_PATTERN = formatToPattern(ITEM_SET_BONUS_GRAY)

local function plainText(fontString)
    local text = fontString and fontString:GetText()
    if not text then
        return ""
    end
    return strtrim((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
end

local function equippedNames()
    local names = {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        local name = link and link:match("|h%[(.-)%]|h")
        if name then
            names[name] = true
        end
    end
    return names
end

-- An active bonus line drops its "(N)" piece count, so the counts seen on grey lines are kept
-- per set to tell later when an active line has to turn grey.
local function bonusTiers(setName)
    transmogSetBonusTiers = transmogSetBonusTiers or {}
    transmogSetBonusTiers[setName] = transmogSetBonusTiers[setName] or {}
    return transmogSetBonusTiers[setName]
end

-- Rewrites the bonus lines below a set's piece list; returns the first line after them.
local function fixBonusLines(tooltipName, first, numLines, setName, count)
    local tiers = bonusTiers(setName)
    local seenBonus = false

    for i = first, numLines do
        local line = _G[tooltipName .. "TextLeft" .. i]
        local text = plainText(line)
        local tier, bonus = text:match(BONUS_OFF_PATTERN)
        if tier then
            tier = tonumber(tier)
            tiers[bonus] = tier
        else
            bonus = text:match(BONUS_ON_PATTERN)
            tier = bonus and tiers[bonus]
        end

        if bonus then
            seenBonus = true
            -- An active line whose count was never seen keeps the client's verdict.
            if tier and count >= tier then
                line:SetText(format(ITEM_SET_BONUS, bonus))
                line:SetTextColor(GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
            elseif tier then
                line:SetText(format(ITEM_SET_BONUS_GRAY, tier, bonus))
                line:SetTextColor(unpack(BONUS_OFF))
            end
        elseif text ~= "" or seenBonus then
            return i
        end
    end

    return numLines + 1
end

local function fixSetLines(tooltip)
    -- Inspect tooltips count the inspected player's gear, not ours.
    local owner = tooltip:GetOwner()
    local ownerName = owner and owner.GetName and owner:GetName()
    if ownerName and ownerName:find("^Inspect") then
        return
    end

    local tooltipName = tooltip:GetName()
    local numLines = tooltip:NumLines()
    local equipped
    local changed = false
    local i = 2

    while i <= numLines do
        local header = _G[tooltipName .. "TextLeft" .. i]
        local setName, _, total = plainText(header):match(SET_NAME_PATTERN)
        total = tonumber(total)

        if setName and total and total > 0 and i + total <= numLines then
            equipped = equipped or equippedNames()

            local count = 0
            for k = 1, total do
                local pieceLine = _G[tooltipName .. "TextLeft" .. (i + k)]
                if equipped[plainText(pieceLine)] then
                    count = count + 1
                    pieceLine:SetTextColor(unpack(PIECE_ON))
                else
                    pieceLine:SetTextColor(unpack(PIECE_OFF))
                end
            end

            header:SetText(format(ITEM_SET_NAME, setName, count, total))
            i = fixBonusLines(tooltipName, i + total + 1, numLines, setName, count)
            changed = true
        else
            i = i + 1
        end
    end

    if changed then
        tooltip:Show()
    end
end

for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2, ShoppingTooltip3 }) do
    if tooltip then
        tooltip:HookScript("OnTooltipSetItem", fixSetLines)
    end
end
