local Transmog = _G.Transmog
local TransmogFrame_Find = string.find
local TransmogFrame_ToNumber = tonumber

-- Maps an inventory type string to the corresponding slot frame.
function Transmog:frameFromInvType(invType, clientSlot)

    if invType == 'INVTYPE_WEAPON' and clientSlot == 17 then
        return SecondaryHandSlot
    end

    if invType == 'INVTYPE_HEAD' then
        return HeadSlot
    end
    if invType == 'INVTYPE_SHOULDER' then
        return ShoulderSlot
    end
    if invType == 'INVTYPE_CLOAK' then
        return BackSlot
    end
    if invType == 'INVTYPE_CHEST' or invType == 'INVTYPE_ROBE' then
        return ChestSlot
    end
    if invType == 'INVTYPE_BODY' then
        return ShirtSlot
    end
    if invType == 'INVTYPE_TABARD' then
        return TabardSlot
    end
    if invType == 'INVTYPE_WRIST' then
        return WristSlot
    end
    if invType == 'INVTYPE_HAND' then
        return HandsSlot
    end
    if invType == 'INVTYPE_WAIST' then
        return WaistSlot
    end
    if invType == 'INVTYPE_LEGS' then
        return LegsSlot
    end
    if invType == 'INVTYPE_FEET' then
        return FeetSlot
    end

    if invType == 'INVTYPE_WEAPONMAINHAND' or
            invType == 'INVTYPE_2HWEAPON' or
            invType == 'INVTYPE_WEAPON' or
            invType == 'INVTYPE_WEAPONMAINHAND'
    then
        return MainHandSlot
    end
    if invType == 'INVTYPE_WEAPONOFFHAND' or
            invType == 'INVTYPE_HOLDABLE' or
            invType == 'INVTYPE_SHIELD'
    then
        return SecondaryHandSlot
    end
    if invType == 'INVTYPE_RANGED' or
            invType == 'INVTYPE_RANGEDRIGHT' then
        return RangedSlot
    end
    return nil
end

-- Rebuilds the character preview model from scratch, skipping the Hidden
-- sentinel. DressUpModel has no per-slot TryOff, so we must Undress/re-TryOn.
function Transmog:RefreshPreviewModel()
    TransmogFramePlayerModel:Undress()
    for _, InventorySlotId in pairs(self.inventorySlots) do
        local effective = self.transmogStatusToServer[InventorySlotId]
        if not effective or effective == 0 then
            effective = self.equippedItems[InventorySlotId]
        end
        if effective and effective ~= 0 and effective ~= Transmog.HIDDEN_ITEM_ID then
            if self:IsIllusionSlot(InventorySlotId) then
                TransmogFramePlayerModel:TryOn("item:" .. effective .. ":" .. self:EnchantShownForSlot(InventorySlotId) .. ":0:0:0:0:0:0:0")
            else
                TransmogFramePlayerModel:TryOn(effective)
            end
        end
    end
end

