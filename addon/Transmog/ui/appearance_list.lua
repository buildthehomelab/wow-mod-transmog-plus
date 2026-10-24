local Transmog = _G.Transmog
local TransmogFrame_Find = string.find
local TransmogFrame_ToNumber = tonumber

-- Updates the collection progress bar with collected count.
function Transmog:setProgressBar(collected, possible)
	TransmogFrameCollectedCollectedStatus:SetText("Collected: " .. collected)

	local fillBarWidth = 0;
    TransmogFrameCollectedFillBar:SetPoint("TOPRIGHT", TransmogFrameCollected, "TOPLEFT", fillBarWidth, 0);
    TransmogFrameCollectedFillBar:Show();

    TransmogFrameCollected:SetStatusBarColor(0.0, 0.0, 0.0, 0.5);
    TransmogFrameCollectedBackground:SetVertexColor(0.0, 0.0, 0.0, 0.5);
    TransmogFrameCollectedFillBar:SetVertexColor(0.0, 1.0, 0.0, 0.5);

    TransmogFrameCollected:Show()
end

-- Looks whose lead item the client hasn't cached yet, by slot then item class. Their tiles show a
-- placeholder until the item arrives; the frame below polls for that, as 3.3.5 has no event for it.
Transmog.uncachedLooks = {}

local CACHE_POLL = 0.2
-- Stop polling when nothing has arrived for this long; reopening the window asks again.
local CACHE_GIVE_UP = 30

Transmog.availableTransmogsCacheDelay = CreateFrame("Frame")
Transmog.availableTransmogsCacheDelay:Hide()
Transmog.availableTransmogsCacheDelay.lastCheck = 0
Transmog.availableTransmogsCacheDelay.lastProgress = 0

Transmog.availableTransmogsCacheDelay:SetScript("OnUpdate", function()
    local now = GetTime()
    if now - this.lastCheck < CACHE_POLL then
        return
    end
    this.lastCheck = now

    local arrived = {}
    local waiting = false
    for slot, classes in pairs(Transmog.uncachedLooks) do
        for itemClass, pending in pairs(classes) do
            local groups = Transmog.appearanceGroups[slot] and Transmog.appearanceGroups[slot][itemClass]
            if groups ~= pending.groups then
                -- The server is sending this list again; its "end" builds the new one.
                classes[itemClass] = nil
            else
                waiting = true
                for _, itemID in ipairs(pending.ids) do
                    if GetItemInfo(itemID) then
                        table.insert(arrived, { slot, itemClass })
                        break
                    end
                end
            end
        end
    end

    local frame = Transmog.availableTransmogsCacheDelay
    if table.getn(arrived) > 0 then
        frame.lastProgress = now
    elseif not waiting or now - frame.lastProgress > CACHE_GIVE_UP then
        Transmog.uncachedLooks = {}
        frame:Hide()
    end

    local current = false
    for _, list in ipairs(arrived) do
        twfdebug("delay cache: " .. list[1])
        Transmog:prepareAvailableTransmogs(list[1], list[2])
        if list[1] == Transmog.currentTransmogSlot and list[2] == Transmog.currentTransmogItemClass then
            current = true
        end
    end
    if current and Transmog:ShownLooksChanged() then
        Transmog:RefreshItemsView()
    end
end)

-- Whether a rebuild of the list on screen changed what the grid shows: a placeholder tile's item
-- arrived, or a search now matches more looks. Arrivals on other pages need no redraw.
function Transmog:ShownLooksChanged()
    if self.showMissing or self.tab ~= 'items' or not TransmogFrame:IsVisible() then
        return false
    end
    for _, look in ipairs(self.ItemButtons) do
        if look:IsShown() and look.uncached and GetItemInfo(look.id) then
            return true
        end
    end
    local shown = self:GetShownLooks(self.currentTransmogSlot, self.currentTransmogItemClass)
    return table.getn(shown) ~= self.shownLookCount
end

