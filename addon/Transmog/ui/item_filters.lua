local Transmog = _G.Transmog

-- Items tab filters: a name search and a Missing view under the grid, which lists the looks the
-- account hasn't collected yet, and Type and Sort menus above it. Collected looks are filtered
-- here; missing looks come from the server (GetMissing), which knows every item and runs the
-- search, type and sort there too.

Transmog.NO_TRANSMOGS_TEXT = "You have yet to uncover any other appearance for this item. \nAppearances unlock when you loot, buy, craft or equip an item."

local SEARCH_DELAY = 0.4
local MISSING_TIMEOUT = 5

local function lower(text)
    return string.lower(text or "")
end

-- Search text sent to the server: no protocol separators, capped like the server's MAX_QUERY.
local function serverQuery()
    local query = string.gsub(Transmog.searchText, "[:|]", "")
    query = string.gsub(query, "^%s+", "")
    query = string.gsub(query, "%s+$", "")
    return string.sub(query, 1, 40)
end

local function lookMatches(item, needle)
    if needle == "" then
        return true
    end
    -- A look still loading has a placeholder name; only its loaded sources can match.
    if not item.uncached and string.find(lower(item.name), needle, 1, true) then
        return true
    end
    for _, id in ipairs(item.sources or {}) do
        local name = GetItemInfo(id)
        if name and string.find(lower(name), needle, 1, true) then
            return true
        end
    end
    return false
end

local function equippedId(slot)
    local link = GetInventoryItemLink('player', slot)
    return link and Transmog:IDFromLink(link) or 0
end

-- The Type menu: item types by slot group as { class, subclass, menu label, client name }. The
-- client name is what GetItemInfo calls the subclass, which is how a look's type is read back.
local ARMOR_TYPES = {
    { 4, 1, "Cloth" }, { 4, 2, "Leather" }, { 4, 3, "Mail" }, { 4, 4, "Plate" },
    { 4, 0, "Cosmetic", "Miscellaneous" },
}
local WEAPON_TYPES = {
    { 2, 0, "One-Handed Axes" }, { 2, 4, "One-Handed Maces" }, { 2, 7, "One-Handed Swords" },
    { 2, 15, "Daggers" }, { 2, 13, "Fist Weapons" },
    { 2, 1, "Two-Handed Axes" }, { 2, 5, "Two-Handed Maces" }, { 2, 8, "Two-Handed Swords" },
    { 2, 6, "Polearms" }, { 2, 10, "Staves" },
    { 2, 2, "Bows" }, { 2, 3, "Guns" }, { 2, 18, "Crossbows" }, { 2, 19, "Wands" }, { 2, 16, "Thrown" },
    { 4, 6, "Shields" }, { 4, 0, "Held In Off-hand", "Miscellaneous" },
    { 2, 20, "Fishing Poles" }, { 2, 14, "Other Weapons", "Miscellaneous" },
}
-- Back, shirt and tabard looks are all one type, so they get no Type menu.
local SLOT_TYPES = {
    [1] = ARMOR_TYPES, [3] = ARMOR_TYPES, [5] = ARMOR_TYPES, [6] = ARMOR_TYPES, [7] = ARMOR_TYPES,
    [8] = ARMOR_TYPES, [9] = ARMOR_TYPES, [10] = ARMOR_TYPES,
    [16] = WEAPON_TYPES, [17] = WEAPON_TYPES, [18] = WEAPON_TYPES,
}

Transmog.SORTS = {
    { key = "default", text = "Default" },
    { key = "name", text = "Name" },
    { key = "quality", text = "Quality" },
    { key = "level", text = "Item Level" },
}
-- The server's GetMissing sort field for each.
local SERVER_SORT = { default = 0, name = 1, quality = 0, level = 2 }

local function typeKey(class, subclass)
    return class .. ":" .. subclass
end

