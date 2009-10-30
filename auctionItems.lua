local Auctions = GDKPManager:NewModule("Auctions", "AceEvent-3.0")
local L = GDKPManagerLocals
local status = {}
local LOOT_RECORD_TIMEOUT = 5 * 60

function Auctions:Enable()
	self:RegisterEvent("LOOT_OPENED")
	self:RegisterEvent("LOOT_CLOSED")
end

function Auctions:Disable()
	selfl:UnregisterAllEvents()
end

local function setBossName(self)
	local thresholdTime = GetTime() - LOOT_RECORD_TIMEOUT
	local raidLoot = GDKPManager.raidLogs[GDKPManager.db.profile.currentRaid].loot
	for i=#(raidLoot), 1, -1 do
		local loot = raidLoot[i]
		if( loot.time >= thresholdTime and not loot.auctioned ) then
			loot.boss = self:GetText()
		end
	end
end

local function updateAuctionStatus(self, elapsed)
	self.timeElapsed = self.timeElapsed + elapsed
	if( self.timeElapsed > 0.25 ) then
		self.timeElapsed = self.timeElapsed - 0.25
		self.auctionStatus:SetFormattedText(L["[%ds] highest bidder %s (%s gold) for %s"], status.endTime - GetTime(), status.highest or L["None"], status.bid or 0, status.fullLink)
	end
end

local function showTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
	GameTooltip:SetText(self.tooltipTitle, 1, .82, 0, 1)
	GameTooltip:AddLine(self.tooltip, 1, 1, 1, 1)
	GameTooltip:Show()
end

local function hideTooltip(self)
	GameTooltip:Hide()
end

function Auctions:UpdateFrame(bossName)
	if( not self.frame ) then
		self.frame = CreateFrame("Frame", "GDKPManagerAuctionFrame", UIParent)
		self.frame:SetWidth(400)
		self.frame:SetHeight(90)
		self.frame:SetMovable(true)
		self.frame:SetClampedToScreen(true)
		self.frame:EnableMouse(true)
		self.frame:RegisterForDrag("LeftButton")
		self.frame.rows = {}
		self.frame.usedRows = 0
		self.frame.timeElapsed = 0
		self.frame:Hide()
		self.frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			edgeSize = 26,
			insets = {left = 9, right = 9, top = 9, bottom = 9},
		})
		self.frame:SetScript("OnDragStop", function(self)
			if( self.isMoving ) then
				self:StopMovingOrSizing()
	
				local scale = self:GetEffectiveScale()
				GDKPManager.db.profile.auctionPosition = {x = self:GetLeft() * scale, y = self:GetTop() * scale}
			end
		end)
	
		self.frame:SetScript("OnDragStart", function(self)
			self.isMoving = true
			self:StartMoving()
		end)
		self.frame:SetScript("OnShow", function(self)
			if( not GDKPManager.db.profile.auctionPosition ) then
				self:ClearAllPoints()
				self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
			else
				local scale = self:GetEffectiveScale()
				self:ClearAllPoints()
				self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", GDKPManager.db.profile.auctionPosition.x / scale, GDKPManager.db.profile.auctionPosition.y / scale)
			end
		end)
				
		-- Create the title/movy thing
		local texture = self.frame:CreateTexture(nil, "ARTWORK")
		texture:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
		texture:SetPoint("TOP", 0, 12)
		texture:SetWidth(250)
		texture:SetHeight(60)
		
		local title = CreateFrame("Button", nil, self.frame)
		title:SetPoint("TOP", 0, 4)
		title:SetText("GDKP Manager")
		title:SetPushedTextOffset(0, 0)
	
		title:SetNormalFontObject(GameFontNormal)
		title:SetHeight(20)
		title:SetWidth(200)
		title:RegisterForDrag("LeftButton")
		title:SetScript("OnDragStart", function(self)
			self.isMoving = true
			Auctions.frame:StartMoving()
		end)
		
		title:SetScript("OnDragStop", function(self)
			if( self.isMoving ) then
				self.isMoving = nil
				Auctions.frame:StopMovingOrSizing()
			end
		end)
		
		-- Close button, this needs more work not too happy with how it looks
		local button = CreateFrame("Button", nil, self.frame, "UIPanelCloseButton")
		button:SetHeight(27)
		button:SetWidth(27)
		button:SetPoint("TOPRIGHT", -2, -2)
		button:SetScript("OnClick", function()
			HideUIPanel(Auctions.frame)
		end)
		
		-- Boss name
		local label = self.frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		label:SetText(L["Boss name"])
		label:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -14)
		self.frame.label = label

		local bossName = CreateFrame("EditBox", self.frame:GetName() .. "BossName", self.frame, "InputBoxTemplate")
		bossName:SetHeight(19)
		bossName:SetWidth(132)
		bossName:SetAutoFocus(false)
		bossName:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -4) 
		self.frame.bossName = bossName
	
		bossName:SetScript("OnEditFocusLost", setBossName)
		bossName:SetScript("OnEnterPressed", setBossName)
		
		-- Auction status
		self.frame.auctionStatus = self.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		self.frame.auctionStatus:SetJustifyH("LEFT")
		self.frame.auctionStatus:SetWidth(370)
		self.frame.auctionStatus:SetHeight(10)
		self.frame.auctionStatus:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -63)
		self.frame.auctionStatus:SetText(L["No auctions are active."])
	end
	
	self.frame.bossName:SetText(bossName or "")
