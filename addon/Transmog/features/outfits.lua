local Transmog = _G.Transmog
local TransmogFrame_Find = string.find

-- Populates the outfits dropdown menu with all saved outfits.
function OutfitsDropDown_Initialize()

    for name, data in pairs(transmogOutfits) do
        local info = {}
        info.text = name
        info.value = 1
        info.arg1 = name
        info.checked = Transmog.currentOutfit == name
        info.func = Transmog_LoadOutfit
        info.tooltipTitle = name
        local descText = ''
        for slot, itemID in pairs(data) do
            if itemID == 0 then
            else
				Transmog:cacheItem(itemID)
                local n, _, quality, _, _, _, _, _, equip_slot = GetItemInfo(itemID)

                if quality == nil then quality = 0 end

                if n == nil then n = "error" end

                local _, _, _, color = GetItemQualityColor(quality)

                descText = descText .. FONT_COLOR_CODE_CLOSE .. color .. n .. "\n"
            end
        end
        info.tooltipText = descText
        UIDropDownMenu_AddButton(info)
    end

    if Transmog:tableSize(transmogOutfits) < 20 then
        local _, _, _, color = GetItemQualityColor(2)

        local newOutfit = {}
        newOutfit.text = color .. "+ New Outfit"
        newOutfit.value = 1
        newOutfit.arg1 = 1
        newOutfit.checked = false
        newOutfit.func = Transmog_NewOutfitPopup
        UIDropDownMenu_AddButton(newOutfit)
    end

end

-- Uses the server-filtered appearance bucket to keep saved outfits aligned with
-- the active transmog configuration and the item currently equipped in a slot.
function Transmog:IsOutfitAppearanceCompatible(slot, itemID)
    if itemID == 0 then
        return true
    end

    if itemID == self.HIDDEN_ITEM_ID then
        return self.hideableSlots[slot] == true
    end

    local equippedLink = GetInventoryItemLink('player', slot)
    if not equippedLink then
        return false
    end

    local _, _, _, _, _, itemClass, itemSubclass = GetItemInfo(equippedLink)
    if not itemClass or not itemSubclass then
        return false
    end

    local bucket = self:ItemClassStrToNum(itemClass) + self:ItemSubclassStrToNum(itemSubclass)
    local slotData = self.transmogDataFromServer[slot]
    local appearances = slotData and slotData[bucket]
    if not appearances then
        return false
    end

    for _, appearanceID in ipairs(appearances) do
        if tonumber(appearanceID) == itemID then
            return true
        end
    end

    return false
end

-- Loads a saved outfit's transmog selections onto all equipment slots.
function Transmog_LoadOutfit(self, outfit)
    UIDropDownMenu_SetText(TransmogFrameOutfits, outfit)

    Transmog.currentOutfit = outfit

    Transmog:EnableOutfitSaveButton()

    TransmogFrameDeleteOutfit:Enable()

    Transmog:hideItemBorders()

    for slot, itemID in pairs(transmogOutfits[outfit]) do

        if not Transmog:IsOutfitAppearanceCompatible(slot, itemID) then
            twfdebug("Skipping incompatible outfit appearance " .. itemID .. " for slot " .. slot)
        else

        local eq_slot, tex
        local hasItemEquipped = false

        if GetInventoryItemLink('player', slot) then
            hasItemEquipped = true
        end

        if hasItemEquipped then

            if itemID == 0 then
                local _, _, eqItemLink = TransmogFrame_Find(GetInventoryItemLink('player', slot), "(item:%d+:%d+:%d+:%d+)");
                local _, _, _, _, _, _, _, _, equip_slot, outfitTex = GetItemInfo(eqItemLink)
                eq_slot = equip_slot
                tex = outfitTex
            else
                local _, _, _, _, _, _, _, _, equip_slot, outfitTex = GetItemInfo(itemID)
                eq_slot = equip_slot
                tex = outfitTex
            end

            local frame

            frame = Transmog:frameFromInvType(eq_slot, slot)

            if hasItemEquipped then
                TransmogFramePlayerModel:TryOn(itemID)
            end

            if frame then

                getglobal(frame:GetName() .. "ItemIcon"):SetTexture(tex)

                if Transmog.transmogStatusToServer[slot] ~= itemID then
                    getglobal(frame:GetName() .. 'BorderHi'):Show()
                    getglobal(frame:GetName() .. 'AutoCast'):SetAlpha(0.3)
                end

                if itemID == 0 or not hasItemEquipped then
                    getglobal(frame:GetName() .. 'BorderHi'):Hide()
                    getglobal(frame:GetName() .. 'AutoCast'):Hide()
                end

            end

            Transmog.transmogStatusToServer[slot] = itemID
            if frame then
                Transmog:UpdateSlotGlow(frame:GetName(), slot)
            end
        end

        end

    end
    Transmog:calculateCost()
