local L = LibStub("AceLocale-3.0"):GetLocale("RotLatency")
local ldb = LibStub:GetLibrary("LibDataBroker-1.1")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local LibTimer = LibStub("LibScriptableUtilsTimer-1.0")

local timers = {}

_G.RotLatency = LibStub("AceAddon-3.0"):NewAddon("RotLatency", "AceEvent-3.0", "AceConsole-3.0", "LibSink-2.0")
local RotLatency = _G.RotLatency

RotLatency.TT = CreateFrame("GameTooltip")
RotLatency.TT:SetOwner(UIParent, "ANCHOR_NONE")

local playerClass = UnitClass("player")

function RotLatency:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("RotLatencyDB")
	
	self.db:RegisterDefaults({
		profile = {
			spells = { [BOOKTYPE_SPELL] = { }, [BOOKTYPE_PET] = { } },
			gcd = 0,
			gap = 10,
			limit = 10,
			refreshRate = 50
		}
	})
	
	self.options = {
		type = "group",
		args = {
			gcd = {
			type = "input",
			name = L["GCD Spell"],
			set = function(info, v)
				for book, _ in pairs(self.db.profile.spells) do
					for i = 1, 500 do
						local name = GetSpellBookItemName(i, book)
						if name == v then
							self.db.profile.gcd = i
						end
					end
				end
			end,
			get = function()
				if self.db.profile.gcd == 0 then
					return ""
				end
				for book, _ in pairs(self.db.profile.spells) do
					local name = GetSpellBookItemName(self.db.profile.gcd, book)
					if name then
						return name
					end
				end
			end,
			validate = function(info, v) 
				for book, spells in pairs(self.db.profile.spells) do
					for i = 1, 500, 1 do
						local name = GetSpellBookItemName(i, book)
						if name == v then
							return true
						end
					end
				end
				return L["No such spell exists in your spell book."]
			end,		

			usage = L["Note that this is mandatory for things to work! RotLatency will use this spell to track global cooldown. It should be a spell on the GCD, but does not have a cooldown of its own. Find Herbs is a good example."] = true
			order = 1
		},
		newLine = {
			type = "header",
			name = "",
			order = 2
		},
		limit = {
			type = "input",
			name = L["Display Limit"],
			set = function(info, v)
				self.db.profile.limit = tonumber(v)
			end,
			get = function()
				return tostring(self.db.profile.limit)
			end,
			pattern = "%d",
			usage = L["Enter how many records back to display."],
			order = 4
		},
		gap = {
			type = "input",
			name = L["Time Gap"],
			set = function(info, v)
				self.db.profile.gap = tonumber(v)
			end,
			get = function()
				return tostring(self.db.profile.gap)
			end,
			pattern = "%d",
			usage = L["Enter the value in seconds for which to give up waiting for the next spell cast."],
			order = 5
		},
		refreshRate = {
			type = "input",
			name = L["Refresh Rate"],
			usage = L["This determines how fast the cooldowns are examined; the format is in milliseconds."],
			set = function(info, v)
				self.db.profile.refreshRate = tonumber(v)
				self.timer:Stop()
				self.timer:Del()
				self.timer = LibTimer:New("RotLatency", self.db.profile.refreshRate, true, RotLatency.OnUpdate)
			end,
			get = function() 
				return tostring(self.db.profile.refreshRate)
			end,
			order = 6
		},
		spells = {
			type = "group",
			name = L["Spells to Track"],
			args = {},
			order = 7
		}
	}
	}
	
	LibStub("AceConfig-3.0"):RegisterOptionsTable("RotLatency", self.options)
	
	AceConfigDialog:AddToBlizOptions("RotLatency")
	
	self:RegisterChatCommand("rotlatency", "CommandHandler")

	self.TT = CreateFrame("GameTooltip")
	self.TT:SetOwner(UIParent, "ANCHOR_NONE")
	self.obj = ldb:NewDataObject("RotLatency", {type = "data source", text = "RotLatency",})
	self.obj.OnTooltipShow = RotLatency.OnTooltip
	self.obj.OnClick = RotLatency.OnClick
	
	
	self:RebuildOptions()
	self.timer = LibTimer:New("RotLatency", self.db.profile.refreshRate or 50, true, RotLatency.OnUpdate)
end