end

local function UpdateStatus(self, status)
	if( status == "reset" ) then
		self.wasAuctioned = nil
		self.startAuction:SetText(L["Auction"])
		self.startAuction:Enable()
	elseif( status == "sold" ) then
		self.wasAuctioned = true
		self.startAuction:SetText(L["Sold"])
		self.startAuction:Disable()
	elseif( status == "de" ) then
		self.wasAuctioned = true
		self.startAuction:SetText(L["DE"])
		self.startAuction:Disable()
	elseif( status == "enable" and not self.wasAuctioned ) then
		self.startAuction:Enable()
	elseif( status == "disable" and not self.wasAuctioned ) then
		self.startAuction:Disable()
	end
end

function Auctions:UpdateRow(itemLink)
	self.frame.usedRows = self.frame.usedRows + 1
	self.frame:SetHeight(100 + (self.frame.usedRows * 36))
	self.frame:Show()
	
	local row = self.frame.rows[self.frame.usedRows]
	if( not row ) then
		row = CreateFrame("Frame", nil, self.frame)
		row:SetHeight(30)
		row:SetWidth(370)
		row.UpdateStatus = UpdateStatus

		-- Item name
		row.itemName = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		row.itemName:ClearAllPoints()
		row.itemName:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.itemName:SetJustifyH("LEFT")
		row.itemName:SetWidth(200)
		row.itemName:SetHeight(10)
		
		-- Only show these labels above the first row to make it look more uniformed
		if( self.frame.usedRows == 1 ) then
			local label = self.frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
			label:SetText(L["Increment"])
			label:SetPoint("TOPLEFT", row, "TOPRIGHT", -114, 10)

			local label = self.frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
			label:SetText(L["Opening"])
			label:SetPoint("TOPLEFT", row, "TOPRIGHT", -166, 10)
		end

		-- Minimum interval
		local minInterval = CreateFrame("EditBox", self.frame:GetName() .. "MinInterval" .. self.frame.usedRows, row, "InputBoxTemplate")
		minInterval.tooltipTitle = L["Minimum interval"]
		minInterval.tooltip = L["Minimum increase in gold for a bid to be accepted."]
		minInterval:SetHeight(19)
		minInterval:SetWidth(40)
		minInterval:SetNumeric(true)
		minInterval:SetAutoFocus(false)
		minInterval:SetPoint("TOPRIGHT", row, "TOPRIGHT", -70, -4) 
		minInterval:SetScript("OnEnter", showTooltip)
		minInterval:SetScript("OnLeave", hideTooltip)
		minInterval:SetScript("OnTextChanged", function(self) GDKPManager.db.profile.minInterval[self:GetParent().itemLink] = self:GetNumber() end)
		row.minInterval = minInterval

		-- Starting bid
		local startingBid = CreateFrame("EditBox", self.frame:GetName() .. "StartingBid" .. self.frame.usedRows, row, "InputBoxTemplate")
		startingBid.label = label
		startingBid.tooltipTitle = L["Starting bid"]
		startingBid.tooltip = L["What to start the bid at in gold for this auction."]
		startingBid:SetHeight(19)
		startingBid:SetWidth(40)
		startingBid:SetNumeric(true)
		startingBid:SetAutoFocus(false)
		startingBid:SetPoint("TOPRIGHT", row, "TOPRIGHT", -120, -4) 
		startingBid:SetScript("OnEnter", showTooltip)
		startingBid:SetScript("OnLeave", hideTooltip)
		startingBid:SetScript("OnTextChanged", function(self) GDKPManager.db.profile.startingBid[self:GetParent().itemLink] = self:GetNumber() end)
		row.startingBid = startingBid
		
		row.startAuction = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.startAuction:SetHeight(20)
		row.startAuction:SetWidth(60)
		row.startAuction:SetText(L["Auction"])
		row.startAuction.tooltipTitle = L["Start auction"]
		row.startAuction.tooltip = L["Starts up the auction for this item, you can only auction one item at a time."]
		row.startAuction:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row.startAuction:SetScript("OnEnter", showTooltip)
		row.startAuction:SetScript("OnLeave", hideTooltip)
		row.startAuction:SetScript("OnClick", Auctions.StartAuction)
		
		if( self.frame.usedRows > 1 ) then
			row:SetPoint("TOPLEFT", self.frame.rows[self.frame.usedRows - 1], "BOTTOMLEFT", 0, -6)
		else
			row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 13, -90)
		end
		
		self.frame.rows[self.frame.usedRows] = row
	end
	
	local itemName, _, _, _, _, _, _, _, itemIcon = select(2, GetItemInfo(itemLink))
	row.itemName:SetFormattedText("|T%s:16:16:-1:0|t %s", itemIcon or "", itemName or itemLink)
	row.minInterval:SetNumber(GDKPManager.db.profile.minInterval[itemLink] or GDKPManager.db.profile.minInterval.default)
	row.startingBid:SetNumber(GDKPManager.db.profile.startingBid[itemLink] or GDKPManager.db.profile.startingBid.default)
	row.itemLink = itemLink
	
	row:UpdateStatus(status.type == "auction" and "disable" or "enable")