-- Processes available transmog data for a slot and item class, building the display list.
function Transmog:prepareAvailableTransmogs(slot, itemClass)

	twfdebug("prepareAvailableTransmogs start slot: " .. slot .. " itemClass: " .. itemClass)

	if not Transmog.availableTransmogItems[slot] then
		Transmog.availableTransmogItems[slot] = {}
	end

    self.availableTransmogItems[slot][itemClass] = {}

    local eqItemLink = nil
    local inventoryItemLink = GetInventoryItemLink('player', slot)
    if inventoryItemLink then
        local _, _, eqItemLink2 = TransmogFrame_Find(inventoryItemLink, "(item:%d+:%d+:%d+:%d+)");
        eqItemLink = eqItemLink2;
    end
    local eqItemID = eqItemLink and self:IDFromLink(eqItemLink)

    -- One tile per look; its lead item is what gets applied, the rest are extra sources.
    -- A look the client hasn't cached keeps its place in the list: stopping at it used to hide
    -- every look after it.
    local groups = self.appearanceGroups[slot] and self.appearanceGroups[slot][itemClass] or {}
    local uncached = {}
    for i, group in ipairs(groups) do
        local itemID = group[1]
        local name, link, quality, level, min_level, class, subclass, _, inv_type, tex = GetItemInfo(itemID)

        if not name then
            table.insert(uncached, itemID)
        end

        table.insert(self.availableTransmogItems[slot][itemClass], {
            ['id'] = itemID,
            ['reset'] = itemID == eqItemID,
            ['uncached'] = not name,
            ['name'] = name or ("Item #" .. itemID),
            ['link'] = link,
            ['quality'] = quality or 1,
            ['t1'] = class,
            ['t2'] = subclass,
            ['equip_slot'] = inv_type,
            ['tex'] = tex,
            ['itemLink'] = eqItemLink,
            ['sources'] = group
        })
    end

    if table.getn(uncached) > 0 then
        if not self.uncachedLooks[slot] then
            self.uncachedLooks[slot] = {}
        end
        self.uncachedLooks[slot][itemClass] = { groups = groups, ids = uncached }
        self.availableTransmogsCacheDelay.lastProgress = GetTime()
        self.availableTransmogsCacheDelay:Show()
    elseif self.uncachedLooks[slot] then
        self.uncachedLooks[slot][itemClass] = nil
    end

    if Transmog.hideableSlots[slot] then
        local slotLabel = string.gsub(Transmog.inventorySlotNames[slot] or "", " Slot", "")
        table.insert(self.availableTransmogItems[slot][itemClass], 1, {
            ['id'] = Transmog.HIDDEN_ITEM_ID,
            ['reset'] = false,
            ['name'] = "Hidden " .. slotLabel,
            ['link'] = nil,
            ['quality'] = 0,
            ['t1'] = nil,
            ['t2'] = nil,
            ['equip_slot'] = nil,
            ['tex'] = nil,
            ['itemLink'] = nil
        })
    end

    -- The server never lists the equipped item's own look (applying it would change nothing),
    -- but like retail it goes first, so the item's look can be picked back after a transmog.
    local equippedLink = GetInventoryItemLink('player', slot)
    local equippedID = equippedLink and self:IDFromLink(equippedLink)
    if equippedID then
        local name, link, quality, _, _, class, subclass, _, inv_type, tex = GetItemInfo(equippedID)
        if name then
            table.insert(self.availableTransmogItems[slot][itemClass], 1, {
                ['id'] = equippedID,
                ['reset'] = true,
                ['name'] = name,
                ['link'] = link,
                ['quality'] = quality,
                ['t1'] = class,
                ['t2'] = subclass,
                ['equip_slot'] = inv_type,
                ['tex'] = tex,
                ['itemLink'] = equippedLink,
                ['sources'] = { equippedID }
            })
        end
    end

	twfdebug("prepareAvailableTransmogs end")
end

