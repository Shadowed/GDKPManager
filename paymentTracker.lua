local Payment = GDKPManager:NewModule("Payment", "AceEvent-3.0")
local L = GDKPManagerLocals
local tradeGold, tradeName, tradeAccepted, tradeIsOwed
local lastSpammed, owedList = {}, {}
local SPAM_TIMEOUT = 5 * 10

function Payment:Enable()
	self:RegisterEvent("UI_INFO_MESSAGE")
	self:RegisterEvent("TRADE_MONEY_CHANGED")
	self:RegisterEvent("TRADE_SHOW")
	self:UpdateFrame()
end

function Payment:Disable()
	self:UnregisterAllEvents()
end

-- Tell people how much gold they owe
function Payment:TRADE_SHOW()
	if( not UnitExists("npc") or not GDKPManager.db.profile.currentRaid ) then return end
	
	local raidLog = GDKPManager.raidLogs[GDKPManager.db.profile.currentRaid]
	local interactName = UnitName("npc") or UNKNOWN
	local interactGUID = UnitGUID("npc")
	
	local owed = 0
	for _, loot in pairs(raidLog.loot) do
		if( loot.owed and loot.winner == interactName ) then
			owed = owed + loot.owed
		end
	end
	
	if( owed <= 0 ) then return end
	if( not lastSpammed[interactGUID] or lastSpammed[interactGUID] <= GetTime() ) then
		lastSpammed[UnitGUID("npc")] = GetTime() + SPAM_TIMEOUT
		SendChatMessage(string.format(L["You owe %s gold, pay up!"], owed), "WHISPER", nil, interactName)
	end

	tradeIsOwed = true
end

-- Money updated, keep track of this obviously
function Payment:TRADE_MONEY_CHANGED()
	tradeGold = GetTargetTradeMoney()
	tradeName = UnitName("npc")
end

-- Silly that this has to be registered, there's no (easy) way to find out that a trade went through
-- besides simply watching for the event
function Payment:UI_INFO_MESSAGE(event, msg)
	if( msg ~= ERR_TRADE_COMPLETE ) then return end
	
	local raidLog = GDKPManager.db.profile.currentRaid and GDKPManager.raidLogs[GDKPManager.db.profile.currentRaid]
	if( tradeAccepted and tradeGold and tradeName and raidLog and tradeIsOwed ) then
		local goldPaid = math.floor(tradeGold / COPPER_PER_GOLD)
		
		-- If they owe 500g for Foo and 250g for Bar then they trade 600g
		-- it will (Depending on order won) first remove the debt of 250g leaving them with 350g
		-- then it will remove 350g from the 500g debt leaving them with owing 150g still
		for i=#(raidLog.loot), 1, -1 do
			local loot = raidLog.loot[i]
			print(loot.owed, loot.winner, loot.winner == tradeName)
			if( loot.owed and loot.winner == tradeName ) then
				if( goldPaid >= loot.owed ) then
					goldPaid = goldPaid - loot.owed
					loot.owed = nil
					print("paid all up!", loot.link)
				else
					loot.owed = loot.owed - goldPaid
					break
				end
			end
		end
		
		self:SendMessage("REBUILD_LOGS", GDKPManager.db.profile.currentRaid)
		self:UpdateFrame()
	end

	tradeAccepted, tradeGold, tradeName, tradeIsOwed = nil, nil, nil
end

local function sortAmounts(a, B)
	if( not a ) then
		return true
	elseif( not b ) then
		return false
	end
	
	return a.amountOwed > b.amountOwed
end

