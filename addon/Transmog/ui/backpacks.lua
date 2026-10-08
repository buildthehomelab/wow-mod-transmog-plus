local Transmog = _G.Transmog

-- Backpacks: a model on the back, per character. Unlocked ones are picked here and put on
-- straight away (free); locked ones show what unlocks them. The server sends the list
-- (Backpack:<id>:<unlocked>:<phase>:<byItem>:<model>:<name>) and the current choice.

local NO_TRANSMOGS_TEXT = "You have yet to uncover any kind of appearance for this item. \nAppearances unlock when you loot, buy, craft or equip an item."

-- Individual progression phase n means this content is cleared.
Transmog.PHASE_NAMES = {
    [1] = "Molten Core",
    [2] = "Onyxia's Lair",
    [3] = "Blackwing Lair",
    [4] = "Zul'Gurub and the road to Ahn'Qiraj",
    [5] = "the Ahn'Qiraj War Effort",
    [6] = "the Temple of Ahn'Qiraj",
    [7] = "Naxxramas",
    [8] = "the road to Outland",
    [9] = "Karazhan, Gruul's Lair and Magtheridon's Lair",
    [10] = "Serpentshrine Cavern and Tempest Keep",
    [11] = "Hyjal Summit and Black Temple",
    [12] = "Zul'Aman",
    [13] = "the Sunwell Plateau",
    [14] = "Naxxramas, the Eye of Eternity and the Obsidian Sanctum",
    [15] = "Ulduar",
    [16] = "the Trial of the Crusader",
    [17] = "Icecrown Citadel",
    [18] = "the Ruby Sanctum",
}

local PHASE_NAMES = Transmog.PHASE_NAMES

local ICON_DIR = "Interface\\AddOns\\Transmog\\assets\\backpacks\\"
local NONE_ICON = "Interface\\Icons\\INV_Misc_Bag_08"

function Transmog:BackpackUnlockHint(entry)
    if entry.byItem then
        return "Use the backpack from your introduction letter (in your mailbox) to unlock it."
    end
    if entry.phase and entry.phase > 0 then
        return "Unlocks when you clear " .. (PHASE_NAMES[entry.phase] or ("progression phase " .. entry.phase)) .. "."
    end
    return "Not unlockable yet."
end

function Transmog:SetBackpacksTabActive(active)
    if not TransmogFrameBackpacksButton then
        return
    end
    local texture = active and 'tab_active' or 'tab_inactive'
    TransmogFrameBackpacksButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\' .. texture)
    TransmogFrameBackpacksButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
    TransmogFrameBackpacksButtonText:SetText((active and HIGHLIGHT_FONT_COLOR_CODE or NORMAL_FONT_COLOR_CODE) .. 'Backpacks')
end

-- The tiles are shared with the other tabs: give them their model back.
function Transmog:LeaveBackpacksView()
    self:SetBackpacksTabActive(false)
    for i, frame in pairs(self.ItemButtons) do
        if frame.backpackIcon then
            frame.backpackIcon:Hide()
        end
        local model = getglobal('TransmogLook' .. i .. 'ItemModel')
        if model then
            model:Show()
        end
    end
    TransmogFrameNoTransmogs:SetText(NO_TRANSMOGS_TEXT)
end

function Transmog:OnBackpacksStart()
    self.backpackList = {}
end

function Transmog:OnBackpack(id, unlocked, phase, byItem, model, name)
    table.insert(self.backpackList, {
        id = id, unlocked = unlocked == 1, phase = phase, byItem = byItem == 1, model = model, name = name,
    })
end

function Transmog:OnBackpacksLoaded()
    self.serverSupportsBackpacks = true
    if TransmogFrameBackpacksButton then
        TransmogFrameBackpacksButton:Show()
        self:SetBackpacksTabActive(self.tab == 'backpacks')
    end
    if self.tab == 'backpacks' and TransmogFrame:IsVisible() then
        self:RenderBackpacks()
    end
end

function Transmog:OnBackpackStatus(id)
    self.backpackChosen = id or 0
    if self.tab == 'backpacks' and TransmogFrame:IsVisible() then
        self:RenderBackpacks()
    end
end

function Transmog:OnBackpackUnlocked(id)
    for _, entry in ipairs(self.backpackList) do
        if entry.id == id then
            entry.unlocked = true
        end
    end
    if self.tab == 'backpacks' and TransmogFrame:IsVisible() then
        self:RenderBackpacks()
    end
end

