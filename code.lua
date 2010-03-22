local ldb = LibStub:GetLibrary("LibDataBroker-1.1")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local frame = CreateFrame("frame")
local timers = {}

frame:SetScript("OnEvent", ldb.OnEvent)

_G.RotLatency = LibStub("AceAddon-3.0"):NewAddon("RotLatency", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0", "AceHook-3.0")
local RotLatency = _G.RotLatency

RotLatency.TT = CreateFrame("GameTooltip")
RotLatency.TT:SetOwner(UIParent, "ANCHOR_NONE")

local playerClass = UnitClass("player")

function RotLatency:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("RotLatencyDB")
	
	self.db:RegisterDefaults({
		profile = {
            spells = { [BOOKTYPE_SPELL] = { }, [BOOKTYPE_PET] = { }, }
		}
	})
        	
	self.options = {
		type = "group",
		args = {
			spells = {
                type = "group",
                name = "Spells to Track",
                args = {}
            }
		}
	}
	
	LibStub("AceConfig-3.0"):RegisterOptionsTable("RotLatency", self.options)
	
	AceConfigDialog:AddToBlizOptions("RotLatency")
    
	self:RegisterChatCommand("rotlatency", "OpenConfig")

    RotLatency.TT = CreateFrame("GameTooltip")
    RotLatency.TT:SetOwner(UIParent, "ANCHOR_NONE")
    RotLatency.obj = ldb:NewDataObject("RotLatency", {text = "RotLatency",})
    RotLatency.obj.OnTooltipShow = RotLatency.OnTooltip
    RotLatency.obj.OnClick = RotLatency.OnClick
    
    self:RebuildOptions()
end

function RotLatency:OpenConfig()
	AceConfigDialog:SetDefaultSize("RotLatency", 500, 450)
	AceConfigDialog:Open("RotLatency")
end


function RotLatency:ResetTimers() 
    timers = {}
    for book, spells in pairs(self.db.profile.spells) do
        for key, spell in pairs(spells) do
            timers[book .. key] = {}
            timers[book .. key][1] = {start = 0, finish = 0, active = false}
        end
    end
end

function RotLatency:OpenConfig()
	AceConfigDialog:SetDefaultSize("RotLatency", 500, 450)
	AceConfigDialog:Open("RotLatency")
end

function RotLatency:OnEnable()
    frame:SetScript("OnUpdate", self.OnUpdate)
end

function RotLatency:OnDisable()
    frame:SetScript("OnUpdate", nil)
end

do
    local update = 0

    function RotLatency.OnUpdate(_, elapsed)
        
        update = update + elapsed
        
        if update < .1 then
            return
        end
        
        update = 0

        for book, spells in pairs(RotLatency.db.profile.spells) do
            for key, spell in pairs(spells) do
                local start, dur, enabled = GetSpellCooldown(spell.id, book)
                local name = book .. key
                
                local count = #timers[name]
                
                if start ~= 0 and count > 0 and not timers[name][count].active then
                    if count == 1 then
                        timers[name][1].finish = start
                    end
                    timers[name][count + 1] = {}
                    timers[name][count + 1].active = true
                    timers[name][count + 1].start = start
                elseif start == 0 and count > 0 and timers[name][count].active then
                    timers[name][count].active = false
                    timers[name][count].finish = GetTime()
                end
            end
        end
    end
end

function RotLatency.OnTooltip(tooltip)
    tooltip:ClearLines()
    tooltip:AddDoubleLine("Action Latencies")
    local latencyTotal = 0
    count = 0
    
    for book, spells in pairs(RotLatency.db.profile.spells) do
        for key, spell in pairs(spells) do
            local name = book .. key            
            local num = #timers[name]            
            local val = 0

            if num > 2 then
                for i = 1, num - 1 do
                    val = val + timers[name][i + 1].start - timers[name][i].finish
                end
                
                local latency = val / (num - 1)
                
                tooltip:AddDoubleLine(spell.name .. ": " .. string.format("%.2f",  latency * 10))
                
                latencyTotal = latencyTotal + latency                
                
                count = count + 1
            end
        end
    end
    
    if count > 0 then
        tooltip:AddDoubleLine("Average: " .. string.format("%.2f", latencyTotal / count * 10))
    end
    
    tooltip:AddDoubleLine("")
    tooltip:AddDoubleLine("Click to configure. Shift-Click to clear data.")
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
        name = "Add Spell",
        type = "input",
        set = function(info, v)
            for book, spells in pairs(self.db.profile.spells) do
                for i = 1, 500, 1 do
                    local name = GetSpellName(i, book)
                    if name == v then
                        self.db.profile.spells[book][name] = {name = "Spell " .. v, id = i}
                        self:RebuildOptions()
                    end
                end
            end
        end,
        --usage = "Enter the spell's name.",
        --[[validate = function(v) 
            for book, spells in pairs(self.db.profile.spells) do
                for i = 1, 500, 1 do
                    local name = GetSpellName(i, book)
                    if name == v then
                        self:Print("Success " .. name)
                        return true
                    end
                end
            end
            return "No such spell exists in your spell book."
        end,]]
        order = 1
    }
    
    for book, spells in pairs(self.db.profile.spells) do
        for key, spell in pairs(spells) do
            self.options.args.spells.args[key] = {
                name = spell.name,
                type = "group",
                args = {
                    delete = {
                        name = "Delete " .. spell.name,
                        type = "execute",
                        func = function() 
                            self.db.profile.spells[book][key] = nil
                            self:RebuildOptions()
                        end
                    }
                }
            }
        end
    end
    
    self:ResetTimers()
end 