local Config = GDKPManager:NewModule("Config", "AceEvent-3.0")
local AceDialog, AceRegistry, options
local idToRaid, rebuildQueue, totalLogs = {}, {}, 0
local L = GDKPManagerLocals

local function setGoldSlider(info, value)
	GDKPManager.db.profile[info[#(info)]][info.arg] = value
end

local function getGoldSlider(info)
	return GDKPManager.db.profile[info[#(info)]][info.arg]
end

local function loadGeneral()
	options.args.general = {
		order = 1,
		type = "group",
		name = L["General"],
		set = function(info, value) GDKPManager.db.profile[info[#(info)]] = value end,
		get = function(info) return GDKPManager.db.profile[info[#(info)]] end,
		args = {
			general = {
				order = 1,
				type = "group",
				inline = true,
				name = L["General"],
				args = {
					autoPot = {
						order = 1,
						type = "toggle",
						name = L["Auto announce pot after auction"],
						desc = L["Automatically announces the current pot after you finish auctioning at least one item and close the loot window."],
						width = "full",
					},
					rules = {
						order = 1,
						type = "input",
						multiline = true,
						name = L["GDKP Rules"],
						desc = L["Rules to put when typing /gdkp rules, you cannot use any line breaks in this and are limited to 255 characters."],
						width = "full",
					},
				},
			},
			defaults = {
				order = 2,
				type = "group",
				inline = true,
				name = L["Default auction settings"],
				args = {
					minInterval = {
						order = 1,
						type = "range",
						name = L["Minimum increment (In gold)"],
						desc = L["Minimum amount of gold people need to add to the highest bid by default."],
						min = 0, max = 1000, step = 25,
						arg = "default",
						set = setGoldSlider,
						get = getGoldSlider,
					},
					startingBid = {
						order = 2,
						type = "range",
						name = L["Starting bid (In gold)"],
						desc = L["What to start the bidding at for items in gold by default."],
						arg = "default",
						set = setGoldSlider,
						get = getGoldSlider,
					},
					auctionTime = {
						order = 3,
						type = "range",
						name = L["Auction duration (Seconds)"],
						desc = L["How long auctions should last, resets whenever a new highest bid is received."],
						min = 5, max = 30, step = 1,
					},
					auctionCountdown = {
						order = 4,
						type = "range",
						name = L["Auction countdown (Seconds)"],
						desc = L["How many seconds should be left on the auction before it starts to count down that it's going to end."],
						min = 0, max = 20, step = 1,	
					},
				},
			},
		},
	}
end

local tempList, exportOptions = {}, {members = true, pot = true, loot = true, exported = {}}
local buildAttendanceList, buildLootList
local classList = CopyTable(LOCALIZED_CLASS_NAMES_FEMALE)

local function setExportOption(info, value)
	exportOptions[info[#(info)]] = value
end

local function getExportOption(info)
	return exportOptions[info[#(info)]]
end

local function deleteLootRecord(info)
	local raidLog = GDKPManager.raidLogs[idToRaid[info[2]]]
	table.remove(raidLog.loot, info.arg)
	buildLootList(info[2])
end

local function deleteAttendanceRecord(info)
	local raidLog = GDKPManager.raidLogs[idToRaid[info[2]]]
	local attendanceList = options.args.logs.args[info[2]].args.attendance.args.attendees.args
	raidLog.members[info.arg] = nil
	
	attendanceList[info[2]] = nil
	attendanceList[info[2] .. "des"] = nil
	attendanceList[info[2] .. "sep"] = nil
	
	AceRegistry:NotifyChange("GDKPManager")
end

local attendeeName, attendeeLog
local function setAttendeeName(info, value)
	attendeeName = value
	attendeeLog = info[2]
end

local function getAttendeeName(info)
	return attendeeLog == info[2] and attendeeName or ""
end

local function setAttendeeClass(info, value)
	local raidLog = GDKPManager.raidLogs[idToRaid[info[2]]]
	raidLog.members[attendeeName] = value
	attendeeName, attendeeLog = nil, nil

	buildAttendanceList(info[2])
end

local function disableClassSelection(info)
	return attendeeLog ~= info[2] or not attendeeName
end

local function getExportLog(info)
	return exportOptions.exported[idToRaid[info[2]]] or ""
end

local classAttendance
local function sortClasses(a, b)
	return #(classAttendance[a]) < #(classAttendance[b])
end

local function generateLog(info)
	local raidLog = GDKPManager.raidLogs[idToRaid[info[2]]]
	local exported = ""
	
	if( exportOptions.members ) then
		classAttendance = {}
		
		local classList = {}
		for name, class in pairs(raidLog.members) do
			if( not classAttendance[class] ) then
				classAttendance[class] = {}
				table.insert(classList, class)
			end

			table.insert(classAttendance[class], name)
		end
		
		table.sort(classList, sortClasses)
		
		for _, class in pairs(classList) do
			exported = string.format("%s[b]%s (%d)[/b]: %s\n", exported, LOCALIZED_CLASS_NAMES_FEMALE[class], #(classAttendance[class]), table.concat(classAttendance[class], ", "))
		end
	end
	
	if( exportOptions.pot ) then
		if( exported ~= "" ) then exported = exported .. "\n" end
		table.wipe(tempList)
		
		local totalSold, totalUnsold, totalGold, totalBuyers, totalDropped = 0, 0, 0, 0, 0
		for _, loot in pairs(raidLog.loot) do
			if( loot.price ) then
				totalGold = totalGold + loot.price
				totalSold = totalSold + 1
			elseif( loot.unsold ) then
				totalUnsold = totalUnsold + 1
			end
						
			totalDropped = totalDropped + 1
			if( loot.winner and not tempList[loot.winner] ) then
				tempList[loot.winner] = true
				totalBuyers = totalBuyers + 1
			end
		end
		
		local totalAttended = 0
		for name in pairs(raidLog.members) do totalAttended = totalAttended + 1 end
		local averagePrice = totalSold > 0 and totalGold / totalSold or 0
		local averagePerPerson = totalAttended > 0 and totalGold / totalAttended or 0
		
		-- I feel dirty doing a concat and a string format at once :<
		exported = exported .. string.format(L["[b]%s[/b] players attended ([b]%s[/b] buyers), [b]%d[/b] gold per person."], totalAttended, totalBuyers, averagePerPerson)
		exported = exported .. "\n" .. string.format(L["[b]%d[/b] items dropped ([b]%d[/b] unsold), [b]%d[/b] gold per item average."], totalDropped, totalUnsold, averagePrice)
	end
	
	if( exportOptions.loot ) then
		if( exported ~= "" ) then exported = exported .. "\n" end
		
		local itemList = {}
		for _, loot in pairs(raidLog.loot) do
			local itemID = loot.link
			itemList[itemID] = itemList[itemID] or {averagePrice = 0, winners = 0, unsold = 0}
			
			if( loot.winner ) then
				itemList[itemID].averagePrice = itemList[itemID].averagePrice + loot.price
				itemList[itemID].winners = itemList[itemID].winners + 1
				table.insert(itemList[itemID], string.format(L["%d gold (%s)"], loot.price, loot.winner))
			else
				itemList[itemID].unsold = itemList[itemID].unsold + 1
			end
		end
		
		for itemID, drop in pairs(itemList) do
			local itemName = GetItemInfo(itemID) or itemID
			exported = exported .. "\n[" .. itemName .. "] "
			
			if( drop.unsold > 0 ) then
				exported = exported .. string.format(L["%d were unsold"], drop.unsold)
				if( drop.winners > 0 ) then exported = exported .. ", " end
			end
			
			if( drop.winners > 0 ) then
				exported = exported .. string.format(L["%d gold averaged: "], drop.averagePrice / drop.winners)
				exported = exported .. table.concat(drop, ", ")
			end
		end
	end
		
	if( not exportOptions.bbcode ) then
		exported = string.gsub(string.gsub(exported, "%[/b%]", ""), "%[b%]", "")
	end
	
	exportOptions.exported[idToRaid[info[2]]] = exported
	AceRegistry:NotifyChange("GDKPManager")
end

buildLootList = function(logID)
	local raidLog = GDKPManager.raidLogs[idToRaid[logID]]
	local lootList = options.args.logs.args[logID].args.loot.args.list.args
	
	table.wipe(lootList)
	
	for id, loot in pairs(raidLog.loot) do
		lootList[id .. "name"] = {
			order = id,
			type = "description",
			name = select(2, GetItemInfo(loot.link)) or loot.link,
			width = "",
		}
		
		local status
		if( loot.winner ) then
			local class = raidLog.members[loot.winner]
			local playerName = type(class) == "string" and string.format("|cff%02x%02x%02x%s|r", RAID_CLASS_COLORS[class].r * 255, RAID_CLASS_COLORS[class].g * 255, RAID_CLASS_COLORS[class].b * 255, loot.winner) or loot.winner

			if( loot.owed ) then
				status = string.format(L["%s (%s|cffffd700g|r |cffff2020owed|r)"], playerName, loot.price)
			else
				status = string.format("%s (%s|cffffd700g|r)", playerName, loot.price)
			end
		else
			status = L["Unsold"]
		end
		
		lootList[id .. "status"] = {
			order = id + 0.50,
			type = "description",
			name = status,
			width = "",	
		}
		
		lootList[tostring(id)] = {
			order = id + 0.75,
			type = "description",
			name = "",
			width = "full",	
		}
	end
end

buildAttendanceList = function(logID)
	local raidLog = GDKPManager.raidLogs[idToRaid[logID]]
	local attendanceList = options.args.logs.args[logID].args.attendance.args.attendees.args
	
	table.wipe(attendanceList)
	
	local id = 0
	for name, class in pairs(raidLog.members) do
		id = id + 1
		
		attendanceList[id .. "des"] = {
			order = id,
			type = "description",
			fontSize = "medium",
			name = type(class) == "string" and string.format("|cff%02x%02x%02x%s|r", RAID_CLASS_COLORS[class].r * 255, RAID_CLASS_COLORS[class].g * 255, RAID_CLASS_COLORS[class].b * 255, name) or name,
			width = "",
		}
		
		attendanceList[tostring(id)] = {
			order = id + 0.5,
			type = "execute",
			name = L["Delete"],
			func = deleteAttendanceRecord,
			arg = name,
			width = "half",
		}
		
		attendanceList[id .. "sep"] = {
			order = id + 0.75,
			type = "description",
			name = "",
			width = "full",
		}
	end
end

local function buildRaidLog(name)
	local raidLog = GDKPManager.raidLogs[name]
	local logID = idToRaid[name]
	
	options.args.logs.args[logID] = {
		order = 1,
		type = "group",
		name = name,
		childGroups = "tab",
		args = {
			general = {
				order = 1,
				type = "group",
				name = L["General"],
				args = {
					stats = {
						order = 1,
						type = "group",
						name = L["Stats"],
						inline = true,
						args = {
							stats = {
								order = 1,
								type = "description",
								fontSize = "medium",
								name = function(info)
									table.wipe(tempList)
									
									local raidLog = GDKPManager.raidLogs[idToRaid[info[2]]]
									local totalOwed, totalSold, totalUnsold, totalGold, totalBuyers, totalDropped = 0, 0, 0, 0, 0, 0
									for itemID, loot in pairs(raidLog.loot) do
										if( loot.owed ) then
											totalOwed = totalOwed + loot.owed
										elseif( loot.price ) then
											totalGold = totalGold + loot.price
											totalSold = totalSold + 1
										elseif( loot.unsold ) then
											totalUnsold = totalUnsold + 1
										end
										
										totalDropped = totalDropped + 1
										if( loot.winner and not tempList[loot.winner] ) then
											tempList[loot.winner] = true
											totalBuyers = totalBuyers + 1
										end
									end
									
									local totalAttended = 0
									for name in pairs(raidLog.members) do totalAttended = totalAttended + 1 end
									
									local endTime = raidLog.endTime or time()	
									local averagePrice = totalSold > 0 and totalGold / totalSold or 0
									local averagePerPerson = totalAttended > 0 and totalGold / totalAttended or 0
									local stat = string.format(L["Attended by |cff20ff20%d|r people, |cff20ff20%d|r buyers, %s %s."], totalAttended, totalBuyers, raidLog.endTime and L["log period"] or L["log still recording for"], string.lower(SecondsToTime(endTime - raidLog.startTime, nil, true)))
									
									stat = stat .. "\n" .. string.format(L["|cffffd700%d|r gold made, |cffffd700%d|r gold per person, buyers spent |cffffd700%d|r gold on average."], totalGold, averagePerPerson, totalGold / totalBuyers)
									stat = stat .. "\n\n" .. string.format(L["|cff20ff20%d|r items dropped (|cffff2020%d|r unsold), average sale price |cffffd700%d|r gold."], totalDropped, totalUnsold, averagePrice, averagePrice)
									
									if( totalOwed > 0 ) then
										stat = stat .. "\n\n" .. string.format(L["Still owed |cffff2020%d|r gold for items."], totalOwed)
									end
									
									return stat
								end,	
							},
						},
					},
					export = {
						order = 2,
						type = "group",
						name = L["Export logs"],
						inline = true,
						set = setExportOption,
						get = getExportOption,
						args = {
							help = {
								order = 1,
								type = "group",
								inline = true,
								name = L["Help"],
								args = {
									help = {
										order = 1,
										type = "description",
										name = L["You can use the below to export logs to plain text, if for example you want to post a list of items dropped, how much they sold for and who bought them."],
									},	
								},
							},
							members = {
								order = 2,
								type = "toggle",
								name = L["Include attedance list"],
								desc = L["Adds the list of players who were present in the group when loot was being auctioned."],
							},
							pot = {
								order = 3,
								type = "toggle",
								name = L["Include gold pot info"],
								desc = L["Adds the total gold pot, gold per member, total buyers and such."],
							},
							loot = {
								order = 4,
								type = "toggle",
								name = L["Include loot info"],
								desc = L["Adds who won what item and how much it went for."],
							},
							bbcode = {
								order = 5,
								type = "toggle",
								name = L["Use BBCode tags"],
								desc = L["Exports it with BBCode tags to make it easier to read, generally only used if posting on forums."],
							},
							generate = {
								order = 6,
								type = "execute",
								name = L["Generate!"],		
								func = generateLog,
							},
							export = {
								order = 7,
								type = "input",
								multiline = true,
								name = L["Exported log"],
								set = false,
								get	= getExportLog,
								width = "full",
							},
						},
					},
				},	
			},
			loot = {
				order = 2,
				type = "group",
				name = L["Loot"],
				args = {
					--[[
					add = {
						order = 1,
						type = "group",
						inline = true,
						name = L["Add drop"],
						args = {
							link = {
								order = 1,	
							},	
						},	
					},
					]]
					list = {
						order = 2,
						type = "group",
						inline = true,
						name = L["Drop list"],
						args = {
						},
					},
				},	
			},
			attendance = {
				order = 3,
				type = "group",
				name = L["Attendance"],	
				args = {
					add = {
						order = 1,
						type = "group",
						inline = true,
						name = L["Add attendee"],
						args = {
							name = {
								order = 1,
								type = "input",
								name = L["Player name"],
								set = setAttendeeName,
								get = getAttendeeName,
							},
							class = {
								order = 2,
								type = "select",
								name = L["Player class"],
								values = classList,
								set = setAttendeeClass,
								disabled = disableClassSelection	
							},
						},	
					},
					attendees = {
						order = 2,
						type = "group",
						inline = true,
						name = L["List of players who attended"],
						args = {
							
						},	
					},
				},
			},
		},		
	}
	
	buildAttendanceList(logID)
	buildLootList(logID)
end

local function rebuildRaidLogs()
	for name in pairs(GDKPManager.db.profile.raidLogs) do
		if( not idToRaid[name] ) then
			totalLogs = totalLogs + 1
			idToRaid[tostring(totalLogs)] = name
			idToRaid[name] = tostring(totalLogs)
			
			buildRaidLog(name)
		end
	end
end

local function loadLogs()
	options.args.logs = {
		order = 2,
		type = "group",
		name = L["Raid logs"],
		args = {
			
		},
	}
	
	rebuildRaidLogs()
end

local function loadOptions()
	options = {
		type = "group",
		name = "GDKP Manager",
		childGroups = "tree",
		args = {
		},	
	}

	loadGeneral()
	loadLogs()
end

-- Queues it so next time it'll reload it, need to figure out how to detect if the configuration is opened or closed next.
function Config:REBUILD_LOGS(event, name)
	if( not rebuildQueue[name] ) then
		rebuildQueue[name] = true
		AceRegistry:NotifyChange("GDKPManager")
	end
end

SLASH_GDKP1 = nil
SLASH_GDKPMANAGE1 = nil

SLASH_GDKPMANAGER1 = "/gdkp"
SLASH_GDKPMANAGER2 = "/gdkpmanager"
SLASH_GDKPMANAGER3 = "/gdkpmanage"
SlashCmdList["GDKPMANAGER"] = function(msg)
	local self = GDKPManager
	local cmd, arg = string.split(" ", msg or "", 2)
	cmd = string.lower(cmd or "")
	
	if( cmd == "config" or cmd == "ui" or cmd == "options" ) then
		if( not AceDialog and not AceRegistry ) then
			loadOptions()
			
			AceDialog = LibStub("AceConfigDialog-3.0")
			AceRegistry = LibStub("AceConfigRegistry-3.0")
			LibStub("AceConfig-3.0"):RegisterOptionsTable("GDKPManager", options)
			AceDialog:SetDefaultSize("GDKPManager", 650, 550)
			
			Config:RegisterMessage("REBUILD_LOGS")
		end
			
		AceDialog:Open("GDKPManager")
		
		-- Rebuild any raid logs that were queued, little silly but more efficient this way
		for name in pairs(rebuildQueue) do
			buildRaidLog(name)
			rebuildQueue[name] = nil
		end

	elseif( cmd == "pot" ) then
		self:AnnouncePot(arg or self.db.profile.currentRaid)
	elseif( cmd == "rule" or cmd == "rules" ) then
		if( self.db.profile.rules and self.db.profile.rules ~= "" ) then
			self:GroupMessage(self.db.profile.rules)
		else
			self:Echo(L["You need to set the rules for GDKP runs before you can use this."])
		end

	elseif( cmd == "end" ) then
		if( not self.db.profile.currentRaid ) then
			self:Print(L["No raids are active, you will need to start one before you can end it."])
			return
		end
		
		if( GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 ) then
			self:GroupMessage(string.format(L["GDKP run %s is over!"], self.db.profile.currentRaid))
			self:AnnouncePot(self.db.profile.currentRaid)
		else
			self:Print(string.format(L["Ended raid %s, you can find records of it in /gdkp options."]))
			self:AnnouncePot(self.db.profile.currentRaid)
		end
		
		self.db.profile.currentRaid = nil

		if( select(2, IsInInstance()) == "raid" and self.isActive ) then
			self.isActive = nil
			for _, module in pairs(self.modules) do
				if( module.Enable ) then
					module:Enable()
				end
			end
		end
		
	elseif( cmd == "start" ) then
		arg = string.trim(arg)
		if( self.db.profile.currentRaid ) then
			self:Print(string.format(L["Cannot start new raid log, still have %s raid active. Stop it first with /gdkp end %s."], self.db.profile.currentRaid, self.db.profile.currentRaid))
			return
		elseif( self.db.profile.raidLogs[arg] ) then
			self:Print(string.format(L["Cannot create new log with name \"%s\" one already exists."], arg))
			return
		elseif( arg == "" ) then
			self:Print(L["You must enter a name for this raid log."])
			return
		end
		
		self.db.profile.currentRaid = arg
		self.raidLogs[arg] = {startTime = time(), members = {}, loot = {}}
		self:Print(string.format(L["New raid log started %s! Remember to end it with /gdkp end when you are done."], arg))
		
		if( select(2, IsInInstance()) == "raid" and not self.isActive ) then
			self.isActive = true
			for _, module in pairs(self.modules) do
				if( module.Enable ) then
					module:Enable()
				end
			end
		end

	else
		self:Print(L["Slash commands"])
		self:Echo(L["/gdkp options - Shows the GDKP configuration and record frame"])
		self:Echo(L["/gdkp start <name> - Starts a new raid log with the passed <name>"])
		self:Echo(L["/gdkp end - Ends the active GDKP raid log"])
		self:Echo(L["/gdkp pot <name> - Announces the current gold pot to the given channel, if <name> is passed then it announces the pot for the specified raid"])
	end	
end