function Payment:UpdateFrame()
	local raidLog = GDKPManager.raidLogs[GDKPManager.db.profile.currentRaid]

	-- Figure out who owes what in totals for the display
	table.wipe(owedList)
	local found
	for _, loot in pairs(raidLog.loot) do
		if( loot.owed ) then
			found = true
			owedList[loot.winner] = (owedList[loot.winner] or 0) + loot.owed
		end
	end
	
	if( not found ) then
		if( self.frame ) then
			self.frame:Hide()
		end
		return		
	end

	if( not self.frame ) then
		self.frame = CreateFrame("Frame", nil, UIParent)
		self.frame:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 9,
			edgeSize = 9,
			insets = { left = 2, right = 2, top = 2, bottom = 2 }})
		self.frame:SetBackdropColor(0, 0, 0, 1)
		self.frame:SetBackdropBorderColor(0.85, 0.85, 0.85, 0.90)
		self.frame:SetHeight(20)
		self.frame:SetWidth(150)
		self.frame:SetMovable(true)
		self.frame:SetClampedToScreen(true)
		self.frame:EnableMouse(true)
		self.frame:RegisterForDrag("LeftButton")
		self.frame:SetScript("OnDragStop", function(self)
			if( self.isMoving ) then
				self:StopMovingOrSizing()
	
				local scale = self:GetEffectiveScale()
				GDKPManager.db.profile.owedPosition = {x = self:GetLeft() * scale, y = self:GetTop() * scale}
			end
		end)
	
		self.frame:SetScript("OnDragStart", function(self)
			self.isMoving = true
			self:StartMoving()
		end)
		self.frame:SetScript("OnShow", function(self)
			if( not GDKPManager.db.profile.owedPosition ) then
				self:ClearAllPoints()
				self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
			else
				local scale = self:GetEffectiveScale()
				self:ClearAllPoints()
				self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", GDKPManager.db.profile.owedPosition.x / scale, GDKPManager.db.profile.owedPosition.y / scale)
			end
		end)
		self.frame.rows = {}
		self.frame:Hide()
		
		local owedLabel = self.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		owedLabel:SetWidth(130)
		owedLabel:SetHeight(10)
		owedLabel:SetJustifyH("LEFT")
		owedLabel:SetText(L["Gold owed"])
		owedLabel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -6)
		self.frame.owedLabel = owedLabel
		
		local button = CreateFrame("Button", nil, self.frame, "UIPanelCloseButton")
		button:SetHeight(26)
		button:SetWidth(26)
		button:SetPoint("TOPRIGHT", 3, 3)
		button:SetScript("OnClick", function() Payment.frame:Hide() end)
	end
	
	for _, row in pairs(self.frame.rows) do row:Hide() end
	
	-- Now do a display update
	local used = 0
	for owedBy, amount in pairs(owedList) do
		used = used + 1
		
		local row = self.frame.rows[used]
		if( not row ) then
			row = CreateFrame("Frame", nil, self.frame)
			row:SetHeight(20)
			row:SetWidth(130)
			row.playerName = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			row.playerName:SetPoint("LEFT", row, "LEFT", 0, 0)
			row.playerName:SetHeight(10)
			row.playerName:SetWidth(95)
			row.playerName:SetJustifyH("LEFT")
			row.playerName:SetJustifyV("CENTER")

			row.amount = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			row.amount:SetPoint("RIGHT", row, "RIGHT", 12, 0)
			row.amount:SetHeight(10)
			row.amount:SetWidth(50)
			row.amount:SetJustifyH("RIGHT")
			row.amount:SetJustifyV("CENTER")
			
			self.frame.rows[used] = row
		end
		
		local classToken = select(2, UnitClass(owedBy))
		if( classToken ) then
			row.playerName:SetFormattedText("|cff%02x%02x%02x%s|r", RAID_CLASS_COLORS[classToken].r *255, RAID_CLASS_COLORS[classToken].g * 255, RAID_CLASS_COLORS[classToken].b * 255, owedBy)
		else
			row.playerName:SetText(owedBy)
		end
		
		row.amount:SetText(amount)
		row.amountOwed = amount
		row:ClearAllPoints()
		row:Show()
	end
	
	table.sort(self.frame.rows, sortAmounts)
	
	self.frame:SetHeight(20 + #(self.frame.rows) * 20)
	for id, row in pairs(self.frame.rows) do
		if( id > 1 ) then
			row:SetPoint("TOPLEFT", self.frame.rows[id - 1], "BOTTOMLEFT", 0, 0)
		else
			row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -20)
		end
	end
	
	if( used > 0 ) then
		self.frame:Show()
	else
		self.frame:Hide()
	end
end