function RotLatency:CommandHandler(command)
	if not command then
		self:Print(L["Usage: /rotlatency <command>"])
		self:Print(L["Where <command> is one of 'config' or 'stats' without quotes."])
	elseif command == "config" then
		AceConfigDialog:SetDefaultSize("RotLatency", 300, 450)
		AceConfigDialog:Open("RotLatency")
	elseif command == "stats" then
		self:ShowStats(false)
	end
end


function RotLatency:OpenConfig()
	AceConfigDialog:SetDefaultSize("RotLatency", 500, 450)
	AceConfigDialog:Open("RotLatency")
end

function RotLatency:OnEnable()
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	self:RegisterEvent("PLAYER_ENTER_COMBAT")
	self:RegisterEvent("PLAYER_LEAVE_COMBAT")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

function RotLatency:OnDisable()
	self:UnregisterAllEvents()
end

local toggle = true
function RotLatency:PLAYER_ENTER_COMBAT()
	if toggle then
		self.timer:Start()
	end
end

function RotLatency:PLAYER_LEAVE_COMBAT()
	self.timer:Stop()
end

local guid = UnitGUID("player")
function RotLatency:COMBAT_LOG_EVENT_UNFILTERED(_, ...)
	local timeStamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, spellid, spellname = ...
	if sourceGUID ~= guid then return end
	if event:find("_DAMAGE") then
		for book, spells in pairs(RotLatency.db.profile.spells) do
			for key, spell in pairs(spells) do
				local skillType, spell_ID = GetSpellBookItemInfo(spell.id, book)
				if spellid ==  spell_ID and timers[book .. key] then
					local spellname, rank, icon, cost, isFunnel, powerType, castTime, minRange, maxRange = GetSpellInfo(spell_ID)
					local i = #timers[book .. key]
					local timer1 = timers[book .. key][i]
					local timer2 = timers[book .. key][i - 1]
					if timer1 and timer2 and timer1.start and timer2.finish and i > 1 then
						local text = format("%s: %dms", spellname, (timer1.start - timer2.finish) * 100)
						self:Pour(text, spell.r or 1, spell.g or .5, spell.b or 1, font, size, outline, sticky, location, icon)
					end
				end
			end
		end
	end
end

-- This event is inconsistent
function RotLatency:SPELL_UPDATE_COOLDOWN()

end

do
	local gcd = {start = 0, finish = 0, active = false}
	
	function RotLatency.OnUpdate(_, elapsed)
	
		local now = GetTime()

		local gcdStart, gcdDur, gcdEnabled
	
		if RotLatency.db.profile.gcd == 0 then
			return
		end
	
		for book, _ in pairs(RotLatency.db.profile.spells) do 
			gcdStart, gcdDur, gcdEnabled = GetSpellCooldown(RotLatency.db.profile.gcd, book)
			if gcdStart ~= 0 then
				break
			end
		end
	
		if gcdStart == nil then
			return
		end
	
		if gcdStart ~= 0 and gcdEnabled == 1 and not gcd.active then
			gcd.start = now
			gcd.active = true
		elseif gcdStart == 0 and gcdEnabled == 1 and gcd.active then
			gcd.finish = now
			gcd.active = false
		end
	
		for book, spells in pairs(RotLatency.db.profile.spells) do
			for key, spell in pairs(spells) do
				local start, dur = GetSpellCooldown(spell.id, book)

				local name = book .. key
		
				if not timers[name] then
					timers[name] = {}
					timers[name][0] = {active=false, start=0, finish=0, name = name, icon = icon}
				end
		
				local count = #timers[name]
		
				local timer = timers[name][count]
					
				if start ~= 0 and not timer.active then
					timers[name][count + 1] = {}
					timers[name][count + 1].active = true
					timers[name][count + 1].start = now
					timers[name][count + 1].gcd = gcdDur
					timers[name][count + 1].name = spellName
					timers[name][count + 1].icon = icon
					if timer.elapse and count > 0 then
						timer.finish = gcd.finish
						timer.elapse = false
					end
				elseif start == 0 and count > 0 and timer.active then
					timer.active = false
					timer.finish = now
					if spell.gcd then
						timer.elapse = true
					end			
				end
			end
		end		
	end
end

function RotLatency.OnTooltip(tooltip)
	tooltip:ClearLines()

	RotLatency:ShowStats(true, tooltip)
	
	tooltip:AddDoubleLine("")
	local toggle = toggle and "off" or "on"
	tooltip:AddDoubleLine(format(L["Click to configure. Shift-Click to clear data. Ctrl-Click to toggle %s."], toggle))