-- "class:subclass" of a look, or nil while its item is loading or its type is one we don't list.
local typeByName
local function lookType(item)
    local class, subclass = item.t1, item.t2
    if not class then
        class, subclass = select(6, GetItemInfo(item.id))
    end
    if not class then
        return nil
    end
    if not typeByName then
        typeByName = {}
        for _, list in ipairs({ ARMOR_TYPES, WEAPON_TYPES }) do
            for _, t in ipairs(list) do
                typeByName[(t[1] == 2 and "Weapon" or "Armor") .. ":" .. (t[4] or t[3])] = typeKey(t[1], t[2])
            end
        end
    end
    return typeByName[class .. ":" .. (subclass or "")]
end

function Transmog:SlotTypes(slot)
    return SLOT_TYPES[slot]
end

-- The type picked for this slot's group, as its row in the group's list, or nil for every type.
-- Kept per group, so a pick carries from legs to chest but not from legs to a weapon.
function Transmog:SlotTypeFilter(slot)
    local types = SLOT_TYPES[slot]
    local key = types and self.typeFilters[types]
    if not key then
        return nil
    end
    for _, t in ipairs(types) do
        if typeKey(t[1], t[2]) == key then
            return t
        end
    end
end

function Transmog:SetSlotTypeFilter(slot, key)
    local types = SLOT_TYPES[slot]
    if types then
        self.typeFilters[types] = key
    end
end

-- The type line under a look's name in its tooltip.
function Transmog:LookTypeText(item)
    local key = lookType(item)
    local types = SLOT_TYPES[self.currentTransmogSlot or 0]
    for _, t in ipairs(types or {}) do
        if typeKey(t[1], t[2]) == key then
            return t[3]
        end
    end
    return item.t2
end

-- Collected looks per type in the selected slot, for the counts in the Type menu.
function Transmog:CountLookTypes(slot, itemClass)
    local counts = {}
    for _, item in ipairs(self.availableTransmogItems[slot] and self.availableTransmogItems[slot][itemClass] or {}) do
        if not item.reset and item.id ~= self.HIDDEN_ITEM_ID then
            local key = lookType(item)
            if key then
                counts[key] = (counts[key] or 0) + 1
            end
        end
    end
    return counts
end

-- Item level and quality of a look for sorting; looks still loading go last.
local function sortValue(item, sort)
    local name, _, quality, level = GetItemInfo(item.id)
    if not name then
        return nil
    end
    if sort == "name" then
        return name
    elseif sort == "quality" then
        return quality or 0
    end
    return level or 0
end

-- The equipped item's own look and the Hidden look stay first, as in the unsorted list.
local function sortLooks(looks, sort)
    if sort == "default" then
        return
    end
    local pinned, rest, order = {}, {}, {}
    for i, item in ipairs(looks) do
        order[item] = i
        if item.reset or item.id == Transmog.HIDDEN_ITEM_ID then
            table.insert(pinned, item)
        else
            table.insert(rest, item)
        end
    end
    table.sort(rest, function(a, b)
        local va, vb = sortValue(a, sort), sortValue(b, sort)
        if va == nil or vb == nil then
            if (va == nil) ~= (vb == nil) then
                return vb == nil
            end
            return order[a] < order[b]
        end
        if va ~= vb then
            if sort == "name" then
                return va < vb
            end
            return va > vb
        end
        return order[a] < order[b]
    end)
    for i = 1, table.getn(looks) do
        looks[i] = i <= table.getn(pinned) and pinned[i] or rest[i - table.getn(pinned)]
    end
end

