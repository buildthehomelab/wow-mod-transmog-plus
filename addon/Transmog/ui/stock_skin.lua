-- The stock look. Without DragonUI the window wears stock 3.3.5 art instead of its own retail
-- art: a dialog box with its header plate, options-box panes, top tabs, item-slot frames on the
-- gear slots and the DressUpFrame's race picture behind the model. With DragonUI
-- (ui/dragonui_skin.lua) nothing below the helpers runs and the window keeps the art it has there.
-- Loaded last: it needs TransmogFrame, and it runs after the DragonUI skin.

local Transmog = _G.Transmog

local ART = "Interface\\AddOns\\Transmog\\assets\\"
local TOOLTIP_BG = "Interface\\Tooltips\\UI-Tooltip-Background"
local TOOLTIP_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local BUTTON_HILIGHT = "Interface\\Buttons\\ButtonHilight-Square"
local CHECKED = "Interface\\Buttons\\CheckButtonHilight"
local QUICKSLOT = "Interface\\Buttons\\UI-Quickslot2"
local ACTION_BORDER = "Interface\\Buttons\\UI-ActionButton-Border"
local UNDO = "Interface\\PaperDollInfoFrame\\UI-GearManager-Undo"
local LEAVE_ITEM = "Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent"
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"

-- An options box (the Interface Options' panes): tooltip border on a dim grey.
local BOX = {
    bgFile = TOOLTIP_BG,
    edgeFile = TOOLTIP_BORDER,
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 5, bottom = 3 },
}

function Transmog.StockInset(pane)
    pane:SetBackdrop(BOX)
    pane:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    pane:SetBackdropBorderColor(0.4, 0.4, 0.4)
end

-- TabButtonTemplate's pieces, left to right; the active ones sit 3 lower to join the pane.
local function tabPieces(button, file, y)
    local left = button:CreateTexture(nil, "BACKGROUND")
    left:SetTexture(file)
    left:SetTexCoord(0, 0.25, 0, 1)
    left:SetWidth(16)
    left:SetHeight(32)
    left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, y)
    local right = button:CreateTexture(nil, "BACKGROUND")
    right:SetTexture(file)
    right:SetTexCoord(0.75, 1, 0, 1)
    right:SetWidth(16)
    right:SetHeight(32)
    right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, y)
    local middle = button:CreateTexture(nil, "BACKGROUND")
    middle:SetTexture(file)
    middle:SetTexCoord(0.25, 0.75, 0, 1)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    return { left, middle, right }
end

local function clear(texture)
    if texture then
        texture:SetTexture(nil)
    end
end

-- The tab row: stock top tabs, or the retail art the DragonUI window keeps.
function Transmog:SetTabLook(button, active)
    if not button then
        return
    end
    if button.stockActive then
        for i = 1, 3 do
            if active then
                button.stockActive[i]:Show()
                button.stockInactive[i]:Hide()
            else
                button.stockActive[i]:Hide()
                button.stockInactive[i]:Show()
            end
        end
    else
        button:SetNormalTexture(ART .. (active and "tab_active" or "tab_inactive"))
        button:SetPushedTexture(ART .. "tab_active")
    end
end

