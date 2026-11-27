--[[
Second Chapter: let KOReader's automatic sleep work on the charger too.

KOReader's auto-sleep plugin postpones sleeping for as long as the battery
is charging (a choice made for e-ink readers). On the Nexus 7's LCD there's
no reason to stay lit on the charger, and the battery charges faster with
the screen off.

This wraps the plugin's scheduling step so that, just while it decides
when to sleep, the battery is reported as not charging. Everything else
(including the battery icon) still sees the real charging state.

The "2-" at the start of the name means KOReader runs this once the device
is set up, before plugins are loaded.
--]]

local Device = require("device")
local logger = require("logger")
local userpatch = require("userpatch")

userpatch.registerPatchPluginFunc("autosuspend", function(AutoSuspend)
    local original_schedule = AutoSuspend._schedule
    if type(original_schedule) ~= "function" then
        logger.warn("Second Chapter: autosuspend plugin has no _schedule; not patched")
        return
    end
    AutoSuspend._schedule = function(self, ...)
        local powerd = Device.powerd
        local own_isCharging = rawget(powerd, "isCharging")
        powerd.isCharging = function() return false end
        local ok, err = pcall(original_schedule, self, ...)
        powerd.isCharging = own_isCharging -- put back exactly as it was
        if not ok then
            error(err, 0)
        end
    end
    logger.info("Second Chapter: auto-sleep now also works while charging")
end)