end

-- Outfits live on the server, account-wide. transmogOutfits mirrors the server copy once it has
-- answered, so the dropdown keeps working against an older server that never answers.

-- Encodes an outfit as "slot,item;slot,item" for the server.
function Transmog:EncodeOutfit(data)
    local parts = {}
    for slot, itemID in pairs(data) do
        table.insert(parts, slot .. "," .. itemID)
    end
    return table.concat(parts, ";")
end

function Transmog:DecodeOutfit(text)
    local data = {}
    for slot, itemID in string.gmatch(text or "", "(%d+),(%d+)") do
        data[tonumber(slot)] = tonumber(itemID)
    end
    return data
end

-- Sends one outfit to the server (no-op until the server has answered GetOutfits).
function Transmog:PushOutfit(name)
    if self.outfitsFromServer and transmogOutfits[name] then
        SendAddonMessage(self.prefix, "SaveOutfit:" .. self:EncodeOutfit(transmogOutfits[name]) .. ":" .. name, "WHISPER", UnitName("player"))
    end
end

function Transmog:DeleteOutfitOnServer(name)
    if self.outfitsFromServer then
        SendAddonMessage(self.prefix, "DeleteOutfit:" .. name, "WHISPER", UnitName("player"))
    end
end

function Transmog:OnOutfitsStart()
    self.incomingOutfits = {}
end

function Transmog:OnOutfit(data, name)
    if self.incomingOutfits and name and name ~= "" then
        self.incomingOutfits[name] = self:DecodeOutfit(data)
    end
end

-- The first sync of a character uploads its old per-character outfits; after that the server
-- copy wins, so an outfit deleted on one character stays deleted on the others.
function Transmog:OnOutfitsEnd()
    local serverOutfits = self.incomingOutfits or {}
    self.incomingOutfits = nil
    self.outfitsFromServer = true

    if not transmogOutfitsSynced then
        for oldName, data in pairs(transmogOutfits or {}) do
            -- Old names may break the server's rules; clean them, and keep both outfits when a
            -- cleaned name collides with a different one already on the account.
            local name = self:CleanOutfitName(oldName)
            if name == "" then
                name = "Outfit"
            end
            local base, n = name, 2
            while serverOutfits[name] and self:EncodeOutfit(serverOutfits[name]) ~= self:EncodeOutfit(data) do
                name = self:CleanOutfitName(base .. " " .. n)
                n = n + 1
            end
            if not serverOutfits[name] then
                serverOutfits[name] = data
                SendAddonMessage(self.prefix, "SaveOutfit:" .. self:EncodeOutfit(data) .. ":" .. name, "WHISPER", UnitName("player"))
            end
        end
        transmogOutfitsSynced = true
    end

    transmogOutfits = serverOutfits
    self:CacheOutfitsItems()
    UIDropDownMenu_Initialize(TransmogFrameOutfits, OutfitsDropDown_Initialize)
end

-- The server refused an outfit (the account is at its outfit limit): drop it from the mirror.
function Transmog:OnOutfitRejected(name)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[Transmog]|r Outfit '" .. name .. "' was not saved: your account has too many outfits. Delete one and save it again.")
    if transmogOutfits[name] then
        transmogOutfits[name] = nil
        if self.currentOutfit == name then
            self.currentOutfit = nil
            UIDropDownMenu_SetText(TransmogFrameOutfits, "Outfits")
        end
        UIDropDownMenu_Initialize(TransmogFrameOutfits, OutfitsDropDown_Initialize)
    end