-- Previews a transmog appearance on the selected equipment slot.
function Transmog_Try(itemId, slotName, newReset)
	twfdebug("Transmog_Try itemID: " .. itemId .. "slotName: " .. slotName)

    if Transmog.tab == 'illusions' and not newReset then
        Transmog:TryIllusion(itemId)
        return true
    end

    if Transmog.tab == 'backpacks' and not newReset then
        Transmog:TryBackpack(itemId)
        return true
    end

    if not newReset and Transmog.tab == 'items' then
        if IsModifiedClick("CHATLINK") and Transmog:LinkLook(itemId) then
            return true
        end
        if Transmog.showMissing then
            Transmog:PreviewMissing(itemId)
            return true
        end
    end

    if newReset and getglobal(slotName .. "NoEquip"):IsVisible() then
        return false
    end

    Transmog:hideItemBorders()

    if newReset then
        local InventorySlotId = Transmog.inventorySlots[slotName]

        itemId = Transmog:IDFromLink(GetInventoryItemLink('player', InventorySlotId))

        Transmog.transmogStatusToServer[InventorySlotId] = 0

        getglobal(slotName .. 'AutoCast'):Hide()

        if Transmog.transmogStatusFromServer[InventorySlotId] ~= Transmog.transmogStatusToServer[InventorySlotId] then
            getglobal(slotName .. 'BorderHi'):Show()
            getglobal(slotName .. 'AutoCast'):SetAlpha(0.3)
        else
            getglobal(slotName .. 'BorderHi'):Hide()
        end
        Transmog:UpdateSlotGlow(slotName, InventorySlotId)

        Transmog:RefreshPreviewModel()

        Transmog:cacheItem(itemId)
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)

        getglobal(slotName .. "ItemIcon"):SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")

        AddButtonOnEnterTooltipFashion(getglobal(slotName), GetInventoryItemLink('player', InventorySlotId))

        local _, _, eqItemLink = TransmogFrame_Find(GetInventoryItemLink('player', InventorySlotId), "(item:%d+:%d+:%d+:%d+)");
        local eName = GetItemInfo(eqItemLink)

        Transmog.equippedTransmogs[eName] = nil

        Transmog:calculateCost()
        Transmog:EnableOutfitSaveButton()

        return true
    end

    if itemId == Transmog:IDFromLink(GetInventoryItemLink('player', Transmog.currentTransmogSlot)) then
        getglobal(Transmog.currentTransmogSlotName .. 'BorderHi'):Hide()
        Transmog.transmogStatusToServer[Transmog.currentTransmogSlot] = 0
    else
        getglobal(Transmog.currentTransmogSlotName .. 'BorderHi'):Show()
        Transmog.transmogStatusToServer[Transmog.currentTransmogSlot] = itemId
    end

    Transmog:UpdateSlotGlow(Transmog.currentTransmogSlotName, Transmog.currentTransmogSlot)

    for itemIndex, data in ipairs(Transmog.ItemButtons) do
        getglobal('TransmogLook' .. itemIndex .. 'Button'):SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\item_bg_normal')
        if data.id == itemId then
            getglobal('TransmogLook' .. itemIndex .. 'Button'):SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\item_bg_selected')
        end
        -- The item's own look offers a revert only while something else is staged.
        if data.reset then
            if Transmog.transmogStatusToServer[Transmog.currentTransmogSlot] ~= 0 then
                getglobal('TransmogLook' .. itemIndex .. 'ButtonRevert'):Show()
            else
                getglobal('TransmogLook' .. itemIndex .. 'ButtonRevert'):Hide()
            end
        end
    end

    getglobal(Transmog.currentTransmogSlotName .. 'AutoCast'):Hide()

    if Transmog.transmogStatusFromServer[Transmog.currentTransmogSlot] ~= Transmog.transmogStatusToServer[Transmog.currentTransmogSlot] then
        getglobal(Transmog.currentTransmogSlotName .. 'AutoCast'):SetAlpha(0.3)
    end

    Transmog:RefreshPreviewModel()

    local tex
    if itemId == Transmog.HIDDEN_ITEM_ID then
        tex = nil
    else
        Transmog:cacheItem(itemId)
        local _
        _, _, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
    end

    twfdebug("Transmog_Try itemIcon target: [" .. tostring(Transmog.currentTransmogSlotName) .. "ItemIcon] tex: " .. tostring(tex))
    getglobal(Transmog.currentTransmogSlotName .. "ItemIcon"):SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    twfdebug("Transmog_Try overlay check NoEquip: " .. tostring(getglobal(Transmog.currentTransmogSlotName .. "NoEquip"):IsVisible())
        .. " BorderHi: " .. tostring(getglobal(Transmog.currentTransmogSlotName .. "BorderHi"):IsVisible())
        .. " AutoCast: " .. tostring(getglobal(Transmog.currentTransmogSlotName .. "AutoCast"):IsVisible())
        .. " IconAlpha: " .. tostring(getglobal(Transmog.currentTransmogSlotName .. "ItemIcon"):GetAlpha()))

    Transmog:calculateCost()

    Transmog:EnableOutfitSaveButton()

end