end

function Auctions:LOOT_OPENED()
	if( self.frame ) then
		for _, row in pairs(self.frame.rows) do row:UpdateStatus("reset") end
		self.frame.usedRows = 0
		self.frame:Hide()
	end
	
	local bossName = UnitExists("target") and not UnitIsPlayer("target") and UnitIsDead("target") and UnitName("target")
	local thresholdTime = GetTime() - LOOT_RECORD_TIMEOUT

	for i=1, GetNumLootItems() do
		-- All of the new currency items seem to be using Money/Money(OBSOLETE) should be able to rely on this
		local itemLink = GDKPManager:GetItemID(GetLootSlotLink(i))
		local itemRarity, _, _, itemType, itemSubType, itemStack = select(3, GetItemInfo(itemLink))
		if( itemRarity and itemRarity >= 4 and itemType ~= "Money" and itemSubType ~= "Money(OBSOLETE)" ) then
			self:UpdateFrame(bossName)
			self:UpdateRow(itemLink)
			
			-- Find the first of this item looted within 5 minute
			local found
			local raidLoot = GDKPManager.raidLogs[GDKPManager.db.profile.currentRaid].loot
			for i=#(raidLoot), 1, -1 do
				local loot = raidLoot[i]
				if( loot.link == itemLink and loot.time >= thresholdTime and not loot.auctioned ) then
					found = true
					break
				end
			end
			
			if( not found ) then
				table.insert(raidLoot, {boss = self.frame.bossName:GetText(), link = itemLink, time = GetTime()})
			end
		end
	end
end

function Auctions:LOOT_CLOSED()
	if( self.frame ) then
		if( self.frame:IsVisible() and self.db.profile.autoPot ) then
			self:AnnouncePot(self.db.profile.currentRaid)
		end
		
		self.frame:Hide()
	end
end

local countdownTimer
local auctionTimer = CreateFrame("Frame")
auctionTimer:Hide()
auctionTimer:SetScript("OnUpdate", function(self, elapsed)
	local timeLeft = status.endTime - GetTime()
	if( timeLeft <= 0 ) then
		self:Hide()
		Auctions:FinishedAuction()
		
	elseif( timeLeft <= GDKPManager.db.profile.auctionCountdown and timeLeft >= 1 ) then
		if( countdownTimer ) then
			countdownTimer = countdownTimer - elapsed
			if( countdownTimer >= 0 ) then return end
			
			if( status.highest ) then
				GDKPManager:GroupMessage(string.format(L["[%ds] %s [highest bid: %s, %s gold] [next bid: %s gold]"], timeLeft, status.fullLink, status.highest, status.bid, status.bid + status.increment))
			else
				GDKPManager:GroupMessage(string.format(L["[%ds] %s [opening bid: %s gold] No bids yet!"], timeLeft, status.fullLink, status.start))
			end
		end
		
		countdownTimer = timeLeft >= 20 and 10 or timeLeft >= 10 and 5 or timeLeft >= 5 and 3 or 1
	end
end)