function Transmog:ApplyBackpackResult(success, id)
    if success == 1 then
        PlaySoundFile("Interface\\AddOns\\Transmog\\assets\\ui_transmogrify_apply.ogg", "Dialog")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[Transmog]|r Couldn't change the backpack (not unlocked yet?).")
    end
end

function Transmog:TryBackpack(id)
    if id ~= 0 then
        for _, entry in ipairs(self.backpackList) do
            if entry.id == id and not entry.unlocked then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff80ff[" .. entry.name .. "]|r " .. self:BackpackUnlockHint(entry))
                return
            end
        end
    end
    if id == (self.backpackChosen or 0) then
        return
    end
    self:aSend("ApplyBackpack:" .. id)
end

-- "No backpack", then every backpack in the server's order; locked ones greyed out.
function Transmog:RenderBackpacks()
    self:hideItems(true)
    self:hideItemBorders()
    self:hidePlayerItemsBorders()
    TransmogFrameSplash:Hide()
    TransmogFrameInstructions:Hide()
    TransmogFrameNoTransmogs:Hide()

    local unlocked = 0
    for _, entry in ipairs(self.backpackList) do
        if entry.unlocked then
            unlocked = unlocked + 1
        end
    end
    TransmogFrameCollectedCollectedStatus:SetText("Backpacks: " .. unlocked .. "/" .. table.getn(self.backpackList))

    local entries = { { id = 0, name = "No backpack", unlocked = true, icon = NONE_ICON } }
    for _, entry in ipairs(self.backpackList) do
        table.insert(entries, entry)
    end

    local total = table.getn(entries)
    self.totalPages = math.max(1, self:ceil(total / self.ipp))
    if self.currentPage > self.totalPages then
        self.currentPage = self.totalPages
    end

    local chosen = self.backpackChosen or 0
    local itemIndex = 1
    local row, col = 0, 0
    for index, entry in ipairs(entries) do
        if index > (self.currentPage - 1) * self.ipp and index <= self.currentPage * self.ipp then
            if not self.ItemButtons[itemIndex] then
                self.ItemButtons[itemIndex] = CreateFrame('Frame', 'TransmogLook' .. itemIndex, TransmogFrame, 'TransmogFrameLookTemplate')
            end

            local frame = self.ItemButtons[itemIndex]
            frame:SetPoint("TOPLEFT", TransmogFrame, "TOPLEFT", 263 + col * 90, -105 - 120 * row)
            frame.name = entry.name
            frame.id = entry.id

            local button = getglobal('TransmogLook' .. itemIndex .. 'Button')
            button:SetID(entry.id)
            getglobal('TransmogLook' .. itemIndex .. 'ButtonRevert'):Hide()
            getglobal('TransmogLook' .. itemIndex .. 'ButtonCheck'):Hide()
            if entry.id == chosen then
                button:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\item_bg_selected')
            else
                button:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\item_bg_normal')
            end

            local hint
            if entry.id == 0 then
                hint = "Wear no backpack and show your cloak."
            elseif entry.unlocked then
                hint = entry.id == chosen and "You're wearing this backpack. It hides your cloak." or "Click to put it on. It hides your cloak."
            else
                hint = "|cffff4444Locked.|r " .. self:BackpackUnlockHint(entry)
            end
            AddButtonOnEnterTextTooltip(button, "|cffff80ff" .. entry.name, hint)

            getglobal('TransmogLook' .. itemIndex .. 'ItemModel'):Hide()
            if not frame.backpackIcon then
                frame.backpackIcon = frame:CreateTexture(nil, "OVERLAY")
                frame.backpackIcon:SetWidth(56)
                frame.backpackIcon:SetHeight(56)
                frame.backpackIcon:SetPoint("CENTER", button, "CENTER", 0, 4)
            end
            if not frame.backpackIcon:SetTexture(entry.icon or (ICON_DIR .. entry.id)) then
                frame.backpackIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            frame.backpackIcon:SetDesaturated(not entry.unlocked)
            frame.backpackIcon:SetVertexColor(entry.unlocked and 1 or 0.5, entry.unlocked and 1 or 0.5, entry.unlocked and 1 or 0.5)
            frame.backpackIcon:Show()

            frame:Show()

            col = col + 1
            if col == 5 then
                row = row + 1
                col = 0
            end
            itemIndex = itemIndex + 1
        end
    end

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
end

function Transmog:ShowBackpacksView()
    self.currentPage = 1
    self:RenderBackpacks()
end