end

-- Outfit names travel inside addon messages: no escape codes or control characters, and at
-- most 48 bytes, cut on a UTF-8 character boundary.
function Transmog:CleanOutfitName(name)
    name = string.gsub(name or "", "[%c|]", "")
    name = strtrim(name)
    local out = ""
    for char in string.gmatch(name, "[%z\1-\127\194-\244][\128-\191]*") do
        if string.len(out) + string.len(char) > 48 then
            break
        end
        out = out .. char
    end
    return out
end

-- Saves the current transmog selections as a saved outfit.
function Transmog_SaveOutfit()
	transmogOutfits[Transmog.currentOutfit] = {}
    for InventorySlotId, itemID in pairs(Transmog.transmogStatusFromServer) do
        if itemID ~= 0 then
            transmogOutfits[Transmog.currentOutfit][InventorySlotId] = itemID
        end
    end
    for InventorySlotId, itemID in pairs(Transmog.transmogStatusToServer) do
        if itemID ~= 0 then
            transmogOutfits[Transmog.currentOutfit][InventorySlotId] = itemID
        end
    end
    TransmogFrameSaveOutfit:Disable()
    Transmog:PushOutfit(Transmog.currentOutfit)
end

-- Enables the save outfit button when an outfit is currently selected.
function Transmog:EnableOutfitSaveButton()
    if self.currentOutfit ~= nil then
        TransmogFrameSaveOutfit:Enable()
    end
end

-- Deletes the currently selected outfit.
function Transmog_deleteOutfit()
    if not Transmog.currentOutfit then
        return
    end

    local outfitName = Transmog.currentOutfit
    transmogOutfits[outfitName] = nil
    Transmog:DeleteOutfitOnServer(outfitName)
    Transmog.currentOutfit = nil
    TransmogFrameSaveOutfit:Disable()
    TransmogFrameDeleteOutfit:Disable()
    UIDropDownMenu_SetText(TransmogFrameOutfits, "Outfits")
    UIDropDownMenu_Initialize(TransmogFrameOutfits, OutfitsDropDown_Initialize)
    Transmog_revert()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Transmog]|r Outfit '" .. outfitName .. "' deleted.")
end

StaticPopupDialogs["TRANSMOG_NEW_OUTFIT"] = {
    text = "Enter Outfit Name:",
    button1 = "Save",
    button2 = "Cancel",
    hasEditBox = 1,
    OnAccept = function()
        local outfitName = Transmog:CleanOutfitName(getglobal(this:GetParent():GetName() .. "EditBox"):GetText())
        if outfitName == '' then
            StaticPopup_Show('TRANSMOG_OUTFIT_EMPTY_NAME')
            return
        end
        if transmogOutfits[outfitName] then
            StaticPopup_Show('TRANSMOG_OUTFIT_EXISTS')
            return
        end
        transmogOutfits[outfitName] = {}
        UIDropDownMenu_SetText(TransmogFrameOutfits, outfitName)
        Transmog.currentOutfit = outfitName
        Transmog:EnableOutfitSaveButton()
        TransmogFrameDeleteOutfit:Enable()
        Transmog_SaveOutfit()
        UIDropDownMenu_Initialize(TransmogFrameOutfits, OutfitsDropDown_Initialize)
        getglobal(this:GetParent():GetName() .. "EditBox"):SetText('')
    end,
    timeout = 0,
    whileDead = 0,
    hideOnEscape = 1,
};

StaticPopupDialogs["TRANSMOG_OUTFIT_EXISTS"] = {
    text = "Outfit Name already exists.",
    button1 = "Okay",
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1
};

StaticPopupDialogs["TRANSMOG_OUTFIT_EMPTY_NAME"] = {
    text = "Outfit Name not valid.",
    button1 = "Okay",
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1
};

StaticPopupDialogs["CONFIRM_DELETE_OUTFIT"] = {
    text = "Delete Outfit ?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        Transmog_deleteOutfit()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
};

-- Shows the dialog for creating a new outfit.
function Transmog_NewOutfitPopup()
    StaticPopup_Show('TRANSMOG_NEW_OUTFIT')
end