-- The tiles to show for the selected slot, and the text for an empty grid (nil hides it).
function Transmog:GetShownLooks(slot, itemClass)
    local shown = {}
    local typeFilter = self:SlotTypeFilter(slot)
    local wantType = typeFilter and typeKey(typeFilter[1], typeFilter[2])
    local typeLabel = typeFilter and typeFilter[3] or nil

    if self.showMissing then
        local key = slot .. ":" .. equippedId(slot) .. ":" .. lower(serverQuery()) .. ":" ..
            (wantType or "") .. ":" .. self.lookSort
        local missing = self.missingLooks
        if not missing or missing.key ~= key then
            self:RequestMissing(slot, key)
            missing = self.missingLooks
        end

        if missing.unsupported then
            return shown, "Listing missing appearances needs a server update on this realm."
        end
        if missing.loading then
            return shown, "Looking for missing appearances..."
        end

        for _, id in ipairs(missing.ids) do
            local name, link, quality, _, _, _, _, _, invType = GetItemInfo(id)
            -- A server without type filtering sends every type; drop the others once they load.
            local itemType = wantType and name and lookType({ id = id })
            if not itemType or itemType == wantType then
                table.insert(shown, {
                    ['id'] = id,
                    ['equip_slot'] = invType,
                    ['name'] = name or ("Item #" .. id),
                    ['link'] = link,
                    ['quality'] = quality or 1,
                    ['sources'] = { id },
                    ['missing'] = true
                })
            end
        end

        if table.getn(shown) == 0 then
            if serverQuery() ~= "" then
                return shown, "No missing appearances match your search."
            end
            if typeLabel then
                return shown, "You have collected every " .. typeLabel .. " appearance this item can use."
            end
            return shown, "You have collected every appearance this item can use."
        end
        return shown, nil
    end

    local needle = lower(self.searchText)
    for _, item in ipairs(self.availableTransmogItems[slot] and self.availableTransmogItems[slot][itemClass] or {}) do
        -- The equipped item's own look and Hidden stay whatever the type, so a look can be undone.
        local typeOk = not wantType or item.reset or item.id == self.HIDDEN_ITEM_ID or lookType(item) == wantType
        if typeOk and lookMatches(item, needle) then
            table.insert(shown, item)
        end
    end
    sortLooks(shown, self.lookSort)

    if self:tableSize(self.transmogDataFromServer[slot][itemClass]) == 0 then
        return shown, self.NO_TRANSMOGS_TEXT
    end
    if table.getn(shown) == 0 then
        return shown, "No collected appearances match your search."
    end
    return shown, nil
end

function Transmog:RequestMissing(slot, key)
    self.missingSeq = self.missingSeq + 1
    self.missingLooks = { key = key, seq = self.missingSeq, ids = {}, total = 0, loading = true }
    local typeFilter = self:SlotTypeFilter(slot)
    local typeArgs = typeFilter and (":" .. typeFilter[1] .. ":" .. typeFilter[2]) or "::"
    self:aSend("GetMissing:" .. self.missingSeq .. ":" .. (slot - 1) .. ":" .. serverQuery() .. typeArgs ..
        ":" .. SERVER_SORT[self.lookSort])
    self.missingTimeout.startTime = GetTime()
    self.missingTimeout:Show()
end

-- "MissingLooks:<seq>:<total>:start", then item ids separated by ':', then "...:end".
function Transmog:OnMissingLooks(seq, total, rest)
    local missing = self.missingLooks
    if not missing or missing.seq ~= seq or not rest then
        return
    end

    if rest == "start" then
        missing.ids = {}
        missing.total = total
        missing.started = true
    elseif rest == "end" then
        missing.loading = false
        self:RefreshItemsView()
    else
        for id in string.gmatch(rest, "(%d+)") do
            table.insert(missing.ids, tonumber(id))
        end
    end
end

-- Re-renders the Items grid when it is the view on screen.
function Transmog:RefreshItemsView()
    if TransmogFrame:IsVisible() and self.tab == 'items' and self.currentTransmogSlot and self.currentTransmogItemClass then
        self:renderAvailableTransmogs(self.currentTransmogSlot, self.currentTransmogItemClass)
    end
end

-- A server without GetMissing never answers; say so instead of loading forever.
Transmog.missingTimeout = CreateFrame("Frame")
Transmog.missingTimeout:Hide()
Transmog.missingTimeout:SetScript("OnUpdate", function()
    if GetTime() - this.startTime < MISSING_TIMEOUT then
        return
    end
    this:Hide()
    local missing = Transmog.missingLooks
    if missing and missing.loading and not missing.started then
        missing.unsupported = true
        Transmog:RefreshItemsView()
    end
end)

