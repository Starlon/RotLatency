local L = LibStub("AceLocale-3.0"):GetLocale("RotLatency")
local ldb = LibStub:GetLibrary("LibDataBroker-1.1")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local frame = CreateFrame("frame")
local timers = {}

frame:SetScript("OnEvent", ldb.OnEvent)

_G.RotLatency = LibStub("AceAddon-3.0"):NewAddon("RotLatency", "AceEvent-3.0", "AceConsole-3.0")
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
			limit = 10
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
			usage = L["RotLatency will use this spell to track global cooldown. It should be a spell on the GCD, but does not have a cooldown of its own."],
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
		spells = {
			type = "group",
			name = L["Spells to Track"],
			args = {},
			order = 5
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
end

function RotLatency:CommandHandler(command)
	if not command then
		self:Print(L["Usage: /rotlatency <command>"])
		self:Print(L["Where <command> is one of 'config' or 'stats' without quotes."])
	elseif command == "config" then
		AceConfigDialog:SetDefaultSize("RotLatency", 500, 450)
		AceConfigDialog:Open("RotLatency")
	elseif command == "stats" then
		self:ShowStats(false)
	end
end


function RotLatency:ResetTimers() 
	timers = {}
end

function RotLatency:OpenConfig()
	AceConfigDialog:SetDefaultSize("RotLatency", 500, 450)
	AceConfigDialog:Open("RotLatency")
end

function RotLatency:OnEnable()
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	self:RegisterEvent("PLAYER_ENTER_COMBAT")
	self:RegisterEvent("PLAYER_LEAVE_COMBAT")
end

function RotLatency:OnDisable()
	frame:SetScript("OnUpdate", nil)
	self:UnregisterAllEvents()
end

function RotLatency:PLAYER_ENTER_COMBAT()
	frame:SetScript("OnUpdate", self.OnUpdate)
end

function RotLatency:PLAYER_LEAVE_COMBAT()
	frame:SetScript("OnUpdate", nil)
end

-- This event is inconsistent
function RotLatency:SPELL_UPDATE_COOLDOWN()

end

do
	local update = 0
	local gcd = {start = 0, finish = 0, active = false}
	
	function RotLatency.OnUpdate(_, elapsed)
	
		update = update + elapsed
	
		if update < .1 then
			return
		end
	
		update = 0
	
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
					timers[name][0] = {active=false, start=0, finish=0}
				end
		
				local count = #timers[name]
		
				local timer = timers[name][count]
					
				if start ~= 0 and not timer.active then
					timers[name][count + 1] = {}
					timers[name][count + 1].active = true
					timers[name][count + 1].start = now
					timers[name][count + 1].gcd = gcdDur
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
	tooltip:AddDoubleLine(L["Click to configure. Shift-Click to clear data."])
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

function RotLatency.OnClick()
	if IsShiftKeyDown() then
	RotLatency:ResetTimers()
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
