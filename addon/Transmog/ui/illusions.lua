local Transmog = _G.Transmog

-- Illusions: collected weapon enchant visuals, shown on the main hand (16) or off hand (17).
-- Slots are 1-based like the rest of the addon; the server gets slot - 1.

local NO_TRANSMOGS_TEXT = "You have yet to uncover any kind of appearance for this item. \nAppearances unlock when you loot, buy, craft or equip an item."

local weaponEquipLocs = {
    INVTYPE_WEAPON = true,
    INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
}

function Transmog:IsIllusionSlot(slot)
    return slot == 16 or slot == 17
end

-- Enchant glows only show on melee weapons, not shields, off-hand frills or ranged weapons.
function Transmog:CanSlotHaveIllusion(slot)
    local link = GetInventoryItemLink('player', slot)
    if not link then
        return false
    end
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    return weaponEquipLocs[equipLoc] == true
end

-- The item whose model the slot shows: pending or applied transmog, else the weapon itself.
function Transmog:WeaponLookForSlot(slot)
    local id = self.transmogStatusToServer[slot]
    if not id or id == 0 or id == self.HIDDEN_ITEM_ID then
        id = self.equippedItems[slot]
    end
    return id
end

-- The weapon's own permanent enchant, read from its item link.
function Transmog:RealEnchantForSlot(slot)
    local link = GetInventoryItemLink('player', slot)
    return tonumber(link and string.match(link, "item:%d+:(%d+)")) or 0
end

-- The enchant a slot would show with its pending illusion.
function Transmog:EnchantShownForSlot(slot, illusion)
    illusion = illusion or self.illusionStatusToServer[slot] or 0
    if illusion == self.HIDDEN_ILLUSION_ID then
        return 0
    end
    if illusion == 0 then
        return self:RealEnchantForSlot(slot)
    end
    return illusion
end

function Transmog:WeaponLinkForSlot(slot, enchant)
    local id = self:WeaponLookForSlot(slot)
    if not id or id == 0 then
        return nil
    end
    return "item:" .. id .. ":" .. (enchant or 0) .. ":0:0:0:0:0:0:0"
end

function Transmog:SetIllusionsTabActive(active)
    if not TransmogFrameIllusionsButton then
        return
    end
    local texture = active and 'tab_active' or 'tab_inactive'
    TransmogFrameIllusionsButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\' .. texture)
    TransmogFrameIllusionsButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
    TransmogFrameIllusionsButtonText:SetText((active and HIGHLIGHT_FONT_COLOR_CODE or NORMAL_FONT_COLOR_CODE) .. 'Illusions')
end

-- The Items view reuses the "no appearances" label, so put its own text back.
function Transmog:LeaveIllusionsView()
    self:SetIllusionsTabActive(false)
    TransmogFrameNoTransmogs:SetText(NO_TRANSMOGS_TEXT)
end

function Transmog:OnIllusionsLoaded()
    local names = self.illusionNames
    table.sort(self.illusionIds, function(a, b)
        return (names[a] or "") < (names[b] or "")
    end)
    if self.tab == 'illusions' and TransmogFrame:IsVisible() then
        self:RenderIllusions()
    end
end

-- Keeps pending choices, but follows the server where nothing is pending.
function Transmog:OnIllusionStatus(mainHand, offHand)
    local incoming = { [16] = mainHand or 0, [17] = offHand or 0 }
    for slot, enchant in pairs(incoming) do
        if self.illusionStatusToServer[slot] == self.illusionStatusFromServer[slot] then
            self.illusionStatusToServer[slot] = enchant
        end
        self.illusionStatusFromServer[slot] = enchant
    end
    self:RefreshPendingGlows()
end

local function positionWeaponModel(model, slot, race)
    local Z, X, Y = model:GetPosition()
    if race == 'nightelf' then
        Z = Z + 3
    elseif race == 'troll' then
        Z = Z + 2
    elseif race == 'goblin' then
        Z = Z - 0.5
    end

    if slot == 16 then
        model:SetRotation(0.61)
        if race == 'gnome' then
            Y = Y - 2
        elseif race == 'dwarf' then
            Y = Y - 1
        end
        model:SetPosition(Z + 3.8, X, Y + 0.4)
    else
        model:SetRotation(-0.61)
        model:SetPosition(Z + 3.8, X, Y)
    end
end

