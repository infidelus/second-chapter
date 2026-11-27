--[[
Second Chapter: use our own device profile for the Nexus 7 (2012).

KOReader works out which device it's running on when it first loads its
"device" module. Its Kobo build only knows Kobo e-readers, so this patch,
which KOReader runs early at start-up, tells it to load our profile (in the
"second-chapter" folder next to this one) instead.

The "1-" at the start of the name means it runs before the device is set up.
--]]

local DataStorage = require("datastorage")

local profile_dir = DataStorage:getDataDir() .. "/second-chapter/"

package.preload["device/secondchapter/powerd"] = function()
    return dofile(profile_dir .. "powerd.lua")
end

package.preload["device/secondchapter/event_map"] = function()
    return dofile(profile_dir .. "event_map.lua")
end

package.preload["device"] = function()
    local device = dofile(profile_dir .. "device.lua")
    device:init()
    return device
end
