-- DragonUI reskin. With DragonUI loaded (and new enough to carry the helpers borrowed here) the
-- transmog window trades its baked retail art for DragonUI's: the metal portrait frame on rock,
-- marble insets, red buttons, DragonUI's close button, checkbox and scroll bar. Without DragonUI
-- nothing here runs and ui/stock_skin.lua gives the window the stock 3.3.5 look instead.
-- Loaded after transmog.xml: it needs TransmogFrame.

local Transmog = _G.Transmog

-- DragonUI's nine-slice helper: DragonUI_NineSlice since DragonUI's 2026 rewrite, NineSliceUtils
-- before it.
local NineSlice = _G.DragonUI_NineSlice or _G.NineSliceUtils

function Transmog.Dragon()
    local D = _G.DragonUI
    if D and D._dir and D.atlasinfo and D.SafeSetAtlas and D.SkinRedButton and NineSlice
            and D.CharacterPanel and D.CharacterPanel.ReskinTab then
        return D, D.CharacterPanel
    end
end

local function tiled(host, sublevel, file)
    local tex = host:CreateTexture(nil, "BACKGROUND", nil, sublevel)
    tex:SetTexture(file, "REPEAT", "REPEAT")
    tex:SetHorizTile(true)
    tex:SetVertTile(true)
    return tex
end

-- A recessed pane on marble (retail's InsetFrameTemplate). Returns false without DragonUI, so
-- the caller falls back to the stock box (Transmog.StockInset in ui/stock_skin.lua).
function Transmog.SkinInset(pane)
    local D = Transmog.Dragon()
    if not D then return false end
    tiled(pane, -5, D._dir .. "UI\\ui-background-marble"):SetAllPoints(pane)
    NineSlice.ApplyLayout(pane, NineSlice.GetLayout("InsetFrameTemplate"))
    return true
end

-- A FauxScrollFrame's bar: DragonUI's thin one, flush inside `host`.
function Transmog.SkinScrollBar(scroll, host)
    local _, CP = Transmog.Dragon()
    if CP and CP.ReskinScrollBar then
        pcall(CP.ReskinScrollBar, scroll, host, 0, -4, 0, true)
    end
end

local D, CP = Transmog.Dragon()
if not (D and TransmogFrame) then return end

local frame = TransmogFrame

-- Where the baked art leaves its holes (measured off ui1.blp): the model window and the
-- appearance pane to its right, which starts under the tabs here so they sit on its trim.
local MODEL_LEFT, MODEL_TOP, MODEL_RIGHT, MODEL_BOTTOM = 20, -111, 241, -473
local PANE_LEFT, PANE_TOP, PANE_RIGHT, PANE_BOTTOM = 246, -79, -24, 8
-- The race picture is 442 square at (18, -70) and was cut down to the model window by the art.
local RACE_X, RACE_Y, RACE_SIZE = 18, -70, 442

TransmogFrameBackground1:Hide()
TransmogFrameBackground2:Hide()

local rock = tiled(frame, -8, D._dir .. "UI\\ui-background-rock")
rock:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -21)
rock:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

local streaks = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
local hasStreaks = D:SafeSetAtlas(streaks, "_UI-Frame-TopTileStreaks")
if hasStreaks then
    streaks:SetHorizTile(true)
    streaks:SetHeight(43)
    streaks:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -21)
    streaks:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -21)
else
    streaks:Hide()
end

-- The race picture keeps to the model window on its own now.
local race = TransmogFrameRaceBackground
race:ClearAllPoints()
race:SetPoint("TOPLEFT", frame, "TOPLEFT", MODEL_LEFT, MODEL_TOP)
race:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", MODEL_RIGHT, MODEL_BOTTOM)
race:SetTexCoord((MODEL_LEFT - RACE_X) / RACE_SIZE, (MODEL_RIGHT - RACE_X) / RACE_SIZE,
    (RACE_Y - MODEL_TOP) / RACE_SIZE, (RACE_Y - MODEL_BOTTOM) / RACE_SIZE)

local modelInset = CreateFrame("Frame", nil, frame)
modelInset:SetPoint("TOPLEFT", race, "TOPLEFT")
modelInset:SetPoint("BOTTOMRIGHT", race, "BOTTOMRIGHT")
modelInset:EnableMouse(false)
NineSlice.ApplyLayout(modelInset, NineSlice.GetLayout("InsetFrameTemplate"))

-- The appearance pane's marble goes on the window itself, under the splash and the texts the
-- window draws there; only the trim needs a frame of its own.
local marble = tiled(frame, -6, D._dir .. "UI\\ui-background-marble")
marble:SetPoint("TOPLEFT", frame, "TOPLEFT", PANE_LEFT, PANE_TOP)
marble:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", PANE_RIGHT, PANE_BOTTOM)

local pane = CreateFrame("Frame", nil, frame)
pane:SetAllPoints(marble)
pane:EnableMouse(false)
NineSlice.ApplyLayout(pane, NineSlice.GetLayout("InsetFrameTemplate"))

-- The metal sits on a frame of its own above the content, so no child draws over it.
local chrome = CreateFrame("Frame", nil, frame)
chrome:SetAllPoints(frame)
chrome:SetFrameLevel(frame:GetFrameLevel() + 30)
chrome:EnableMouse(false)
NineSlice.ApplyLayout(chrome, NineSlice.GetLayout("PortraitFrameTemplate"))

-- Under the frame's ring, where DragonUI's own windows put their portrait.
TransmogFramePortrait:SetParent(chrome)
TransmogFramePortrait:SetDrawLayer("ARTWORK")
TransmogFramePortrait:ClearAllPoints()
TransmogFramePortrait:SetSize(58, 58)
TransmogFramePortrait:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 6)

TransmogFrameTitleText:SetParent(chrome)
TransmogFrameTitleText:SetDrawLayer("OVERLAY")
TransmogFrameTitleText:ClearAllPoints()
TransmogFrameTitleText:SetPoint("TOP", frame, "TOP", 0, -5)

if CP.ModernizeCloseButton then
    CP.ModernizeCloseButton(TransmogFrameCloseButton, chrome, 1, 0)
    TransmogFrameCloseButton:SetFrameLevel(chrome:GetFrameLevel() + 5)
end

D.SkinRedButton(TransmogFrameApplyButton)
D.SkinRedButton(TransmogFrameSaveOutfit)

if CP.SkinCheckbox then CP.SkinCheckbox(TransmogFrameFiltersMissing) end

-- The search box: the stock box with its border darkened to a plain well.
local regions = { TransmogFrameFiltersSearch:GetRegions() }
for i = 1, #regions do
    local r = regions[i]
    if r:GetObjectType() == "Texture" then
        local path = r:GetTexture()
        if type(path) == "string" and path:lower():find("common%-input%-border") then
            r:SetTexture(0, 0, 0, 0.55)
        end
    end
end

-- Docked in the Journal's Appearances tab (ui/journal_tab.lua) the Journal's own DragonUI window
-- is the frame: the metal, the rock and streaks behind it, the portrait, title and close button
-- all go, and the model window and appearance pane sit straight on the Journal's rock, as
-- retail's Appearances tab does in its Collections window. Returns true when it went bare.
local windowParts = { rock, chrome, TransmogFrameCloseButton }
if hasStreaks then windowParts[#windowParts + 1] = streaks end

function Transmog.SetDockedChrome(docked)
    for i = 1, #windowParts do
        if docked then windowParts[i]:Hide() else windowParts[i]:Show() end
    end
    return true
end