-- Hides the pagination arrow and page text controls.
function Transmog:hidePagination()
    TransmogFrameLeftArrow:Hide()
    TransmogFrameRightArrow:Hide()
    TransmogFramePageText:Hide()
end

-- Shows the pagination arrow and page text controls.
function Transmog:showPagination()
    TransmogFrameLeftArrow:Show()
    TransmogFrameRightArrow:Show()
    TransmogFramePageText:Show()
end

-- Hides all transmog item buttons, optionally using the button's own Hide method.
function Transmog:hideItems(hideButton)
    for index, button in ipairs(self.ItemButtons) do
        -- The Illusions tab reuses these tiles; a missing look's shade must not follow.
        if button.missingShade then
            button.missingShade:Hide()
        end
		if hideButton then
			button:Hide()
		else
			getglobal('TransmogLook' .. index):Hide()
		end
    end
end

-- Resets all item button border textures to the normal state.
function Transmog:hideItemBorders()
    for index, _ in ipairs(self.ItemButtons) do
        getglobal('TransmogLook' .. index .. 'Button'):SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\item_bg_normal')
	end
end

-- Selects a gear slot and displays available transmog options for it.
function selectTransmogSlot(InventorySlotId, slotName)

    -- Weapon slots stay on the Illusions tab; any other slot goes back to Items.
    if Transmog.tab == 'illusions' and InventorySlotId ~= -1 then
        if Transmog:IsIllusionSlot(InventorySlotId) and not getglobal(slotName .. "NoEquip"):IsVisible() then
            Transmog.currentTransmogSlot = InventorySlotId
            Transmog.currentTransmogSlotName = slotName
            Transmog:ShowIllusionsView()
            return true
        end

        Transmog.tab = 'items'
        Transmog:LeaveIllusionsView()
        TransmogFrameItemsButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
        TransmogFrameItemsButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
        TransmogFrameItemsButtonText:SetText(HIGHLIGHT_FONT_COLOR_CODE .. 'Items')
    end

    if Transmog.tab == 'backpacks' and InventorySlotId ~= -1 then
        Transmog.tab = 'items'
        Transmog:LeaveBackpacksView()
        TransmogFrameItemsButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
        TransmogFrameItemsButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
        TransmogFrameItemsButtonText:SetText(HIGHLIGHT_FONT_COLOR_CODE .. 'Items')
    end

    if Transmog.tab == 'sets' and InventorySlotId ~= -1 then
        Transmog.tab = 'items'
        TransmogFrameItemsButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
        TransmogFrameItemsButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
        TransmogFrameItemsButtonText:SetText(HIGHLIGHT_FONT_COLOR_CODE .. 'Items')

        if TransmogFrameSetsButton then
            TransmogFrameSetsButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\tab_inactive')
            TransmogFrameSetsButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
            TransmogFrameSetsButtonText:SetText(NORMAL_FONT_COLOR_CODE .. 'Sets')
        end

        if TransmogSetsFrame then
            TransmogSetsFrame:Hide()
        end

        TransmogFrameCollected:Show()
    end

    TransmogFrameNoTransmogs:Hide()

    if InventorySlotId == -1 then
        Transmog:hidePlayerItemsBorders()
        Transmog:HidePlayerItemsAnimation()
        Transmog:hideItems(true)
        Transmog:hideItemBorders()
        Transmog:hidePagination()
        TransmogFrameSplash:Show()
        TransmogFrameInstructions:Show()
        TransmogFrameCollected:Hide()
        TransmogFrameFilters:Hide()
        Transmog.currentTransmogSlotName = nil
        Transmog.currentTransmogSlot = nil
		Transmog.currentTransmogItemClass = nil
        return true
    end

    if getglobal(slotName .. "NoEquip"):IsVisible() then
        return false
    end

    TransmogFrameSplash:Hide()
    TransmogFrameInstructions:Hide()

    Transmog.currentPage = 1
    Transmog.currentTransmogSlotName = slotName
    Transmog.currentTransmogSlot = InventorySlotId

    if not GetInventoryItemLink('player', Transmog.currentTransmogSlot) then
        selectTransmogSlot(-1)
        return
    end

    local _, _, eqItemLink = TransmogFrame_Find(GetInventoryItemLink('player', Transmog.currentTransmogSlot), "(item:%d+:%d+:%d+:%d+)");
    local itemName, _, _, _, _, itemClass, itemSubclass, _, invType = GetItemInfo(eqItemLink)

    local eqItemId = Transmog:IDFromLink(eqItemLink)

    Transmog:RefreshPreviewModel()

    Transmog:hideItems(false)
    Transmog:hidePlayerItemsBorders()

	Transmog.currentTransmogItemClass = Transmog:ItemClassStrToNum(itemClass) + Transmog:ItemSubclassStrToNum(itemSubclass)

    Transmog:renderAvailableTransmogs(Transmog.currentTransmogSlot, Transmog.currentTransmogItemClass)
