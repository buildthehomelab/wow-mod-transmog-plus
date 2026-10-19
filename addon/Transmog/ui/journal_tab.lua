-- The Journal's Appearances tab. With the Journal addon (mod-forever-journal) installed, the
-- transmog window opens inside the Journal's window as one of its tabs, through the same
-- "open anywhere" request /transmog uses (Transmog.OpenAnywhere on the server). Leaving the tab
-- or closing the Journal puts the window back where it was, so the NPC and /transmog work as before.
-- Loaded after transmog.xml: it needs TransmogFrame.

local Transmog = _G.Transmog

if not (Journal and Journal.RegisterTab and (Journal.API or 0) >= 1 and TransmogFrame) then return end

-- The window is a fixed 750x506 layout, much smaller than the Journal's content area, so in the
-- Journal it is scaled up to fill it. It drops its own frame there (Transmog.SetDockedChrome in
-- ui/dragonui_skin.lua, or ui/stock_skin.lua without DragonUI) and only its content counts: from the tabs
-- (47 down) to the pane's bottom edge (8 up), and from the model window's left edge (20) to the
-- Collected bar's right end (590 + 150), which reaches past the pane's.
local FRAME_W, FRAME_H = 750, 506
local BARE_LEFT, BARE_TOP, BARE_RIGHT, BARE_BOTTOM = 20, 47, 740, 498
-- Room left between the content and the Journal's edges, in the Journal's units.
local FIT_MARGIN = 14
local MAX_SCALE = 1.6

local docked = false
local bare = false
local status
local saved -- where the window was before it went into the Journal

-- The sets view pins its strata to the window's when it's made; keep it with the window's.
local function matchSets()
    if TransmogSetsFrame then
        TransmogSetsFrame:SetFrameStrata(TransmogFrame:GetFrameStrata())
        TransmogSetsFrame:SetFrameLevel(TransmogFrame:GetFrameLevel() + 2)
    end
end

-- Scales the window to the biggest size whose content fits the panel and centres that content.
-- SetPoint offsets are in the window's own (scaled) units, so the centring offset is too.
local function fit(panel)
    local left, top, right, bottom = 0, 0, FRAME_W, FRAME_H
    if bare then left, top, right, bottom = BARE_LEFT, BARE_TOP, BARE_RIGHT, BARE_BOTTOM end
    local w, h = panel:GetWidth() or 0, panel:GetHeight() or 0
    local scale = 1
    if w > 0 and h > 0 then
        scale = math.min((w - 2 * FIT_MARGIN) / (right - left), (h - 2 * FIT_MARGIN) / (bottom - top), MAX_SCALE)
        if scale <= 0 then scale = 1 end
    end
    TransmogFrame:SetScale(scale)
    TransmogFrame:ClearAllPoints()
    TransmogFrame:SetPoint("CENTER", panel, "CENTER",
        FRAME_W / 2 - (left + right) / 2, (top + bottom) / 2 - FRAME_H / 2)
end

local function dock(panel)
    if docked then return end
    docked = true
    local point, relativeTo, relativePoint, x, y = TransmogFrame:GetPoint(1)
    saved = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y,
        strata = TransmogFrame:GetFrameStrata(), level = TransmogFrame:GetFrameLevel(),
        scale = TransmogFrame:GetScale() }
    TransmogFrame:SetParent(panel)
    bare = Transmog.SetDockedChrome and Transmog.SetDockedChrome(true) or false
    fit(panel)
    -- Bare, its empty top edge overlaps the Journal's title bar; let clicks there reach it.
    if bare then TransmogFrame:EnableMouse(false) end
    TransmogFrame:SetFrameStrata(panel:GetFrameStrata())
    TransmogFrame:SetFrameLevel(panel:GetFrameLevel() + 5)
    matchSets()
    -- Dragging would move it around inside the Journal.
    TransmogFrame:RegisterForDrag()
end

local function undock()
    if not docked then return end
    docked = false
    if bare then
        Transmog.SetDockedChrome(false)
        TransmogFrame:EnableMouse(true)
        bare = false
    end
    TransmogFrame:SetParent(UIParent)
    TransmogFrame:SetScale(saved and saved.scale or 1)
    TransmogFrame:ClearAllPoints()
    if saved and saved.point and saved.relativeTo ~= nil and saved.relativeTo ~= TransmogFrame then
        TransmogFrame:SetPoint(saved.point, saved.relativeTo, saved.relativePoint, saved.x, saved.y)
    elseif saved and saved.point then
        TransmogFrame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        TransmogFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    TransmogFrame:SetFrameStrata(saved and saved.strata or "MEDIUM")
    if saved and saved.level then TransmogFrame:SetFrameLevel(saved.level) end
    matchSets()
    TransmogFrame:RegisterForDrag("LeftButton")
end

Journal.RegisterTab({
    key = "appearances",
    name = "Appearances",
    order = 70,
    icon = "Interface\\Icons\\INV_Chest_Cloth_17",
    build = function (panel)
        -- The first open docks before the panel's anchors have resolved, when it still reads 0 wide
        -- and fit() falls back to scale 1; this fits it once the panel has its real size.
        panel:HookScript("OnSizeChanged", function (self)
            if docked then fit(self) end
        end)
        status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        status:SetPoint("CENTER", panel, "CENTER", 0, 0)
        status:SetWidth(460)
    end,
    onShow = function (panel)
        dock(panel)
        if TransmogFrame:IsShown() then
            status:SetText("")
        else
            status:SetText("Opening your appearances...\n\n|cff9d9d9dIf nothing opens, this realm only lets you change appearances at a Transmogrifier.|r")
            SendAddonMessage(Transmog.prefix, "RequestPortable", "WHISPER", UnitName("player"))
        end
    end,
    onHide = function ()
        if docked and TransmogFrame:IsShown() then TransmogFrame:Hide() end
        undock()
    end,
})

-- Without its own frame the window no longer covers the panel, so the waiting text goes once it opens.
TransmogFrame:HookScript("OnShow", function ()
    if docked and status then status:SetText("") end
end)

-- Closing the transmog window while it's in the Journal leaves the tab with a way back.
TransmogFrame:HookScript("OnHide", function ()
    if docked and status then
        status:SetText("The transmog window is closed.\n\n|cff9d9d9dClick the Appearances tab again to open it.|r")
    end
end)