-- Re-renders once the page's uncached missing items arrive, so their models can load.
Transmog.missingCacheWait = CreateFrame("Frame")
Transmog.missingCacheWait:Hide()
function Transmog.missingCacheWait:Start()
    self.startTime = GetTime()
    self.page = Transmog.currentPage
    self:Show()
end
Transmog.missingCacheWait:SetScript("OnUpdate", function()
    if not Transmog.showMissing or Transmog.currentPage ~= this.page then
        this:Hide()
        return
    end
    local waited = GetTime() - this.startTime
    if waited < 0.2 then
        return
    end
    local ready = true
    for _, look in ipairs(Transmog.ItemButtons) do
        if look:IsShown() and look.id and look.id ~= Transmog.HIDDEN_ITEM_ID and not GetItemInfo(look.id) then
            ready = false
        end
    end
    if ready or waited > 3 then
        this:Hide()
        Transmog:RefreshItemsView()
    end
end)

-- Dims a tile and labels it when its look isn't collected.
function Transmog:SetMissingShade(index, missing)
    local look = self.ItemButtons[index]
    if not look.missingShade then
        if not missing then
            return
        end
        local model = getglobal('TransmogLook' .. index .. 'ItemModel')
        local shade = CreateFrame("Frame", nil, look)
        shade:SetAllPoints(model)
        shade:SetFrameLevel(model:GetFrameLevel() + 2)
        local tint = shade:CreateTexture(nil, "OVERLAY")
        tint:SetAllPoints(shade)
        tint:SetTexture(0, 0, 0, 0.35)
        local label = shade:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("BOTTOM", shade, "BOTTOM", 0, 8)
        label:SetText("Not collected")
        look.missingShade = shade
    end
    if missing then
        look.missingShade:Show()
    else
        look.missingShade:Hide()
    end
end

-- A missing look can't be applied; clicking one only tries it on the big model.
function Transmog:PreviewMissing(itemId)
    self:RefreshPreviewModel()
    TransmogFramePlayerModel:TryOn(itemId)
    for itemIndex, data in ipairs(self.ItemButtons) do
        self:SetTileLook(getglobal('TransmogLook' .. itemIndex .. 'Button'), data.id == itemId)
    end
end

-- Shift-click puts the item link in chat, so a look can be looked up or shared.
function Transmog:LinkLook(itemId)
    if itemId == self.HIDDEN_ITEM_ID then
        return false
    end
    local _, link = GetItemInfo(itemId)
    if link then
        ChatEdit_InsertLink(link)
    end
    -- An item still loading has no link yet; the click is still a link click, not a try-on.
    return true
end

function TransmogFilters_OnSearchChanged(editBox)
    local text = editBox:GetText() or ""
    if text == Transmog.searchText then
        return
    end
    Transmog.searchText = text
    if text == "" and not editBox:HasFocus() then
        TransmogFrameFiltersSearchHint:Show()
    else
        TransmogFrameFiltersSearchHint:Hide()
    end

    Transmog.currentPage = 1
    -- Missing searches go to the server, so wait for a pause in typing.
    if Transmog.showMissing then
        Transmog.searchDelay.startTime = GetTime()
        Transmog.searchDelay:Show()
    else
        Transmog:RefreshItemsView()
    end
end

Transmog.searchDelay = CreateFrame("Frame")
Transmog.searchDelay:Hide()
Transmog.searchDelay:SetScript("OnUpdate", function()
    if GetTime() - this.startTime >= SEARCH_DELAY then
        this:Hide()
        Transmog:RefreshItemsView()
    end
end)

