local Transmog = _G.Transmog

-- 3D previews in the Forms and Backpacks tiles (and the big model in the Forms tab).
-- A 3.3.5 model frame shows a creature only once the client has it cached, and loads a model
-- file in the background, so a preview is re-set until the frame reports a model (GetModel),
-- then framed. The model sits on a layer above the tile's button: the button's background is
-- opaque, and anything on the tile frame itself draws under it.

local LIGHT = { 1, 0, 0, -0.707, -0.707, 0.7, 1.0, 1.0, 1.0, 0.8, 1.0, 1.0, 0.8 }
local DARK = { 1, 0, 0, -0.707, -0.707, 0, 0, 0, 0, 0, 0, 0, 0 }
local RETRY_EVERY = 0.4
local MAX_TRIES = 30 -- 12 seconds

-- Framing per tab: model scale, then SetPosition's depth (toward the camera), side and height.
-- /transmog tilecam changes it for the session, to find better numbers.
Transmog.tileCamera = {
    forms = { 1, 0, 0, 0 },
    backpacks = { 1, 0, 0, 0 },
}

local function loaded(model)
    local file = model:GetModel()
    return type(file) == "string" and file ~= ""
end

local function frameModel(model)
    local cam = model.cameraKey and Transmog.tileCamera[model.cameraKey]
    if cam then
        model:SetModelScale(cam[1])
        model:SetPosition(cam[2], cam[3], cam[4])
    end
    model:SetFacing(model.facing or 0.6)
    if model.cameraKey then
        model:SetLight(unpack(model.locked and DARK or LIGHT))
    end
end

local function load(model)
    if model.want.creature then
        model:SetCreature(model.want.creature)
    else
        model:SetModel(model.want.file)
    end
end

local loader = CreateFrame("Frame")
loader:Hide()
loader.pending = {}
loader.wait = 0
loader.reported = {}
loader:SetScript("OnUpdate", function(self, elapsed)
    self.wait = self.wait - elapsed
    if self.wait > 0 then
        return
    end
    self.wait = RETRY_EVERY
    local left = false
    for model in pairs(self.pending) do
        if not model:IsVisible() or not model.want then
            self.pending[model] = nil
        elseif loaded(model) then
            frameModel(model)
            self.pending[model] = nil
        else
            model.tries = model.tries + 1
            if model.tries > MAX_TRIES then
                self.pending[model] = nil
                if model.onFail then
                    model.onFail(model)
                end
                if not self.reported.any then
                    self.reported.any = true
                    local what = model.want.creature and ("creature " .. model.want.creature) or model.want.file
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff80ff[Transmog]|r A preview didn't load (" .. tostring(what)
                        .. "). Is the realm's client patch installed?")
                end
            else
                load(model)
                left = true
            end
        end
    end
    if not left and not next(self.pending) then
        self:Hide()
    end
end)

-- Shows a creature ({ creature = entry }) or a model file ({ file = path }) in a model frame.
-- cameraKey picks the framing (nil: leave the frame's own); onFail runs if it never loads.
function Transmog:ShowPreview(model, want, cameraKey, locked, onFail)
    local key = want.creature or want.file
    model.cameraKey = cameraKey
    model.locked = locked
    model.onFail = onFail
    if model.wantKey ~= key then
        model.wantKey = key
        model.want = want
        model.tries = 0
        model:ClearModel()
        load(model)
    end
    if loaded(model) then
        frameModel(model)
    else
        loader.pending[model] = true
        loader:Show()
    end
end

function Transmog:ForgetPreview(model)
    model.want = nil
    model.wantKey = nil
    loader.pending[model] = nil
end

-- The preview layer of a tile: a model and an icon above its button.
function Transmog:TilePreview(frame, button)
    if not frame.tileModel then
        local layer = CreateFrame("Frame", nil, frame)
        layer:SetAllPoints(button)
        layer:SetFrameLevel(button:GetFrameLevel() + 2)
        layer:EnableMouse(false)
        local model = CreateFrame("PlayerModel", nil, layer)
        model:SetWidth(76)
        model:SetHeight(96)
        model:SetPoint("CENTER", button, "CENTER", 0, 0)
        model:SetFrameLevel(layer:GetFrameLevel() + 1)
        model:EnableMouse(false)
        local icon = layer:CreateTexture(nil, "OVERLAY")
        icon:SetWidth(48)
        icon:SetHeight(48)
        icon:SetPoint("CENTER", button, "CENTER", 0, 4)
        frame.tileModel, frame.tileIcon = model, icon
    end
    return frame.tileModel, frame.tileIcon
end

function Transmog:HideTilePreviews()
    for _, frame in pairs(self.ItemButtons) do
        if frame.tileModel then
            self:ForgetPreview(frame.tileModel)
            frame.tileModel:Hide()
            frame.tileIcon:Hide()
        end
    end
end

-- /transmog tilecam <scale> <depth> <side> <height>: frames the Forms or Backpacks tiles
-- (whichever tab is open) for this session.
function Transmog:TileCameraCommand(args)
    local key = self.tab
    if not self.tileCamera[key] or not TransmogFrame:IsVisible() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff80ff[Transmog]|r Open the Forms or Backpacks tab first.")
        return
    end
    local vals = {}
    for v in string.gmatch(args or "", "%S+") do
        table.insert(vals, tonumber(v))
    end
    local cam = self.tileCamera[key]
    for i = 1, 4 do
        if vals[i] then
            cam[i] = vals[i]
        end
    end
    for _, frame in pairs(self.ItemButtons) do
        if frame.tileModel and frame.tileModel:IsVisible() then
            frameModel(frame.tileModel)
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff80ff[Transmog]|r %s tiles: scale %.2f, depth %.2f, side %.2f, height %.2f",
        key, cam[1], cam[2], cam[3], cam[4]))
end