-- A look tile in the stock box: the options box around the model, gold and checked when chosen,
-- the item button's square glow on hover.
local function stockTile(button)
    local look = button:GetParent()
    local box = CreateFrame("Frame", nil, look)
    box:SetPoint("TOPLEFT", look, "TOPLEFT", 2, 1)
    box:SetPoint("BOTTOMRIGHT", look, "TOPLEFT", 86, -109)
    box:SetFrameLevel(look:GetFrameLevel())
    Transmog.StockInset(box)
    box.checked = box:CreateTexture(nil, "ARTWORK")
    box.checked:SetTexture(CHECKED)
    box.checked:SetBlendMode("ADD")
    box.checked:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
    box.checked:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 4)
    box.checked:Hide()

    clear(button:GetNormalTexture())
    clear(button:GetPushedTexture())
    local hl = button:GetHighlightTexture()
    hl:SetTexture(BUTTON_HILIGHT)
    hl:SetTexCoord(0, 1, 0, 1)
    hl:ClearAllPoints()
    hl:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
    hl:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 4)

    local name = button:GetName()
    local revert = getglobal(name .. "Revert")
    revert:SetTexture(UNDO)
    revert:ClearAllPoints()
    revert:SetPoint("TOPLEFT", box, "TOPLEFT", 5, -5)
    local check = getglobal(name .. "Check")
    check:SetTexture(CHECK)
    check:SetWidth(20)
    check:SetHeight(20)
    check:ClearAllPoints()
    check:SetPoint("TOPRIGHT", box, "TOPRIGHT", -3, -3)

    button.stockBox = box
    return box
end

-- A look tile, chosen or not.
function Transmog:SetTileLook(button, selected)
    if self.stockLook then
        local box = button.stockBox or stockTile(button)
        if selected then
            box:SetBackdropBorderColor(1, 0.82, 0)
            box.checked:Show()
        else
            box:SetBackdropBorderColor(0.4, 0.4, 0.4)
            box.checked:Hide()
        end
    else
        button:SetNormalTexture(ART .. (selected and "item_bg_selected" or "item_bg_normal"))
    end
end

-- The new-appearance toast: the achievement alert's plate and icon frame in place of the
-- animated retail loot frame. The icon sits where the alert's icon sits.
function Transmog:StyleToast(toast)
    if not self.stockLook or toast.stockPlate then
        return
    end
    local name = toast:GetName()
    local plate = toast:CreateTexture(nil, "BACKGROUND")
    plate:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Alert-Background")
    plate:SetTexCoord(0, 0.605, 0, 0.703)
    plate:SetWidth(300)
    plate:SetHeight(88)
    plate:SetPoint("TOPLEFT", toast, "TOPLEFT", 142, -30)
    toast.stockPlate = plate

    local label = toast:CreateFontString(nil, "ARTWORK", "GameFontBlackTiny")
    label:SetWidth(200)
    label:SetHeight(12)
    label:SetPoint("TOP", plate, "TOP", 7, -23)
    label:SetText("Appearance Collected")

    local itemName = getglobal(name .. "ItemName")
    itemName:SetFontObject(GameFontHighlight)
    itemName:SetJustifyH("CENTER")
    itemName:ClearAllPoints()
    itemName:SetPoint("BOTTOMLEFT", plate, "BOTTOMLEFT", 72, 36)
    itemName:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", -60, 36)
    itemName:SetHeight(16)

    local icon = getglobal(name .. "Icon")
    local ring = icon:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
    ring:SetTexCoord(0, 0.5625, 0, 0.5625)
    ring:SetWidth(52)
    ring:SetHeight(52)
    ring:SetPoint("CENTER", icon, "CENTER", -1, 1)
end

if Transmog.Dragon() or not TransmogFrame then return end

Transmog.stockLook = true

local frame = TransmogFrame

-- The model window and the appearance pane, as the DragonUI skin cuts them, kept clear of the
-- dialog border and the Apply button.
local MODEL_LEFT, MODEL_TOP, MODEL_RIGHT, MODEL_BOTTOM = 20, -111, 241, -468
local PANE_LEFT, PANE_TOP, PANE_RIGHT, PANE_BOTTOM = 246, -79, -12, 12

local DIALOG = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

frame:SetBackdrop(DIALOG)

TransmogFrameBackground1:Hide()
TransmogFrameBackground2:Hide()
TransmogFramePortrait:Hide()
TransmogFrameRaceBackground:Hide()
-- Shown and hidden all over the addon; it just draws nothing here.
TransmogFrameSplash:SetAlpha(0)

local header = frame:CreateTexture(nil, "ARTWORK")
header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
header:SetWidth(256)
header:SetHeight(64)
header:SetPoint("TOP", frame, "TOP", 0, 12)