end

-- Initializes the character preview model with default rotation.
function TransmogModel_OnLoad()
    TransmogFramePlayerModel.rotation = 0.61;
    TransmogFramePlayerModel:SetRotation(TransmogFramePlayerModel.rotation);
end

-- Navigates between pages of transmog options or outfit tabs.
function Transmog_ChangePage(dir)
    if Transmog.tab == 'items' then
        if not Transmog.currentTransmogSlot or not Transmog.currentTransmogItemClass then
            return
        end

        local totalPages = math.max(1, Transmog.totalPages or 1)
        local nextPage = math.max(1, math.min(Transmog.currentPage + dir, totalPages))
        if nextPage ~= Transmog.currentPage then
            PlaySound("igAbiliityPageTurn")
        end

        Transmog.currentPage = nextPage
        Transmog:renderAvailableTransmogs(Transmog.currentTransmogSlot, Transmog.currentTransmogItemClass)
    elseif Transmog.tab == 'illusions' then
        local nextPage = math.max(1, math.min(Transmog.currentPage + dir, math.max(1, Transmog.totalPages or 1)))
        if nextPage ~= Transmog.currentPage then
            PlaySound("igAbiliityPageTurn")
        end
        Transmog.currentPage = nextPage
        Transmog:RenderIllusions()
    elseif Transmog.tab == 'backpacks' then
        local nextPage = math.max(1, math.min(Transmog.currentPage + dir, math.max(1, Transmog.totalPages or 1)))
        if nextPage ~= Transmog.currentPage then
            PlaySound("igAbiliityPageTurn")
        end
        Transmog.currentPage = nextPage
        Transmog:RenderBackpacks()
    else
        Transmog_switchTab(Transmog.tab)
    end
end

-- Reverts all pending transmog edits, discarding un-applied changes.
function Transmog_revert()
    for InventorySlotId, itemID in pairs(Transmog.transmogStatusFromServer) do
        Transmog.transmogStatusToServer[InventorySlotId] = itemID
    end
    for slot, enchant in pairs(Transmog.illusionStatusFromServer) do
        Transmog.illusionStatusToServer[slot] = enchant
    end
    Transmog:HidePlayerItemsAnimation()

    Transmog:Reset()
    Transmog:calculateCost(0)
end

-- Stages a reset on every transmogged slot and illusion; Apply sends it, like right-clicking each slot.
function Transmog_RemoveAll()
    local staged = false
    for slotName, InventorySlotId in pairs(Transmog.inventorySlots) do
        if (Transmog.transmogStatusToServer[InventorySlotId] or 0) ~= 0 and Transmog_Try(0, slotName, 'newReset') then
            staged = true
        end
    end
    for slot, enchant in pairs(Transmog.illusionStatusToServer) do
        if enchant ~= 0 then
            Transmog.illusionStatusToServer[slot] = 0
            staged = true
        end
    end

    if not staged then
        twfprint("Nothing is transmogrified.")
        return
    end

    Transmog:RefreshPendingGlows()
    Transmog:RefreshPreviewModel()
    if Transmog.tab == 'illusions' then
        Transmog:RenderIllusions()
    end
    Transmog:calculateCost()
end