-- Renders the grid of transmog item buttons for the currently selected slot.
function Transmog:renderAvailableTransmogs(slot, itemClass)

	twfdebug("renderAvailableTransmogs slot: " .. slot .. " itemClass: " .. itemClass)

	if not self.transmogDataFromServer[slot] then
		return
	end

    self:hideItems(true)
    self:hideItemBorders()
    TransmogFrameFilters:Show()
    self:UpdateFilterButtons()
    TransmogFrameNoTransmogs:Hide()

	local looks = self.appearanceGroups[slot] and self.appearanceGroups[slot][itemClass]
	self:setProgressBar(self:tableSize(looks), self.numTransmogs[slot][itemClass])

    local shown, emptyText = self:GetShownLooks(slot, itemClass)
    local missing = self.showMissing and self.missingLooks
    if missing and not missing.loading and not missing.unsupported then
        local count = table.getn(missing.ids)
        TransmogFrameCollectedCollectedStatus:SetText("Missing: " .. (count < missing.total and (count .. " of " .. missing.total) or count))
    end
    if emptyText then
        TransmogFrameNoTransmogs:SetText(emptyText)
        TransmogFrameNoTransmogs:Show()
    end

    self.shownLookCount = table.getn(shown)
    self.currentPage = math.min(self.currentPage, math.max(1, self:ceil(table.getn(shown) / self.ipp)))

    local index = 0
    local row = 0
    local col = 0
    local itemIndex = 1
    local uncached = false

    for _, item in ipairs(shown) do

        if index >= (self.currentPage - 1) * self.ipp and index < self.currentPage * self.ipp then

            if not self.ItemButtons[itemIndex] then
                self.ItemButtons[itemIndex] = CreateFrame('Frame', 'TransmogLook' .. itemIndex, TransmogFrame, 'TransmogFrameLookTemplate')
            end

            self.ItemButtons[itemIndex]:SetPoint("TOPLEFT", TransmogFrame, "TOPLEFT", 263 + col * 90, -105 - 120 * row)

            self.ItemButtons[itemIndex].name = item.name
            self.ItemButtons[itemIndex].id = item.id
            self.ItemButtons[itemIndex].reset = item.reset
            self.ItemButtons[itemIndex].uncached = item.uncached

            getglobal('TransmogLook' .. itemIndex .. 'Button'):SetID(item.id)
            getglobal('TransmogLook' .. itemIndex .. 'ButtonRevert'):Hide()
            getglobal('TransmogLook' .. itemIndex .. 'ButtonCheck'):Hide()

            local staged = self.transmogStatusToServer[slot] or 0
            if item.id == staged or (item.reset and staged == 0) then
                Transmog:SetTileLook(getglobal('TransmogLook' .. itemIndex .. 'Button'), true)
            else
                Transmog:SetTileLook(getglobal('TransmogLook' .. itemIndex .. 'Button'), false)
            end

            self:SetLookTooltip(getglobal('TransmogLook' .. itemIndex .. 'Button'), item)
            if item.reset and staged ~= 0 then
                getglobal('TransmogLook' .. itemIndex .. 'ButtonRevert'):Show()
            end
            self:SetMissingShade(itemIndex, item.missing)

            self.ItemButtons[itemIndex]:Show()

            local model = getglobal('TransmogLook' .. itemIndex .. 'ItemModel')

            model:SetUnit("player")
            model:SetRotation(0.61);
            local Z, X, Y = model:GetPosition(Z, X, Y)

            if self.race == 'nightelf' then
                Z = Z + 3
            end
            if self.race == 'gnome' then
                Z = Z - 3
                Y = Y + 1.5
            end
            if self.race == 'dwarf' then
                Y = Y + 1
                Z = Z - 1
            end
            if self.race == 'troll' then
                Z = Z + 2
            end
            if self.race == 'goblin' then
                Z = Z - 0.5
            end
            if self.race == 'scourge' then
                Z = Z + 2
            end

            if self.currentTransmogSlot == self.inventorySlots['HeadSlot'] then
                if self.race == 'tauren' then
                    model:SetRotation(0.3);
                    X = X - 0.2
                    Y = Y + 0.2
                end
                if self.race == 'goblin' then
                    Y = Y + 1.5
                end
                if self.race == 'dwarf' then
                    Y = Y + 0.5
                end
                model:SetPosition(Z + 5.8, X, Y - 2.2)
            end

            if self.currentTransmogSlot == self.inventorySlots['ShoulderSlot'] then
                if self.race == 'dwarf' then
                    Y = Y - 0.2
                end
                if self.race == 'goblin' then
                    Y = Y + 1.5
                    Z = Z - 0.5
                end
                if self.race == 'nightelf' then
                    Z = Z - 1
                end
                model:SetPosition(Z + 5.8, X + 0.5, Y - 1.7)
            end

            if self.currentTransmogSlot == self.inventorySlots['BackSlot'] then
                model:SetRotation(3.2);
                model:SetPosition(Z + 3.8, X, Y - 0.7)
            end

            -- Shirts and tabards sit on the torso, so they share the chest framing.
            if self.currentTransmogSlot == self.inventorySlots['ChestSlot'] or
                    self.currentTransmogSlot == self.inventorySlots['ShirtSlot'] or
                    self.currentTransmogSlot == self.inventorySlots['TabardSlot'] then
                if self.race == 'tauren' then
                    model:SetRotation(0.3);
                    X = X - 0.2
                    Y = Y + 0.5
                end
                if self.race == 'goblin' then
                    Y = Y + 1.5
                    Z = Z - 0.5
                end
                model:SetRotation(0.61);
                model:SetPosition(Z + 5.8, X + 0.1, Y - 1.2)
            end

            if self.currentTransmogSlot == self.inventorySlots['WristSlot'] then
                model:SetRotation(1.5);
                if self.race == 'gnome' then
                    Y = Y - 1
                end
                if self.race == 'tauren' then
                    X = X - 0.2
                end
                if self.race == 'dwarf' then
                    X = X - 0.3
                    Y = Y - 0.4
                end
                if self.race == 'troll' then
                    Y = Y + 0.6
                end
                if self.race == 'goblin' then
                    Y = Y + 1.5
                    Z = Z - 0.5
                end
                model:SetPosition(Z + 5.8, X + 0.4, Y - 0.3)
            end

            if self.currentTransmogSlot == self.inventorySlots['HandsSlot'] then
                model:SetRotation(1.5);
                if self.race == 'gnome' then
                    Y = Y - 0.7
                end
                if self.race == 'tauren' then
                    X = X - 0.2
                end
                if self.race == 'dwarf' then
                    Z = Z - 0.2
                    X = X - 0.3
                    Y = Y - 0.1
                end
                if self.race == 'troll' then
                    Y = Y + 0.9
                end
                if self.race == 'goblin' then
                    Y = Y + 1.5
                    Z = Z - 0.5
                end
                model:SetPosition(Z + 5.8, X + 0.4, Y - 0.3)
            end

            if self.currentTransmogSlot == self.inventorySlots['WaistSlot'] then
                model:SetRotation(0.31);
                if self.race == 'gnome' then
                    Y = Y - 0.7
                end
                if self.race == 'tauren' then
                    Z = Z + 1
                    Y = Y + 0.3
                end
                if self.race == 'goblin' then
                    Y = Y + 1.5
                    Z = Z - 0.5
                end
                model:SetPosition(Z + 5.8, X, Y - 0.4)
            end

            if self.currentTransmogSlot == self.inventorySlots['LegsSlot'] then
                model:SetRotation(0.31);
                if self.race == 'gnome' then
                    Z = Z + 2
                    Y = Y - 1.5
                end
                if self.race == 'dwarf' then
                    Y = Y - 0.9
                end
                model:SetPosition(Z + 3.8, X, Y + 0.9)
            end

            if self.currentTransmogSlot == self.inventorySlots['FeetSlot'] then
                model:SetRotation(0.61);
                if self.race == 'gnome' then
                    Z = Z + 2
                    Y = Y - 1.9
                end
                if self.race == 'dwarf' then
                    Y = Y - 0.6
                end
                model:SetPosition(Z + 4.8, X, Y + 1.5)
            end

            if self:IsWeaponSlot(self.currentTransmogSlot) then
                self:FrameWeaponModel(model, item.equip_slot)
            end

            self:ApplyCameraNudge(model, self.currentTransmogSlot)

            model:Undress()

            if item.id ~= Transmog.HIDDEN_ITEM_ID then
                -- Missing looks usually aren't in the client cache yet, and TryOn needs them there.
                if item.missing and not GetItemInfo(item.id) then
                    self:cacheItem(item.id)
                    uncached = true
                end
                model:TryOn(item.id);
            end

            col = col + 1
            if col == 5 then
                row = row + 1
                col = 0
            end

            itemIndex = itemIndex + 1

        end
        index = index + 1
    end

    self.totalPages = math.max(1, self:ceil(table.getn(shown) / self.ipp))

    TransmogFramePageText:SetText("Page " .. self.currentPage .. "/" .. self.totalPages)

    if self.currentPage == 1 then
        TransmogFrameLeftArrow:Disable()
    else
        TransmogFrameLeftArrow:Enable()
    end

    if self.currentPage >= self.totalPages then
        TransmogFrameRightArrow:Disable()
    else
        TransmogFrameRightArrow:Enable()
    end

    if self.totalPages > 1 then
        self:showPagination()
    else
        self:hidePagination()
    end

    if self.currentTransmogSlotName then
        getglobal(self.currentTransmogSlotName .. 'BorderSelected'):Show()
    end

    if uncached then
        self.missingCacheWait:Start()
    end

