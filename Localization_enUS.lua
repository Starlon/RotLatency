local AceLocale = LibStub:GetLibrary("AceLocale-3.0")
local L = AceLocale:NewLocale("RotLatency", "enUS", true)
if not L then return end

L["GCD Spell"] = true
L["Note that this is mandatory for things to work! RotLatency will use this spell to track global cooldown. It should be a spell on the GCD, but does not have a cooldown of its own. Find Herbs is a good example."] = true
L["Time Gap"] = true
L["Enter the value in seconds for which to give up waiting for the next spell cast."] = true
L["Spells to Track"] = true
L["Action Latencies"] = true
L["ms"] = true
L["Average: "] = true
L["Click to configure. Shift-Click to clear data. Ctrl-Click to toggle %s."] = true
L["Add Spell"] = true
L["Enter the spell's name."] = true
L["No such spell exists in your spell book."] = true
L["Track GCD"] = true
L["Delete "] = true
L["Display Limit"] = true
L["Enter how many records back to display."] = true
L["Usage: /rotlatency <command>"] = true
L["Where <command> is one of 'config' or 'stats' without quotes."] = true
L["Nothing to display"] = true
L["RotLatency is %s."] = true
L["This determines how fast the cooldowns are examined; the format is in milliseconds."] = true
L["Refresh Rate"] = true