function TransmogFilters_OnMissingClick(checkButton)
    Transmog.showMissing = checkButton:GetChecked() and true or false
    PlaySound(Transmog.showMissing and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
    Transmog.currentPage = 1
    if Transmog.currentTransmogSlot and Transmog.tab == 'items' then
        -- Reselecting the slot also clears a preview left by clicking a missing look.
        selectTransmogSlot(Transmog.currentTransmogSlot, Transmog.currentTransmogSlotName)
    end
end

-- Closing the window starts the next visit unfiltered.
function Transmog:ResetItemFilters()
    self.showMissing = false
    self.missingLooks = nil
    self.searchDelay:Hide()
    TransmogFrameFiltersMissing:SetChecked(false)
    TransmogFrameFiltersSearch:SetText("")
    TransmogFrameFiltersSearch:ClearFocus()
    self.searchText = ""
    TransmogFrameFiltersSearchHint:Show()
end

-- Type and Sort buttons above the grid; their menus share one dropdown frame.
local filterMenu
local function openMenu(button, entries)
    if not filterMenu then
        filterMenu = CreateFrame("Frame", "TransmogFilterMenu", UIParent, "UIDropDownMenuTemplate")
    end
    EasyMenu(entries, filterMenu, button, 0, 0, "MENU")
end

local function filtersChanged()
    Transmog.currentPage = 1
    Transmog:UpdateFilterButtons()
    if Transmog.currentTransmogSlot and Transmog.tab == 'items' then
        -- Reselecting the slot also clears a preview left by clicking a missing look.
        selectTransmogSlot(Transmog.currentTransmogSlot, Transmog.currentTransmogSlotName)
    end
end

function Transmog:UpdateFilterButtons()
    local slot = self.currentTransmogSlot
    local types = slot and SLOT_TYPES[slot]
    if types then
        local picked = self:SlotTypeFilter(slot)
        TransmogFrameFiltersType:SetText(picked and picked[3] or "All Types")
        TransmogFrameFiltersType:Show()
    else
        TransmogFrameFiltersType:Hide()
    end
    for _, sort in ipairs(self.SORTS) do
        if sort.key == self.lookSort then
            TransmogFrameFiltersSort:SetText("Sort: " .. sort.text)
        end
    end
end

function TransmogFilters_OnTypeClick(button)
    local slot = Transmog.currentTransmogSlot
    local types = slot and SLOT_TYPES[slot]
    if not types then
        return
    end
    local picked = Transmog:SlotTypeFilter(slot)
    local pickedKey = picked and typeKey(picked[1], picked[2])
    -- Missing looks come from the server, so every type is offered; collected ones only list
    -- the types this slot actually has.
    local counts = not Transmog.showMissing and Transmog:CountLookTypes(slot, Transmog.currentTransmogItemClass)
    local entries = {
        { text = "Item Type", isTitle = true, notCheckable = true },
        { text = "All Types", checked = pickedKey == nil, func = function()
            Transmog:SetSlotTypeFilter(slot, nil)
            filtersChanged()
        end },
    }
    for _, t in ipairs(types) do
        local key = typeKey(t[1], t[2])
        local count = counts and counts[key] or 0
        if not counts or count > 0 or key == pickedKey then
            table.insert(entries, {
                text = counts and (t[3] .. " |cff808080(" .. count .. ")|r") or t[3],
                checked = key == pickedKey,
                func = function()
                    Transmog:SetSlotTypeFilter(slot, key)
                    filtersChanged()
                end,
            })
        end
    end
    PlaySound("igMainMenuOptionCheckBoxOn")
    openMenu(button, entries)
end

function TransmogFilters_OnSortClick(button)
    local entries = { { text = "Sort By", isTitle = true, notCheckable = true } }
    for _, sort in ipairs(Transmog.SORTS) do
        table.insert(entries, {
            text = sort.text,
            checked = Transmog.lookSort == sort.key,
            func = function()
                Transmog.lookSort = sort.key
                filtersChanged()
            end,
        })
    end
    PlaySound("igMainMenuOptionCheckBoxOn")
    openMenu(button, entries)
end