end

-- Tile tooltips list every item with the tile's look: collected ones first as they arrive with
-- the list, then the full set (collected or not) once the server answers GetSources.
local function sourceLine(itemID, collected)
    local name, _, quality = GetItemInfo(itemID)
    if not name then
        Transmog:cacheItem(itemID)
        name = "Item #" .. itemID
        quality = 1
    end
    if collected then
        local _, _, _, color = GetItemQualityColor(quality or 1)
        return "|cff20ff20+|r " .. color .. name .. "|r"
    end
    return "|cff808080- " .. name .. "|r"
end

function Transmog:ShowLookTooltip(owner, item)
    FashionTooltip:SetOwner(owner, "ANCHOR_RIGHT", -(owner:GetWidth() / 4) + 15, -(owner:GetHeight() / 4) + 20)
    local _, _, _, color = GetItemQualityColor(item.quality or 1)
    FashionTooltip:AddLine(color .. item.name)

    if item.id ~= self.HIDDEN_ITEM_ID then
        local typeText = self:LookTypeText(item)
        if typeText then
            FashionTooltip:AddLine(typeText, 1, 1, 1)
        end
        FashionTooltip:AddLine("Sources:", 1, 0.82, 0)
        local sources = self.sourcesByItem[item.id]
        -- An empty answer (item unknown to the server's look index) keeps the collected list.
        if sources and not sources.loading and table.getn(sources.list) > 0 then
            for _, source in ipairs(sources.list) do
                FashionTooltip:AddLine(sourceLine(source.id, source.collected))
            end
        else
            for _, id in ipairs(item.sources or { item.id }) do
                FashionTooltip:AddLine(sourceLine(id, not item.missing))
            end
            if sources and sources.loading then
                FashionTooltip:AddLine("|cff808080Loading all sources...|r")
            end
        end
        if item.reset then
            FashionTooltip:AddLine("Your equipped item's own look", 0.5, 0.5, 0.5)
        end
        if item.missing then
            FashionTooltip:AddLine("Not collected", 1, 0.27, 0.27)
            FashionTooltip:AddLine("Click to preview, Shift-click to link", 0.5, 0.5, 0.5)
        end
    end

    FashionTooltip:Show()
end

function Transmog:SetLookTooltip(button, item)
    button:SetScript("OnEnter", function()
        Transmog.lookTooltipOwner = this
        Transmog.lookTooltipItem = item
        if Transmog.serverSupportsExtended and item.id ~= Transmog.HIDDEN_ITEM_ID and not Transmog.sourcesByItem[item.id] then
            Transmog.sourcesByItem[item.id] = { loading = true, list = {} }
            Transmog:aSend("GetSources:" .. item.id)
        end
        Transmog:ShowLookTooltip(this, item)
    end)
    button:SetScript("OnLeave", function()
        Transmog.lookTooltipOwner = nil
        FashionTooltip:Hide()
    end)
end

-- "Sources:<item>:start", "Sources:<item>:<id>,<0|1>:...", "Sources:<item>:end".
function Transmog:OnSources(itemID, rest)
    if not itemID or not rest then
        return
    end

    local entry = self.sourcesByItem[itemID]
    if not entry then
        entry = { loading = true, list = {} }
        self.sourcesByItem[itemID] = entry
    end

    if rest == "start" then
        entry.list = {}
        entry.loading = true
    elseif rest == "end" then
        entry.loading = false
        if self.lookTooltipOwner and self.lookTooltipItem and self.lookTooltipItem.id == itemID then
            self:ShowLookTooltip(self.lookTooltipOwner, self.lookTooltipItem)
        end
    else
        for id, collected in string.gmatch(rest, "(%d+),(%d)") do
            table.insert(entry.list, { id = tonumber(id), collected = collected == "1" })
            self:cacheItem(tonumber(id))
        end
    end
end