TransmogFrameTitleText:SetDrawLayer("OVERLAY")
TransmogFrameTitleText:ClearAllPoints()
TransmogFrameTitleText:SetPoint("TOP", header, "TOP", 0, -14)

-- Both hung off the title before; with no splash the hint goes to the middle of the pane.
TransmogFrameInstructions:ClearAllPoints()
TransmogFrameInstructions:SetPoint("CENTER", frame, "TOPLEFT", 485, -280)
TransmogFrameNoTransmogs:ClearAllPoints()
TransmogFrameNoTransmogs:SetPoint("CENTER", frame, "TOPLEFT", 485, -268)

TransmogFrameCloseButton:ClearAllPoints()
TransmogFrameCloseButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)

-- Clear of the dialog border.
TransmogFrameCollected:SetWidth(140)
TransmogFrameApplyButton:ClearAllPoints()
TransmogFrameApplyButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 120, 13)

-- An options box drawn round a part of the window: the grey on the window itself, under the
-- texts it draws there, and only the border on a frame of its own.
local function box(left, top, right, bottom, fill)
    if fill then
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(TOOLTIP_BG)
        bg:SetVertexColor(0.1, 0.1, 0.1, 0.5)
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", left + 3, top - 5)
        bg:SetPoint("BOTTOMRIGHT", frame, right < 0 and "BOTTOMRIGHT" or "TOPLEFT", right - 3, bottom + 3)
    end
    local border = CreateFrame("Frame", nil, frame)
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", left, top)
    border:SetPoint("BOTTOMRIGHT", frame, right < 0 and "BOTTOMRIGHT" or "TOPLEFT", right, bottom)
    border:SetFrameLevel(frame:GetFrameLevel() + 1)
    border:SetBackdrop({ edgeFile = TOOLTIP_BORDER, tile = true, tileSize = 16, edgeSize = 16 })
    border:SetBackdropBorderColor(0.4, 0.4, 0.4)
    return border
end

box(MODEL_LEFT, MODEL_TOP, MODEL_RIGHT, MODEL_BOTTOM, false)
box(PANE_LEFT, PANE_TOP, PANE_RIGHT, PANE_BOTTOM, true)

-- The DressUpFrame's race picture (318x383 in four pieces) behind the model: scaled to the
-- window's height and cut evenly at both sides to its width.
local race = {}
do
    local inLeft, inTop = MODEL_LEFT + 4, MODEL_TOP - 4
    local w, h = MODEL_RIGHT - MODEL_LEFT - 8, MODEL_TOP - MODEL_BOTTOM - 8
    local scale = h / 383
    local cut = (318 - w / scale) / 2
    local leftW, rightW = (256 - cut) * scale, (62 - cut) * scale
    local topH = 255 * scale
    local pieces = {
        { inLeft, inTop, leftW, topH, cut / 256, 1 },
        { inLeft + leftW, inTop, rightW, topH, 0, (62 - cut) / 62 },
        { inLeft, inTop - topH, leftW, h - topH, cut / 256, 1 },
        { inLeft + leftW, inTop - topH, rightW, h - topH, 0, (62 - cut) / 62 },
    }
    for i, p in ipairs(pieces) do
        local tex = frame:CreateTexture(nil, "BACKGROUND")
        tex:SetPoint("TOPLEFT", frame, "TOPLEFT", p[1], p[2])
        tex:SetWidth(p[3])
        tex:SetHeight(p[4])
        tex:SetTexCoord(p[5], p[6], 0, 1)
        race[i] = tex
    end
end

local function setRace()
    if not DressUpTexturePath then
        return
    end
    local path = DressUpTexturePath()
    for i = 1, 4 do
        race[i]:SetTexture(path .. i)
    end
end
setRace()
frame:HookScript("OnShow", setRace)

-- The tabs, on the pane's top edge.
local tabs = { TransmogFrameItemsButton, TransmogFrameSetsButton, TransmogFrameIllusionsButton,
    TransmogFrameBackpacksButton, TransmogFrameFormsButton }
