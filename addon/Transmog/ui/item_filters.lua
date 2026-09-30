local Transmog = _G.Transmog

-- Items tab filters under the grid: a name search, and a Missing view that lists the looks the
-- account hasn't collected yet. Collected looks are filtered here; missing looks come from the
-- server (GetMissing), which knows every item and runs the search there too.

Transmog.NO_TRANSMOGS_TEXT = "You have yet to uncover any kind of appearance for this item. \nAppearances unlock when you loot, buy, craft or equip an item."

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
    if string.find(lower(item.name), needle, 1, true) then
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

-- The tiles to show for the selected slot, and the text for an empty grid (nil hides it).
function Transmog:GetShownLooks(slot, itemClass)
    local shown = {}

    if self.showMissing then
        local key = slot .. ":" .. equippedId(slot) .. ":" .. lower(serverQuery())
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
            local name, link, quality = GetItemInfo(id)
            table.insert(shown, {
                ['id'] = id,
                ['name'] = name or ("Item #" .. id),
                ['link'] = link,
                ['quality'] = quality or 1,
                ['sources'] = { id },
                ['missing'] = true
            })
        end

        if table.getn(shown) == 0 then
            if serverQuery() ~= "" then
                return shown, "No missing appearances match your search."
            end
            return shown, "You have collected every appearance this item can use."
        end
        return shown, nil
    end

    local needle = lower(self.searchText)
    for _, item in ipairs(self.availableTransmogItems[slot] and self.availableTransmogItems[slot][itemClass] or {}) do
        if lookMatches(item, needle) then
            table.insert(shown, item)
        end
    end

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
    self:aSend("GetMissing:" .. self.missingSeq .. ":" .. (slot - 1) .. ":" .. serverQuery())
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
        local texture = data.id == itemId and 'item_bg_selected' or 'item_bg_normal'
        getglobal('TransmogLook' .. itemIndex .. 'Button'):SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\' .. texture)
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
        return true
    end
    return false
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