function Auctions.StartAuction(button)
	local itemLink = button:GetParent().itemLink
	local fullItemLink = itemLink and select(2, GetItemInfo(itemLink))
	if( not fullItemLink or ( GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 ) ) then return end
	
	self = Auctions

	status.type = "auction"
	status.highest = nil
	status.bid = nil
	status.link = itemLink
	status.fullLink = fullItemLink
	status.increment = GDKPManager.db.profile.minInterval[itemLink] or GDKPManager.db.profile.minInterval.default		status.start = GDKPManager.db.profile.startingBid[itemLink] or GDKPManager.db.profile.startingBid.default
	status.nextBid = status.start
	status.endTime = GetTime() + GDKPManager.db.profile.auctionTime
	
	GDKPManager:GroupMessage(string.format(L["BIDDING STARTING QUITE DOWN: Opening at %s gold, minimum increment %s gold, you have %d seconds."], status.start, status.increment, GDKPManager.db.profile.auctionTime))
	GDKPManager:GroupMessage(string.format(L["[%ds] %s [opening bid: %s gold]"], GDKPManager.db.profile.auctionTime, fullItemLink, status.start))
	
	if( GetNumRaidMembers() > 0 ) then
		self:RegisterEvent("CHAT_MSG_RAID", "CheckBidMessage")
		self:RegisterEvent("CHAT_MSG_RAID_LEADER", "CheckBidMessage")
	elseif( GetNumPartyMembers() > 0 ) then
		self:RegisterEvent("CHAT_MSG_PARTY", "CheckBidMessage")
	end
	
	for _, row in pairs(self.frame.rows) do row:UpdateStatus("disable") end
	
	-- Off we go!
	self.frame:SetScript("OnUpdate", updateAuctionStatus)
	auctionTimer:Show()
end

function Auctions:CheckBidMessage(event, message, sender)
	if( string.match(message, "^%*%*") ) then return end
	
	-- Try and sanitize it by removing any item, achievement, etc links
	message = string.gsub(message, "|c(.-)|r", "")
	message = string.trim(message)
	bid = tonumber(string.match(message, "(%d+)"))
	if( not bid or bid < status.nextBid ) then return end
	
	status.highest = sender
	status.bid = bid
	status.nextBid = bid + status.increment
	status.endTime = GetTime() + GDKPManager.db.profile.auctionTime

	GDKPManager:GroupMessage(string.format(L["[%ds] %s [highest bid: %s, %s gold] [next bid: %s gold]"], GDKPManager.db.profile.auctionTime, status.fullLink, status.highest, status.bid, status.bid + status.increment))
end

function Auctions:FinishedAuction()
	self.frame:SetScript("OnUpdate", nil)
	for _, row in pairs(self.frame.rows) do
		if( row.itemLink == status.link ) then
			row:UpdateStatus(status.highest and "sold" or "de")
		else
			row:UpdateStatus("enabe")
		end
	end

	if( status.highest ) then
		GDKPManager:GroupMessage(string.format(L["FINISHED! %s was won by %s for %d gold."], status.fullLink, status.highest, status.bid))
		self.frame.auctionStatus:SetFormattedText(L["%s was won by %s for %d gold"], status.fullLink, status.highest, status.bid)
	else
		GDKPManager:GroupMessage(string.format(L["FINISHED! No bids on %s, nobody won."], status.fullLink))
		self.frame.auctionStatus:SetFormattedText(L["%s nobody bidded"], status.fullLink)
	end
	
	-- Update records
	local raidLoot = GDKPManager.raidLogs[GDKPManager.db.profile.currentRaid].loot
	local thresholdTime = GetTime() - LOOT_RECORD_TIMEOUT
	for i=#(raidLoot), 1, -1 do
		local loot = raidLoot[i]
		if( loot.link == status.link and loot.time >= thresholdTime and not loot.auctioned ) then
			loot.auctioned = true
			if( status.highest ) then
				loot.winner = status.highest
				loot.price = status.bid
				
				-- While the player can owe gold, it makes more sense to just pretend they paid it off instantly
				if( status.highest ~= UnitName("player") ) then
					loot.owed = loot.price
					GDKPManager.modules.Payment:UpdateFrame()
				end
			end
		end
	end
	
	self:UnregisterEvent("CHAT_MSG_RAID")
	self:UnregisterEvent("CHAT_MSG_RAID_LEADER")
	self:UnregisterEvent("CHAT_MSG_PARTY")
end



