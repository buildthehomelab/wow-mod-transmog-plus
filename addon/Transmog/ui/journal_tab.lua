-- The Journal's Appearances tab. With the Journal addon (mod-forever-journal) installed, the
-- transmog window opens inside the Journal's window as one of its tabs, through the same
-- "open anywhere" request /transmog uses (Transmog.OpenAnywhere on the server). Leaving the tab
-- or closing the Journal puts the window back where it was, so the NPC and /transmog work as before.
-- Loaded after transmog.xml: it needs TransmogFrame.

local Transmog = _G.Transmog

if not (Journal and Journal.RegisterTab and (Journal.API or 0) >= 1 and TransmogFrame) then return end

local docked = false
local status
local saved -- where the window was before it went into the Journal

-- The sets view pins its strata to the window's when it's made; keep it with the window's.
local function matchSets()
    if TransmogSetsFrame then
        TransmogSetsFrame:SetFrameStrata(TransmogFrame:GetFrameStrata())
        TransmogSetsFrame:SetFrameLevel(TransmogFrame:GetFrameLevel() + 2)
    end
end

local function dock(panel)
    if docked then return end
    docked = true
    local point, relativeTo, relativePoint, x, y = TransmogFrame:GetPoint(1)
    saved = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y,
        strata = TransmogFrame:GetFrameStrata(), level = TransmogFrame:GetFrameLevel() }
    TransmogFrame:SetParent(panel)
    TransmogFrame:ClearAllPoints()
    TransmogFrame:SetPoint("CENTER", panel, "CENTER", 0, 0)
    TransmogFrame:SetFrameStrata(panel:GetFrameStrata())
    TransmogFrame:SetFrameLevel(panel:GetFrameLevel() + 5)
    matchSets()
    -- Dragging would move it around inside the Journal.
    TransmogFrame:RegisterForDrag()
end

local function undock()
    if not docked then return end
    docked = false
    TransmogFrame:SetParent(UIParent)
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
        status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        status:SetPoint("CENTER", panel, "CENTER", 0, 0)
        status:SetWidth(460)
    end,
    onShow = function (panel)
        status:SetText("Opening your appearances...\n\n|cff9d9d9dIf nothing opens, this realm only lets you change appearances at a Transmogrifier.|r")
        dock(panel)
        if not TransmogFrame:IsShown() then
            SendAddonMessage(Transmog.prefix, "RequestPortable", "WHISPER", UnitName("player"))
        end
    end,
    onHide = function ()
        if docked and TransmogFrame:IsShown() then TransmogFrame:Hide() end
        undock()
    end,
})

-- Closing the transmog window while it's in the Journal leaves the tab with a way back.
TransmogFrame:HookScript("OnHide", function ()
    if docked and status then
        status:SetText("The transmog window is closed.\n\n|cff9d9d9dClick the Appearances tab again to open it.|r")
    end
end)
