local Transmog = _G.Transmog

-- Key Bindings > Transmog > Open/close Transmog (Bindings.xml).
BINDING_HEADER_TRANSMOG = "Transmog"
BINDING_NAME_TRANSMOG_TOGGLE = "Open/close Transmog"

-- Opens the transmog window anywhere (if the realm allows it), or closes it.
function Transmog_Toggle()
    if TransmogFrame:IsVisible() then
        TransmogFrame:Hide()
    else
        SendAddonMessage(Transmog.prefix, "RequestPortable", "WHISPER", UnitName("player"))
    end
end

-- /transmog toggles the window; /transmog anchor shows the new-appearance alert anchor window.
SLASH_TRANSMOG1 = "/transmog"
SlashCmdList["TRANSMOG"] = function(cmd)
    if cmd and strlower(strtrim(cmd)) == "anchor" then
        Transmog.newTransmogAlert:ShowAnchor()
    else
        Transmog_Toggle()
    end
end

-- Toggles debug mode on/off.
SLASH_TRANSMOGDEBUG1 = "/transmogdebug"
SlashCmdList["TRANSMOGDEBUG"] = function(cmd)
    if cmd then
        if Transmog.debug then
            Transmog.debug = false
            twfprint("Transmog debug off")
        else
            Transmog.debug = true
            twfprint("Transmog debug on")
        end
    end
end

-- Registers TransmogFrame for ESC key handling (we hide GossipFrame and
-- replace it with our own frame, so Blizzard's default ESC logic needs this).
if not UISpecialFrames then
    UISpecialFrames = {}
end
tinsert(UISpecialFrames, "TransmogFrame")