for _, tab in ipairs(tabs) do
    tab.stockInactive = tabPieces(tab, "Interface\\HelpFrame\\HelpFrameTab-Inactive", 0)
    tab.stockActive = tabPieces(tab, "Interface\\HelpFrame\\HelpFrameTab-Active", -3)
    clear(tab:GetNormalTexture())
    clear(tab:GetPushedTexture())
    clear(tab:GetDisabledTexture())
    tab:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight", "ADD")
    local hl = tab:GetHighlightTexture()
    hl:SetTexCoord(0, 1, 0, 1)
    hl:ClearAllPoints()
    hl:SetPoint("BOTTOM", tab, "BOTTOM", 2, -8)
    hl:SetWidth(tab:GetWidth() - 20)
    hl:SetHeight(32)
    tab:SetNormalFontObject(GameFontNormalSmall)
    tab:SetHighlightFontObject(GameFontHighlightSmall)
    local text = getglobal(tab:GetName() .. "Text")
    text:ClearAllPoints()
    text:SetPoint("BOTTOM", tab, "BOTTOM", 0, 5)
    tab:SetFrameLevel(frame:GetFrameLevel() + 3)
    Transmog:SetTabLook(tab, tab == TransmogFrameItemsButton)
end

-- The gear slots: an item button's frame round the icon, its square glow on hover, the checked
-- glow on the chosen slot, the action button's border on a transmogrified one and the gear
-- manager's own marks for an empty slot and a revert.
local SLOTS = { "HeadSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot",
    "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
    "MainHandSlotSmall" }

local function around(texture, icon, size, file, mode)
    texture:SetTexture(file)
    if mode then
        texture:SetBlendMode(mode)
    end
    texture:ClearAllPoints()
    if size then
        texture:SetWidth(size)
        texture:SetHeight(size)
        texture:SetPoint("CENTER", icon, "CENTER", 0, -1)
    else
        texture:SetAllPoints(icon)
    end
end

for _, slotName in ipairs(SLOTS) do
    local icon = getglobal(slotName .. "ItemIcon")
    if icon then
        around(getglobal(slotName .. "Border"), icon, 45, QUICKSLOT)
        around(getglobal(slotName .. "BorderHi"), icon, 45, ACTION_BORDER, "ADD")
        getglobal(slotName .. "BorderHi"):SetVertexColor(1, 0.6, 0.1)
        around(getglobal(slotName .. "BorderFull"), icon, 45, ACTION_BORDER, "ADD")
        getglobal(slotName .. "BorderFull"):SetVertexColor(1, 0.82, 0)
        around(getglobal(slotName .. "BorderSelected"), icon, nil, CHECKED, "ADD")
        around(getglobal(slotName .. "BorderHighlight"), icon, nil, BUTTON_HILIGHT, "ADD")
        around(getglobal(slotName .. "NoEquip"), icon, 28, LEAVE_ITEM)
        getglobal(slotName .. "Revert"):SetTexture(UNDO)
    end
end

-- The window's own revert button.
TransmogFrameRevert:SetNormalTexture(UNDO)
TransmogFrameRevert:SetPushedTexture(UNDO)
TransmogFrameRevert:SetHighlightTexture(BUTTON_HILIGHT, "ADD")

-- Docked in the Journal's Appearances tab (ui/journal_tab.lua) the Journal's window is the
-- frame: the dialog box, its header, title and close button go, and the model window and pane
-- sit straight on the Journal. Returns true when it went bare.
local windowParts = { header, TransmogFrameTitleText, TransmogFrameCloseButton }

function Transmog.SetDockedChrome(docked)
    if docked then
        frame:SetBackdrop(nil)
    else
        frame:SetBackdrop(DIALOG)
    end
    for i = 1, #windowParts do
        if docked then windowParts[i]:Hide() else windowParts[i]:Show() end
    end
    return true
end
