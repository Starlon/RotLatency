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
            spells = { [BOOKTYPE_SPELL] = { }, [BOOKTYPE_PET] = { } },
            gcd = 0,
            gap = 10
		}
	})
        	
	self.options = {
		type = "group",
		args = {
            gcd = {
                type = "input",
                name = "GCD Spell",
                set = function(info, v)
                    for book, _ in pairs(self.db.profile.spells) do
                        for i = 1, 500 do
                            local name = GetSpellName(i, book)
                            if name == v then
                                self.db.profile.gcd = i
                            end
                        end
                    end
                end,
                get = function()
                    for book, _ in pairs(self.db.profile.spells) do
                        local name = GetSpellName(self.db.profile.gcd, book)
                        if name then
                            return name
                        end
                    end
                end,
                usage = "RotLatency will use this spell to track global cooldown. It should be a spell on the GCD, but does not have a cooldown of its own.",
                order = 1
            },
            newLine = {
                type = "header",
                name = "",
                order = 2
            },
            gap = {
                type = "input",
                name = "Time Gap",
                set = function(info, v)
                    self.db.profile.gap = tonumber(v)
                end,
                get = function() 
                    return tostring(self.db.profile.gap)
                end,
                pattern = "%d",
                usage = "Enter the value in seconds for which to give up waiting for the next spell cast.",
                order = 3
            },
			spells = {
                type = "group",
                name = "Spells to Track",
                args = {},
                order = 4
            }
		}
	}
	
	LibStub("AceConfig-3.0"):RegisterOptionsTable("RotLatency", self.options)
	
	AceConfigDialog:AddToBlizOptions("RotLatency")
    
	self:RegisterChatCommand("rotlatency", "OpenConfig")

    self.TT = CreateFrame("GameTooltip")
    self.TT:SetOwner(UIParent, "ANCHOR_NONE")
    self.obj = ldb:NewDataObject("RotLatency", {text = "RotLatency",})
    self.obj.OnTooltipShow = RotLatency.OnTooltip
    self.obj.OnClick = RotLatency.OnClick
    
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self:RebuildOptions()
end

function RotLatency:OpenConfig()
	AceConfigDialog:SetDefaultSize("RotLatency", 500, 450)
	AceConfigDialog:Open("RotLatency")
end


function RotLatency:ResetTimers() 
    timers = {}
end

function RotLatency:GetGCD()
    if self.db.profile.gcd == "" then return end
    
    
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

function RotLatency:SPELL_UPDATE_COOLDOWN()

end

do
    local update = 0
    local gcd = {start = 0, finished = 0, active = false}
    
    function RotLatency.OnUpdate(_, elapsed)
        
        update = update + elapsed
        
        if update < .1 then
            return
        end
        
        update = 0
        
        local now = GetTime()

        local gcdStart, gcdDur, gcdEnabled
        
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
            gcd.finished = now
            gcd.active = true
        elseif gcdStart == 0 and gcdEnabled == 1 and gcd.active then
            gcd.finished = now
            gcd.active = false
        end
        
        for book, spells in pairs(RotLatency.db.profile.spells) do
            for key, spell in pairs(spells) do
                local start, dur, enabled = GetSpellCooldown(spell.id, book)

                local name = book .. key
                
                if not timers[name] then
                    timers[name] = {}
                    timers[name][0] = {active=false, start=0, finish=0}
                end
                
                local count = #timers[name]
                
                local timer = timers[name][count]
            
                if gcd.finished < now - RotLatency.db.profile.gap and count > 1 and not timer.hasGap then
                    timer.hasGap = true
                end
            
                if start ~= 0 and enabled == 1 and not timer.active and not spell.gcd then
                    timers[name][count + 1] = {}
                    timers[name][count + 1].active = true
                    timers[name][count + 1].start = now
                    timers[name][count + 1].gcd = gcdDur
                    if timer.hasGap then
                        RotLatency:Print("hasGap " .. count)
                        timer.finish = now
                        RotLatency:Print("hasGap #2 " .. name)
                        timer.hasGap = false
                    end
                elseif start == 0 and enabled == 1 and count > 0 and timer.active then
                    timer.active = false
                    timer.finish = now
                    local delta = timer.finish - timer.start - .5
                    if delta < timer.gcd and not spell.gcd then
                        timers[name][count] = nil
                    end
                end
            end
        end            
    end
end

function RotLatency.OnTooltip(tooltip)
    tooltip:ClearLines()
    tooltip:AddDoubleLine("Action Latencies")
    local latencyTotal = 0
    local count = 0
    
    for book, spells in pairs(RotLatency.db.profile.spells) do
        for key, spell in pairs(spells) do
            local name = book .. key            
            local num = 0
            local val = 0
            
            if timers[name] then
                num = #timers[name]
            end
            
            if num > 2 then
                for i = 2, num, 1 do
                    val = val + timers[name][i].start - timers[name][i - 1].finish
                end
                
                local latency = val / num
                
                tooltip:AddDoubleLine(spell.name .. ": " .. string.format("%.2f",  latency * 100) .. "ms")
                
                latencyTotal = latencyTotal + latency                
                
                count = count + 1
            end
        end
    end
    
    if count > 0 then
        tooltip:AddDoubleLine("Average: " .. string.format("%.2f", latencyTotal / count * 100) .. "ms")
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
                        self.db.profile.spells[book][name] = {name = "Spell " .. v, id = i, gcd=false}
                        self:RebuildOptions()
                    end
                end
            end
        end,
        usage = "Enter the spell's name.",
        validate = function(info, v) 
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
                        name = "Track GCD",
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
                        name = "Delete " .. spell.name,
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