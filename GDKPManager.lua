GDKPManager = LibStub("AceAddon-3.0"):NewAddon("GDKPManager", "AceEvent-3.0")
local L = GDKPManagerLocals
local instanceType

function GDKPManager:OnInitialize()
	self.defaults = {
		profile = {
			autoPot = false,
			rules = "",
			raidLogs = {},
			minInterval = {default = 100},
			startingBid = {default = 1000},
			auctionTime = 30,
			auctionCountdown = 5,
		},
	}
	
	self.db = LibStub:GetLibrary("AceDB-3.0"):New("GDKPManagerDB", self.defaults, true)
	self.db.RegisterCallback(self, "OnDatabaseShutdown", "OnDatabaseShutdown")
	
	self.raidLogs = setmetatable({}, {
		__index = function(tbl, index)
			-- No data found, don't try and load this index again
			if( not GDKPManager.db.profile.raidLogs[index] ) then
				rawset(tbl, index, false)
				return false
			end
			
			local log = loadstring("return " .. GDKPManager.db.profile.raidLogs[index])()
		
			rawset(tbl, index, log)
			return log
		end
	})

	self:RegisterEvent("PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	self:ZONE_CHANGED_NEW_AREA()
	
	-- Warn if they logged in with a raid open
	if( self.db.profile.currentRaid ) then
		self:Print(string.format(L["Warning! You still have the raid %s running, you should end it if you are finished."], self.db.profile.currentRaid))
	end
end

-- Only enable modules if a raid is running
function GDKPManager:ZONE_CHANGED_NEW_AREA()
	local type = select(2, IsInInstance())
	if( instanceType == "raid" and type ~= instanceType and self.db.profile.currentRaid and not self.isActive ) then
		self.isActive = true
		for _, module in pairs(self.modules) do
			if( module.Enable ) then
				module:Enable()
			end
		end
	elseif( instanceType ~= "raid" and type == "raid" and self.db.profile.currentRaid and self.isActive ) then
		self.isActive = nil
		for _, module in pairs(self.modules) do
			if( module.Disable ) then
				module:Disable()
			end
		end
	end
	
	instanceType = type
end

-- Handle writing the raw logs to their storage format
local function compressData(data)
	if( type(data) == "table" ) then
		local tempData = ""
		if( #(data) > 0 ) then
			for _, subValue in pairs(data) do
				tempData = string.format("%s%s;", tempData, compressData(subValue))
			end
		else
			for subKey, subValue in pairs(data) do
				subKey = type(subKey) == "string" and string.format('"%s"', subKey) or subKey
				tempData = string.format("%s[%s] = %s;", tempData, subKey, compressData(subValue))
			end
		end
		
		return string.format("{%s}", tempData)
	elseif( type(data) == "string" ) then
		return string.format('"%s"', data)
	else
		return tostring(data)
	end
end

function GDKPManager:OnDatabaseShutdown()
	for id, log in pairs(self.raidLogs) do
		if( type(log) == "table" ) then
			self.db.profile.raidLogs[id] = string.gsub(compressData(log), ";}", "}")
		end
	end
end

function GDKPManager:AnnouncePot(raid)
	local log = raid and self.raidLogs[raid]
	if( not log ) then
		self:Print(string.format(L["Cannot announce pot, no raid log for \"%s\"."], raid or ""))
		return
	end
	
	local totalOwed, totalSold, totalUnsold, totalGold = 0, 0, 0, 0
	for itemID, loot in pairs(log.loot) do
		if( loot.owed ) then
			totalOwed = totalOwed + 1
		elseif( loot.price ) then
			totalGold = totalGold + loot.price
			totalSold = totalSold + 1
		elseif( loot.unsold ) then
			totalUnsold = totalUnsold + 1
		end
	end
	
	local unpaid = totalOwed > 0 and string.format(L[" %d items need payment still"], totalOwed) or ""
	self:GroupMessage(string.format(L["Gold pot: %d gold / %d = %g gold per person. %d items sold, %s gold average, %d unsold%s."], totalGold, GetNumRaidMembers(), totalGold / GetNumRaidMembers(), totalSold, totalGold / totalSold, totalUnsold, unpaid), true)
end

-- Misc helper functions
function GDKPManager:GroupMessage(msg, localOutput)
	if( GetNumRaidMembers() > 0 ) then
		SendChatMessage(string.format("** %s", msg), "RAID")
	elseif( GetNumPartyMembers() > 0 ) then
		SendChatMessage(string.format("** %s", msg), "PARTY")
	elseif( localOutput ) then
		ChatFrame1:AddMessage(msg)
	end
end

function GDKPManager:GetItemID(link)
	link = string.match(link or "", "|H(.-):([-0-9]+):([0-9]+)|h")
	return link and string.gsub(link, ":0:0:0:0:0:0", "")
end

function GDKPManager:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99GDKP Manager|r: %s", msg))
end

function GDKPManager:Echo(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end
-- DEBUGGDKPManagerLocals = setmetatable(GDKPManagerLocals, {
	__index = function(tbl, value)
		rawset(tbl, value, value)
		return value
	end,
})