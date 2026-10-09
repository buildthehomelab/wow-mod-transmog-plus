local Transmog = _G.Transmog

-- Forms: druid shapeshift looks, one choice per form, like the retail barber shop. The server
-- sends every look (Form:<display>:<unlocked>:<phase>:<form>:<preview creature>:<name>) and the
-- current choice per form. Tiles preview each look through a creature that uses its display
-- (3.3.5 model frames can't show a display id); locked looks show as a silhouette.

local FORMS = {
    { key = "bear",    name = "Bear Form",     icon = "Interface\\Icons\\Ability_Racial_BearForm" },
    { key = "cat",     name = "Cat Form",      icon = "Interface\\Icons\\Ability_Druid_CatForm" },
    { key = "travel",  name = "Travel Form",   icon = "Interface\\Icons\\Ability_Druid_TravelForm" },
    { key = "aquatic", name = "Aquatic Form",  icon = "Interface\\Icons\\Ability_Druid_AquaticForm" },
    { key = "flight",  name = "Flight Form",   icon = "Interface\\Icons\\Ability_Druid_FlightForm" },
    { key = "moonkin", name = "Moonkin Form",  icon = "Interface\\Icons\\Spell_Nature_ForceOfNature" },
    { key = "tree",    name = "Tree of Life",  icon = "Interface\\Icons\\Ability_Druid_TreeofLife" },
}

Transmog.formKey = "bear"

local function formInfo(key)
    for _, f in ipairs(FORMS) do
        if f.key == key then
            return f
        end
    end
end

function Transmog:FormUnlockHint(entry)
    if entry.phase and entry.phase > 0 then
        local names = self.PHASE_NAMES or {}
        return "Unlocks when you clear " .. (names[entry.phase] or ("progression phase " .. entry.phase)) .. "."
    end
    return "Available from the start."
end

-- The big character model on the left shows a look like the barber shop does: the chosen one,
-- or the hovered tile. 0 (the default look) shows the character as it is.
function Transmog:PreviewFormLook(preview)
    local model = TransmogFramePlayerModel
    self.formPreviewing = true
    if not preview or preview == 0 then
        if model.wantKey then
            self:ForgetPreview(model)
            model:SetUnit("player")
            self:RefreshPreviewModel()
        end
        return
    end
    -- If the look never loads, show the character again rather than an empty frame.
    self:ShowPreview(model, { creature = preview }, nil, false, function()
        self:ForgetPreview(model)
        model:SetUnit("player")
        self:RefreshPreviewModel()
    end)
end

function Transmog:ChosenFormPreview()
    local chosen = (self.formChosen or {})[self.formKey] or 0
    for _, entry in ipairs(self.formList) do
        if entry.id == chosen then
            return entry.preview
        end
    end
    return 0
end

function Transmog:SetFormsTabActive(active)
    if not TransmogFrameFormsButton then
        return
    end
    local texture = active and 'tab_active' or 'tab_inactive'
    TransmogFrameFormsButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\' .. texture)
    TransmogFrameFormsButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
    TransmogFrameFormsButtonText:SetText((active and HIGHLIGHT_FONT_COLOR_CODE or NORMAL_FONT_COLOR_CODE) .. 'Forms')
end

-- The form picker: one icon per form above the grid.
function Transmog:FormPicker()
    if self.formPicker then
        return self.formPicker
    end
    local picker = CreateFrame("Frame", "TransmogFrameFormPicker", TransmogFrame)
    picker:SetWidth(7 * 26)
    picker:SetHeight(22)
    picker:SetPoint("TOPLEFT", TransmogFrame, "TOPLEFT", 268, -80)
    picker.buttons = {}
    for i, f in ipairs(FORMS) do
        local b = CreateFrame("Button", "TransmogFrameFormPicker" .. f.key, picker)
        b:SetWidth(22)
        b:SetHeight(22)
        b:SetPoint("LEFT", picker, "LEFT", (i - 1) * 26, 0)
        b:SetNormalTexture(f.icon)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.selected = b:CreateTexture(nil, "OVERLAY")
        b.selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        b.selected:SetBlendMode("ADD")
        b.selected:SetAllPoints(b)
        b.key = f.key
        b:SetScript("OnClick", function(button)
            Transmog.formKey = button.key
            Transmog.currentPage = 1
            PlaySound("igMainMenuOptionCheckBoxOn")
            Transmog:RenderForms()
        end)
        b:SetScript("OnEnter", function(button)
            GameTooltip:SetOwner(button, "ANCHOR_TOP")
            GameTooltip:AddLine(formInfo(button.key).name, 1, 1, 1)
            local unlocked, total = Transmog:CountForms(button.key)
            GameTooltip:AddLine(unlocked .. "/" .. total .. " looks unlocked", 1, 0.82, 0)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        picker.buttons[f.key] = b
    end
    self.formPicker = picker
    return picker
end

function Transmog:CountForms(key)
    local unlocked, total = 0, 0
    for _, entry in ipairs(self.formList) do
        if not key or entry.form == key then
            total = total + 1
            if entry.unlocked then
                unlocked = unlocked + 1
            end
        end
    end
    return unlocked, total
end

-- The tiles are shared with the other tabs: give them their item model back.
function Transmog:LeaveFormsView()
    self:SetFormsTabActive(false)
    if self.formPreviewing then
        self.formPreviewing = false
        if TransmogFramePlayerModel.wantKey then
            self:ForgetPreview(TransmogFramePlayerModel)
            TransmogFramePlayerModel:SetUnit("player")
            self:RefreshPreviewModel()
        end
    end
    if self.formPicker then
        self.formPicker:Hide()
    end
    self:HideTilePreviews()
    for i in pairs(self.ItemButtons) do
        local model = getglobal('TransmogLook' .. i .. 'ItemModel')
        if model then
            model:Show()
        end
    end
end

function Transmog:OnFormsStart(phase)
    self.formList = {}
    self.formPhase = phase or 0
end

function Transmog:OnForm(display, unlocked, phase, form, preview, name)
    table.insert(self.formList, {
        id = display, unlocked = unlocked == 1, phase = phase, form = form, preview = preview, name = name,
    })
end

function Transmog:OnFormsLoaded()
    self.serverSupportsForms = true
    if TransmogFrameFormsButton then
        TransmogFrameFormsButton:Show()
        -- The Forms tab takes the Collected bar's place in the tab row: move the bar under it.
        TransmogFrameCollected:ClearAllPoints()
        TransmogFrameCollected:SetPoint("TOPLEFT", TransmogFrame, "TOPLEFT", 590, -84)
        self:SetFormsTabActive(self.tab == 'forms')
    end
    if self.tab == 'forms' and TransmogFrame:IsVisible() then
        self:RenderForms()
    end
end

-- "bear=95003,cat=0,..."
function Transmog:OnFormStatus(text)
    self.formChosen = {}
    for key, display in string.gmatch(text, "(%a+)=(%d+)") do
        self.formChosen[key] = tonumber(display)
    end
    if self.tab == 'forms' and TransmogFrame:IsVisible() then
        self:RenderForms()
    end
end

function Transmog:OnFormsUnlocked()
    self:aSend("GetForms")
end

function Transmog:ApplyFormResult(success)
    if success == 1 then
        PlaySoundFile("Interface\\AddOns\\Transmog\\assets\\ui_transmogrify_apply.ogg", "Dialog")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[Transmog]|r Couldn't change the form look (not unlocked yet?).")
    end
end

function Transmog:TryForm(id)
    local key = self.formKey
    if id ~= 0 then
        for _, entry in ipairs(self.formList) do
            if entry.id == id and not entry.unlocked then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff80ff[" .. entry.name .. "]|r " .. self:FormUnlockHint(entry))
                return
            end
        end
    end
    if id == ((self.formChosen or {})[key] or 0) then
        return
    end
    self:aSend("ApplyForm:" .. key .. ":" .. id)
end

-- "Default look", then every look for the picked form; locked ones as silhouettes.
function Transmog:RenderForms()
    self:hideItems(true)
    self:hideItemBorders()
    self:hidePlayerItemsBorders()
    TransmogFrameSplash:Hide()
    TransmogFrameInstructions:Hide()
    TransmogFrameNoTransmogs:Hide()

    local key = self.formKey
    local picker = self:FormPicker()
    picker:Show()
    for k, b in pairs(picker.buttons) do
        if k == key then
            b.selected:Show()
        else
            b.selected:Hide()
        end
    end

    local unlocked, total = self:CountForms()
    TransmogFrameCollectedCollectedStatus:SetText("Forms: " .. unlocked .. "/" .. total)

    local info = formInfo(key)
    local entries = { { id = 0, name = "Default " .. info.name, unlocked = true, icon = info.icon } }
    for _, entry in ipairs(self.formList) do
        if entry.form == key then
            table.insert(entries, entry)
        end
    end

    local count = table.getn(entries)
    self.totalPages = math.max(1, self:ceil(count / self.ipp))
    if self.currentPage > self.totalPages then
        self.currentPage = self.totalPages
    end

    local chosen = (self.formChosen or {})[key] or 0
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
                hint = "Your usual " .. info.name .. "."
            elseif entry.unlocked then
                hint = entry.id == chosen and "You're using this look." or "Click to use this look for " .. info.name .. "."
            else
                hint = "|cffff4444Locked.|r " .. self:FormUnlockHint(entry)
            end
            AddButtonOnEnterTextTooltip(button, "|cffff80ff" .. entry.name, hint)
            -- Hovering a tile tries the look on the big model; leaving goes back to the chosen one.
            local onEnter, onLeave = button:GetScript("OnEnter"), button:GetScript("OnLeave")
            local preview = entry.id == 0 and 0 or entry.preview
            button:SetScript("OnEnter", function(...)
                if onEnter then onEnter(...) end
                if Transmog.tab == 'forms' then
                    Transmog:PreviewFormLook(preview)
                end
            end)
            button:SetScript("OnLeave", function(...)
                if onLeave then onLeave(...) end
                if Transmog.tab == 'forms' then
                    Transmog:PreviewFormLook(Transmog:ChosenFormPreview())
                end
            end)

            getglobal('TransmogLook' .. itemIndex .. 'ItemModel'):Hide()
            local model, icon = self:TilePreview(frame, button)
            if entry.id == 0 or not entry.preview or entry.preview == 0 then
                self:ForgetPreview(model)
                model:Hide()
                icon:SetTexture(entry.icon or info.icon)
                icon:Show()
            else
                icon:Hide()
                model:Show()
                self:ShowPreview(model, { creature = entry.preview }, 'forms', not entry.unlocked, function()
                    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    icon:Show()
                end)
            end

            frame:Show()

            col = col + 1
            if col == 5 then
                row = row + 1
                col = 0
            end
            itemIndex = itemIndex + 1
        end
    end

    self:PreviewFormLook(self:ChosenFormPreview())

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

function Transmog:ShowFormsView()
    self.currentPage = 1
    -- Open on the form the druid is in, if it's one with looks.
    local form = GetShapeshiftForm and GetShapeshiftForm() or 0
    if form > 0 then
        local _, name = GetShapeshiftFormInfo(form)
        for _, f in ipairs(FORMS) do
            if name and (name == f.name or (f.key == "bear" and name == "Dire Bear Form")
                    or (f.key == "flight" and name == "Swift Flight Form")) then
                self.formKey = f.key
            end
        end
    end
    self:RenderForms()
end