-- Grid of illusions for the selected weapon slot: "No illusion" (the weapon's own enchant),
-- "Hide enchant", then every collected illusion by name.
function Transmog:RenderIllusions()
    self:hideItems(true)
    self:hideItemBorders()
    TransmogFrameSplash:Hide()
    TransmogFrameInstructions:Hide()
    TransmogFrameNoTransmogs:Hide()

    local slot = self.currentTransmogSlot
    TransmogFrameCollectedCollectedStatus:SetText("Illusions: " .. table.getn(self.illusionIds))

    if not slot or not self:IsIllusionSlot(slot) or not self:CanSlotHaveIllusion(slot) then
        self:hidePagination()
        TransmogFrameNoTransmogs:SetText("Select your main hand or off hand weapon to choose its illusion.\nIllusions unlock when you enchant a weapon.")
        TransmogFrameNoTransmogs:Show()
        return
    end

    local entries = {
        { id = 0, name = "No illusion", hint = "Show the weapon's own enchant." },
        { id = self.HIDDEN_ILLUSION_ID, name = "Hide enchant", hint = "Show no enchant glow at all." },
    }
    for _, id in ipairs(self.illusionIds) do
        table.insert(entries, { id = id, name = self.illusionNames[id] or ("Illusion #" .. id) })
    end

    local total = table.getn(entries)
    self.totalPages = math.max(1, self:ceil(total / self.ipp))
    if self.currentPage > self.totalPages then
        self.currentPage = self.totalPages
    end

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
            if entry.id == (self.illusionStatusToServer[slot] or 0) then
                button:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\item_bg_selected')
            else
                button:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\item_bg_normal')
            end
            AddButtonOnEnterTextTooltip(button, "|cffff80ff" .. entry.name, entry.hint)

            frame:Show()

            local model = getglobal('TransmogLook' .. itemIndex .. 'ItemModel')
            model:SetUnit("player")
            positionWeaponModel(model, slot, self.race)
            model:Undress()
            local link = self:WeaponLinkForSlot(slot, self:EnchantShownForSlot(slot, entry.id))
            if link then
                model:TryOn(link)
            end

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

-- Stages an illusion for the selected weapon slot; Apply sends it.
function Transmog:TryIllusion(enchant)
    local slot = self.currentTransmogSlot
    if not slot or not self:IsIllusionSlot(slot) then
        return
    end

    self.illusionStatusToServer[slot] = enchant
    self:RenderIllusions()
    if self.currentTransmogSlotName then
        self:UpdateSlotGlow(self.currentTransmogSlotName, slot)
    end
    self:RefreshPreviewModel()
    self:calculateCost()
end

-- Selects a weapon slot while the Illusions tab is open (defaults to the main hand).
function Transmog:ShowIllusionsView()
    if not (self.currentTransmogSlot and self:IsIllusionSlot(self.currentTransmogSlot)) then
        if MainHandSlotNoEquip and not MainHandSlotNoEquip:IsVisible() then
            self.currentTransmogSlot = 16
            self.currentTransmogSlotName = 'MainHandSlot'
        else
            self.currentTransmogSlot = nil
            self.currentTransmogSlotName = nil
        end
    end

    self:hidePlayerItemsBorders()
    if self.currentTransmogSlotName then
        getglobal(self.currentTransmogSlotName .. 'BorderSelected'):Show()
    end
    self.currentPage = 1
    self:RenderIllusions()
end

function Transmog:ApplyIllusionResult(success, serverSlot, enchant)
    local slot = (serverSlot or -1) + 1
    if not self:IsIllusionSlot(slot) then
        slot = nil
    end

    if success == 1 and slot then
        self.illusionStatusFromServer[slot] = enchant
        self.illusionStatusToServer[slot] = enchant
        if enchant == 0 then
            self:addTransmogAnim(slot, 'reset')
        else
            self:addTransmogAnim(slot)
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[Transmog]|r Failed to apply the illusion (not collected, not a weapon, or not enough money).")
        for s, value in pairs(self.illusionStatusFromServer) do
            self.illusionStatusToServer[s] = value
        end
    end

    self:RefreshPendingGlows()

    if self.pendingApplyCount and self.pendingApplyCount > 0 then
        self.pendingApplyCount = self.pendingApplyCount - 1
    else
        self.pendingApplyCount = 0
    end

    if self.pendingApplyCount <= 0 then
        if success == 1 then
            PlaySoundFile("Interface\\AddOns\\Transmog\\assets\\ui_transmogrify_apply.ogg", "Dialog")
        end
        self:transmogStatus()
        self:calculateCost()
    end
end
