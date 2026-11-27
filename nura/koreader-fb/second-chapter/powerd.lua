--[[
Second Chapter: battery and backlight for the Nexus 7 (2012).

Battery: the bq27541 fuel gauge. Backlight: the standard Linux backlight
device, so KOReader's own brightness slider works.
--]]

local BasePowerD = require("device/generic/powerd")

local BATTERY = "/sys/class/power_supply/bq27541-0/"
local BACKLIGHT = "/sys/class/backlight/backlight/"

local SecondChapterPowerD = BasePowerD:new{
    fl_min = 0,
    fl_max = 100,
}

-- On an LCD, a backlight of 0 means a black, unusable screen (unlike an
-- e-ink reader's frontlight). So never go below this many percent, even when
-- KOReader turns its "frontlight" off.
local MIN_VISIBLE_PERCENT = 2
-- Brightness to use if none has been chosen yet.
local DEFAULT_PERCENT = 10

local function writeBrightness(raw)
    local file = io.open(BACKLIGHT .. "brightness", "w")
    if file then
        file:write(tostring(raw))
        file:close()
    end
end

function SecondChapterPowerD:init()
    self.backlight_max = self:read_int_file(BACKLIGHT .. "max_brightness")
    if not self.backlight_max or self.backlight_max <= 0 then
        self.backlight_max = 255
    end
    self.backlight_min = math.max(1, math.floor(self.backlight_max * MIN_VISIBLE_PERCENT / 100 + 0.5))

    -- Start with the brightness last chosen (or a sensible default), so the
    -- screen is never dark at start-up.
    local wanted = G_reader_settings:readSetting("frontlight_intensity") or DEFAULT_PERCENT
    if wanted < MIN_VISIBLE_PERCENT then
        wanted = DEFAULT_PERCENT
    end
    self:setIntensityHW(wanted)
end

-- Backlight: KOReader uses 0-100; the hardware uses 0-max_brightness.
function SecondChapterPowerD:frontlightIntensityHW()
    local raw = self:read_int_file(BACKLIGHT .. "brightness") or 0
    return math.floor(raw * 100 / self.backlight_max + 0.5)
end

function SecondChapterPowerD:setIntensityHW(intensity)
    local raw = math.floor(intensity * self.backlight_max / 100 + 0.5)
    if raw < self.backlight_min then
        raw = self.backlight_min -- dimmest visible level, never fully off
    end
    writeBrightness(raw)
    -- Remember the chosen brightness for next time.
    if intensity >= MIN_VISIBLE_PERCENT then
        G_reader_settings:saveSetting("frontlight_intensity", intensity)
    end
end

function SecondChapterPowerD:getCapacityHW()
    return self:read_int_file(BATTERY .. "capacity")
end

function SecondChapterPowerD:isChargingHW()
    return self:read_str_file(BATTERY .. "status") == "Charging"
end

function SecondChapterPowerD:isChargedHW()
    return self:read_str_file(BATTERY .. "status") == "Full"
end

function SecondChapterPowerD:beforeSuspend()
    -- Stop input and tell KOReader we're going to sleep (it saves your place).
    self.device:_beforeSuspend()
end

-- Switch the backlight fully off straight away when going to sleep, so the
-- screen goes dark the moment Power is pressed (sleep itself takes a second
-- or so). This is the only time the backlight goes fully off.
function SecondChapterPowerD:backlightOffForSleep()
    writeBrightness(0)
end

function SecondChapterPowerD:afterResume()
    self:invalidateCapacityCache()
    -- Put the brightness back as it was before sleeping.
    local wanted = G_reader_settings:readSetting("frontlight_intensity") or DEFAULT_PERCENT
    self:setIntensityHW(wanted)
    -- Restore input and tell KOReader we're awake again.
    self.device:_afterResume()
end

return SecondChapterPowerD