-- Switches between the items and outfits tabs.
function Transmog_switchTab(to)

	twfdebug("Transmog_switchTab " .. to)

    Transmog.tab = to
    if to ~= 'illusions' then
        Transmog:LeaveIllusionsView()
    end
    if to ~= 'backpacks' then
        Transmog:LeaveBackpacksView()
    end
    if to == 'items' then
        TransmogFrameItemsButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
        TransmogFrameItemsButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
        TransmogFrameItemsButtonText:SetText(HIGHLIGHT_FONT_COLOR_CODE .. 'Items')

        if TransmogFrameSetsButton then
            TransmogFrameSetsButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\tab_inactive')
            TransmogFrameSetsButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
            TransmogFrameSetsButtonText:SetText(NORMAL_FONT_COLOR_CODE .. 'Sets')
        end

        if TransmogSetsFrame then
            TransmogSetsFrame:Hide()
        end

        TransmogFrameCollected:Show()

        if Transmog.currentTransmogSlot ~= nil then
            selectTransmogSlot(Transmog.currentTransmogSlot, Transmog.currentTransmogSlotName)
        else
            selectTransmogSlot(-1)
        end
    elseif to == 'sets' then
        TransmogFrameItemsButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\tab_inactive')
        TransmogFrameItemsButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
        TransmogFrameItemsButtonText:SetText(NORMAL_FONT_COLOR_CODE .. 'Items')

        if TransmogFrameSetsButton then
            TransmogFrameSetsButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
            TransmogFrameSetsButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
            TransmogFrameSetsButtonText:SetText(HIGHLIGHT_FONT_COLOR_CODE .. 'Sets')
        end

        -- Hide Items grid and pagination
        Transmog:hideItems(true)
        Transmog:hidePagination()
        TransmogFrameCollected:Hide()
        TransmogFrameFilters:Hide()
        TransmogFrameNoTransmogs:Hide()
        TransmogFrameSplash:Hide()
        TransmogFrameInstructions:Hide()

        -- Show Sets UI
        if Transmog.ShowSetsView then
            Transmog:ShowSetsView()
        end
    elseif to == 'illusions' then
        if not Transmog.serverSupportsIllusions then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[Transmog]|r Illusions aren't available on this realm yet.")
            Transmog_switchTab('items')
            return
        end

        TransmogFrameItemsButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\tab_inactive')
        TransmogFrameItemsButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
        TransmogFrameItemsButtonText:SetText(NORMAL_FONT_COLOR_CODE .. 'Items')

        if TransmogFrameSetsButton then
            TransmogFrameSetsButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\tab_inactive')
            TransmogFrameSetsButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
            TransmogFrameSetsButtonText:SetText(NORMAL_FONT_COLOR_CODE .. 'Sets')
        end
        Transmog:SetIllusionsTabActive(true)
        TransmogFrameFilters:Hide()

        if TransmogSetsFrame then
            TransmogSetsFrame:Hide()
        end

        TransmogFrameCollected:Show()
        Transmog:ShowIllusionsView()
    elseif to == 'backpacks' then
        if not Transmog.serverSupportsBackpacks then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[Transmog]|r Backpacks aren't available on this realm yet.")
            Transmog_switchTab('items')
            return
        end

        TransmogFrameItemsButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\tab_inactive')
        TransmogFrameItemsButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
        TransmogFrameItemsButtonText:SetText(NORMAL_FONT_COLOR_CODE .. 'Items')

        if TransmogFrameSetsButton then
            TransmogFrameSetsButton:SetNormalTexture('Interface\\AddOns\\Transmog\\assets\\tab_inactive')
            TransmogFrameSetsButton:SetPushedTexture('Interface\\AddOns\\Transmog\\assets\\tab_active')
            TransmogFrameSetsButtonText:SetText(NORMAL_FONT_COLOR_CODE .. 'Sets')
        end
        Transmog:SetBackpacksTabActive(true)
        TransmogFrameFilters:Hide()

        if TransmogSetsFrame then
            TransmogSetsFrame:Hide()
        end

        TransmogFrameCollected:Show()
        Transmog:ShowBackpacksView()
    end
end