end
	
function RotLatency:PourTimer(timer)
end

function RotLatency:ShowStats(onTooltip, tooltip)
	local latencyTotal = 0
	local count = 0

	if onTooltip then
		tooltip:AddDoubleLine(L["Action Latencies"])
	else
		self:Print(L["Action Latencies"])
	end
	
	for book, spells in pairs(RotLatency.db.profile.spells) do
		for key, spell in pairs(spells) do
			local name = book .. key		
			local num = 0
			local val = 0
			local trash = 0
		
			if timers[name] then
				num = #timers[name]
			end
		
			if num > 2 then
				for i = 2, num, 1 do
					local delta = timers[name][i].start - timers[name][i - 1].finish
					if delta < RotLatency.db.profile.gap then
						val = val + delta
					else
						trash = trash + 1
					end
				end
		
				local latency = val / (num - 2 - trash)

				local text = spell.name .. ": " .. string.format("%.2f",  latency * 100) .. L["ms"]
				if onTooltip then
					tooltip:AddDoubleLine(text)
				else
					self:Print(text)
				end

				local firstTimer = 2

				if num - 2 > (RotLatency.db.profile.limit or 10) then
					firstTimer = num - RotLatency.db.profile.limit
				end

				trash = 0
				for i = firstTimer, num do
					local delta = timers[name][i].start - timers[name][i - 1].finish
					if delta < RotLatency.db.profile.gap then
						text = (i - 1) .. ": " .. string.format("%2f", delta * 100)
						if onTooltip then
							tooltip:AddDoubleLine(text)
						else
							self:Print(text)
						end
					else
						trash = trash + 1
					end
				end			
			
				latencyTotal = latencyTotal + latency		
			
				count = count + 1
			end
		end
	end
	
	if count > 0 then
		text = L["Average: "] .. string.format("%.2f", latencyTotal / count * 100) .. "ms"
		if onTooltip then
			tooltip:AddDoubleLine(text)
		else
			self:Print(text)
		end
	elseif not onTooltip then
		self:Print(L["Nothing to display"])
	end
end

function RotLatency:ResetTimers() 
	timers = {}
end

function RotLatency.OnClick()
	if IsShiftKeyDown() then
		RotLatency:ResetTimers()
		return
	end
	if IsControlKeyDown() then
		toggle = not toggle
		RotLatency:Print(format(L["RotLatency is %s."], toggle and "On" or "Off"))
		return
	end
	RotLatency:OpenConfig()
end

function RotLatency:RebuildOptions()
	self.options.args.spells.args = {}
	
	self.options.args.spells.args.add = {
	name = L["Add Spell"],
	type = "input",
	set = function(info, v)
		for book, spells in pairs(self.db.profile.spells) do
		for i = 1, 500, 1 do
			local name = GetSpellBookItemName(i, book)
			if name == v then
			local key = string.gsub(name, " ", "_")
			key = name
			self.db.profile.spells[book][key] = {name = v, id = i, gcd=false}
			self:RebuildOptions()
			end
		end
		end
	end,
	usage = L["Enter the spell's name."],
	validate = function(info, v) 
		for book, spells in pairs(self.db.profile.spells) do
		for i = 1, 500, 1 do
			local name = GetSpellBookItemName(i, book)
			if name == v then
			return true
			end
		end
		end
		return L["No such spell exists in your spell book."]
	end,
	order = 1
	}
	
	for book, spells in pairs(self.db.profile.spells) do
	for key, spell in pairs(spells) do
		self.options.args.spells.args[key] = {
		name = spell.name,
		type = "group",
		args = {
			gcd = {
			name = L["Track GCD"],
			type = "toggle",
			set = function(info, v) 
				self.db.profile.spells[book][key].gcd = v
			end,
			get = function()
				return spell.gcd
			end,
			order = 1
			},
			space = {
			name = "",
			type = "header",
			order = 2
			},
			delete = {
			name = L["Delete "] .. spell.name,
			type = "execute",
			func = function() 
				self.db.profile.spells[book][key] = nil
				self:RebuildOptions()
			end,
			order = 3
			}
		}
		}
	end
	end
	
	self:ResetTimers()
end 
