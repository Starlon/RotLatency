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
            actionbars = {}
		}
	})
        	
	self.options = {
		type = "group",
		args = {
			actionbars = {
                type = "group",
                name = "Action Bars",
                args = {}
            }
		}
	}
	
	LibStub("AceConfig-3.0"):RegisterOptionsTable("RotLatency", self.options)
	if InterfaceOptionsFrame:IsResizable() then
		AceConfigDialog:AddToBlizOptions("RotLatency")
	end
	self:RegisterChatCommand("rotlatency", "OpenConfig")

    RotLatency.TT = CreateFrame("GameTooltip")
    RotLatency.TT:SetOwner(UIParent, "ANCHOR_NONE")
    RotLatency.obj = ldb:NewDataObject("RotLatency", {text = "RotLatency",})
    RotLatency.obj.OnTooltipShow = RotLatency.OnTooltip
    
    self:RebuildOptions()
end

function RotLatency:ResetTimers() 
    timers = {}
    for actionbarkey, actionbar in pairs(self.db.profile.actionbars) do
        for actionkey, action in pairs(actionbar.actions) do
            timers[actionbar.val * 12 + action.val] = {}
            timers[actionbar.val * 12 + action.val][1] = {start = 0, finish = 0, active = false}
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
        
        local classOffset = 0
        local stance = GetShapeshiftForm(false)

        if (playerClass == "Warrior" or playerClass == "Druid" or playerClass == "Rogue" or playerClass == "Priest") and stance > 0 then
            classOffset = 5 + stance 
        end
    
        for barkey, actionbar in pairs(RotLatency.db.profile.actionbars) do
            for actionkey, action in pairs(actionbar.actions) do
        
                local row            
                if actionbar.val == 0 then
                    row = classOffset + actionbar.val
                else
                    row = actionbar.val
                end
                
                local start, dur, enable = 0, 0, 0
                local typ, id, subType, globalID = GetActionInfo(row * 12 + action.val + 1)
                if typ == "spell" then 
                    start, dur, enabled = GetSpellCooldown(id, BOOKTYPE_SPELL)
                elseif typ == "macro" then
                
                elseif typ == "item" then
                    start, dur, enabled = GetItemCooldown(id)
                end
                
                local n = actionbar.val * 12 + action.val
                
                local count = #timers[n]
                
                if start ~= 0 and count > 0 and not timers[n][count].active then
                    RotLatency:Print("1 element: " .. row * 12 + action.val + 1)
                    RotLatency:Print("bar: " .. actionbar.name .. ", action: " .. action.name .. ", active -- start: " .. start ..", dur " .. dur .. ", count " .. count)
                    timers[n][count + 1] = {}
                    timers[n][count + 1].active = true
                    timers[n][count + 1].start = GetTime()
                elseif start == 0 and count > 0 and timers[n][count].active then
                    RotLatency:Print("2 element: " .. row * 12 + action.val + 1)
                    RotLatency:Print(actionbar.name .. ", inactive")
                    timers[n][count].active = false
                    timers[n][count].finish = GetTime()
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
    for barkey, actionbar in pairs(RotLatency.db.profile.actionbars) do
        for actionkey, action in pairs(actionbar.actions) do
            local n = actionbar.val * 12 + action.val
            local num = #timers[n]
            local val = 0
            if num > 2 then
                for i = 0, num do
                    val = val + timers[n][num - 1].start - timers[n][num - 2].finish
                end
                latency = val / num
                tooltip:AddDoubleLine(action.name .. ": " .. latency .. "ms")
                latencyTotal = latencyTotal + latency
                count = count + 1
            end
        end
    end
    if count > 0 then
        tooltip:AddDoubleLine("Average: " .. latencyTotal / count .. "ms")
    end
end

function RotLatency:RebuildOptions()
    self.options.args.actionbars.args = {}
    
    self.options.args.actionbars.args.add = {
        name = "Add Actionbar",
        type = "input",
        set = function(info, v)
            self.db.profile.actionbars[v] = {name = "Actionbar " .. v, val = tonumber(v) - 1, actions = {}}
            self:RebuildOptions()
        end,
        pattern = "%d",
        usage = "Requires a numeric value representing the numbered action bar.",
        order = 1
    }
    
    self:Print(self.db.profile.actionbars["1"])
    for actionbarkey, actionbar in pairs(self.db.profile.actionbars) do
        self:Print("test " .. actionbar.name .. ": " .. actionbarkey)
        self.options.args.actionbars.args[actionbarkey] = {
            name = actionbar.name,
            type = "group",
            args = {
                add = {
                    name = "Add Action",
                    type = "input",
                    set = function(info, v)
                        self.db.profile.actionbars[actionbarkey].actions[v] = {val = tonumber(v) - 1, name = v}
                        self:RebuildOptions()
                    end,
                    pattern = "%d",
                    usage = "Requires a numeric value representing the action bar's action element -- 1 through 12 are valid.",
                    order = 1
                },
                delete = {
                    name = "Delete Actionbar",
                    type = "execute",
                    func = function()
                        self.db.profile.actionbars[actionbarkey] = nil
                        self:RebuildOptions()
                    end
                }
            }
        }
        for actionkey, action in pairs(actionbar.actions) do
            self:Print("Action " .. actionkey)
            self.options.args.actionbars.args[actionbarkey].args[actionkey] = {
                type = "group",
                name = "Action " .. action.name,
                args = {
                    name = {
                        type = "input",
                        name = "Action Name",
                        set = function(info, v)
                            self.db.profile.actionbars[actionbarkey].actions[actionkey].name = v
                            self:RebuildOptions()
                        end,
                        order = 1
                    },
                    delete = {
                        type = "execute",
                        name = "Delete Action",
                        func = function() 
                            self.db.profile.actionbars[actionkey].actions[actionkey] = nil
                            self:RebuildOptions() 
                        end
                    }
                }
            }
        end
    end
    self:ResetTimers()
end 