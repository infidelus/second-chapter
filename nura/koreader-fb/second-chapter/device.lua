--[[
Second Chapter: KOReader device profile for the Asus Nexus 7 (2012).

Lets KOReader's Kobo build run straight on the Linux framebuffer, with no
display server, Wayland or OpenGL:

  * Screen: the standard Linux framebuffer (/dev/fb0), a colour LCD.
  * Touch: the Elan touchscreen (/dev/input/event0). Its coordinate range is
    read from the device at start-up and scaled to the screen.
  * Buttons (/dev/input/event2): Power sleeps and wakes (hold for a menu to
    switch off or restart), Volume Down/Up turn pages.
  * Sleep: writes "mem" to /sys/power/state. With the Second Chapter kernel
    that's LP1 deep sleep. KOReader's own auto-sleep and auto-switch-off
    (autosuspend plugin) then work, using the clock alarm (/dev/rtc0).
  * Battery and backlight: see powerd.lua.
  * Switching off on the charger sleeps instead (see UIManagerReady below).

Modelled on KOReader's Sony PRS-T profile (frontend/device/sony-prstux).
--]]

local Generic = require("device/generic/device")
local WakeupMgr = require("device/wakeupmgr")
local ffi = require("ffi")
local logger = require("logger")

local C = ffi.C
require("ffi/posix_h")
require("ffi/linux_input_h")

local UIManager

local function yes() return true end
local function no() return false end

local CONSOLE = "/dev/tty1"
local KDSETMODE, KDGETMODE, KD_GRAPHICS = 0x4B3A, 0x4B3B, 1

local TOUCH_DEV = "/dev/input/event0"
local BUTTONS_DEV = "/dev/input/event2"

ffi.cdef[[
struct sc_input_absinfo {
    int32_t value;
    int32_t minimum;
    int32_t maximum;
    int32_t fuzz;
    int32_t flat;
    int32_t resolution;
};
]]

-- Ask an input device for the range of one of its axes (EVIOCGABS).
local function getAbsRange(path, code)
    local fd = C.open(path, C.O_RDONLY)
    if fd < 0 then
        return nil
    end
    local info = ffi.new("struct sc_input_absinfo")
    -- EVIOCGABS(code) = _IOR('E', 0x40 + code, struct input_absinfo [24 bytes])
    local request = 0x80184540 + code
    local rc = C.ioctl(fd, request, info)
    C.close(fd)
    if rc ~= 0 then
        return nil
    end
    return info.minimum, info.maximum
end

-- Put the screen's text console into graphics mode, so it doesn't draw text
-- (start-up messages) over KOReader. Returns true if it had been in text
-- mode, meaning the screen may need redrawing.
local function consoleGraphicsMode()
    local fd = C.open(CONSOLE, C.O_RDWR)
    if fd < 0 then
        return false
    end
    local mode = ffi.new("int[1]")
    local was_text = C.ioctl(fd, KDGETMODE, mode) == 0 and mode[0] ~= KD_GRAPHICS
    if was_text then
        C.ioctl(fd, KDSETMODE, ffi.cast("unsigned long", KD_GRAPHICS))
    end
    C.close(fd)
    return was_text
end

-- Write a power-off or reboot request for second-chapter-power.path to carry
-- out (KOReader runs inside the Debian environment, so it can't switch off
-- the tablet itself), or carry it out directly if no request file is set.
local function powerAction(action)
    local request_file = os.getenv("SC_POWER_REQUEST")
    if request_file then
        local tmp = request_file .. ".tmp"
        local file = io.open(tmp, "w")
        if file then
            file:write(action, "\n")
            file:close()
            os.rename(tmp, request_file)
            return
        end
        logger.err("Second Chapter: couldn't write power request to", tmp)
    end
    os.execute("sleep 1 && " .. action .. " &")
end

-- Is a charger connected? The charger chip's "online" can't be trusted here
-- (smb347-usb says online=1 even with no cable), so this looks at the
-- charging status of every power supply instead: "Charging" or "Full"
-- means a charger is connected; unplugged they say "Discharging" or
-- "Not charging".
local function isPluggedIn()
    local lfs = require("libs/libkoreader-lfs")
    local base = "/sys/class/power_supply"
    if lfs.attributes(base, "mode") ~= "directory" then
        return false
    end
    for entry in lfs.dir(base) do
        if entry ~= "." and entry ~= ".." then
            local status_file = io.open(base .. "/" .. entry .. "/status")
            local status = status_file and status_file:read("*l")
            if status_file then status_file:close() end
            if status == "Charging" or status == "Full" then
                return true
            end
        end
    end
    return false
end

local SecondChapter = Generic:extend{
    model = "Nexus 7 (2012)",
    isSecondChapter = yes,
    isTouchDevice = yes,
    hasKeys = yes,
    hasFrontlight = yes,
    hasEinkScreen = no,
    hasColorScreen = yes,
    hasBGRFrameBuffer = no, -- see the colour order note in init
    canSuspend = yes,
    -- Sleep on the charger too: there's no reason to keep an LCD lit while
    -- charging, and the battery charges faster with the screen off.
    canPowerSaveWhileCharging = yes,
    canPowerOff = yes,
    canReboot = yes,
    hasWifiToggle = no, -- Wi-Fi is handled by the system for now
    hasOTAUpdates = no,
    display_dpi = 216,
    home_dir = "/home/user/Books",
}

function SecondChapter:init()
    -- First of all, stop the text console drawing over the screen.
    -- (KOReader starts early in start-up, so this is done here rather than
    -- by the start-up script, which would need a slow-to-start helper.)
    consoleGraphicsMode()

    self.screen = require("ffi/framebuffer_linux"):new{device = self, debug = logger.dbg}

    -- Colour order: the Second Chapter kernel (patch 0003) shows the screen
    -- in red-green-blue byte order, which is how KOReader draws, so no swap
    -- is needed. (The screen settings still report the usual blue-green-red
    -- layout, so they can't be relied on.) The setting "second_chapter_bgr"
    -- (true) in settings.reader.lua swaps red and blue in PDFs and pictures,
    -- for a kernel without that patch.
    if G_reader_settings and G_reader_settings:isTrue("second_chapter_bgr") then
        self.hasBGRFrameBuffer = yes
        logger.info("Second Chapter: swapping red and blue (forced by setting)")
    end
    self.powerd = require("device/secondchapter/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = require("device/secondchapter/event_map"),
    }

    self.input:open(TOUCH_DEV, "touchscreen")
    self.input:open(BUTTONS_DEV, "buttons")

    -- Scale touch coordinates to screen pixels.
    local min_x, max_x = getAbsRange(TOUCH_DEV, C.ABS_MT_POSITION_X)
    local min_y, max_y = getAbsRange(TOUCH_DEV, C.ABS_MT_POSITION_Y)
    local width, height = self.screen:getWidth(), self.screen:getHeight()
    if max_x and max_y and max_x > min_x and max_y > min_y then
        logger.info("Second Chapter: touchscreen range", min_x, "-", max_x, "x", min_y, "-", max_y,
                    "for a", width, "x", height, "screen")
        self.input:registerEventAdjustHook(self.input.adjustTouchScale, {
            x = width / (max_x - min_x + 1),
            y = height / (max_y - min_y + 1),
        })
    else
        logger.warn("Second Chapter: couldn't read the touchscreen range; using raw coordinates")
    end

    self.wakeup_mgr = WakeupMgr:new{dev_rtc = "/dev/rtc0"}

    Generic.init(self)
end

function SecondChapter:supportsScreensaver() return true end

function SecondChapter:intoScreenSaver()
    local Screensaver = require("ui/screensaver")
    if not self.screen_saver_mode then
        Screensaver:setup()
        Screensaver:show()
    end
    self.powerd:beforeSuspend()
    -- Darken the screen straight away; sleep itself takes a second or so.
    self.powerd:backlightOffForSleep()
end

function SecondChapter:outofScreenSaver()
    if self.screen_saver_mode then
        local Screensaver = require("ui/screensaver")
        Screensaver:close()
        UIManager:nextTick(function() UIManager:setDirty("all", "full") end)
    end
    self.powerd:afterResume()
end

-- Switch the Wi-Fi radio off (true) or on (false) with the standard Linux
-- radio switch (rfkill), finding it by type rather than by number.
-- NetworkManager notices and reconnects by itself when it's switched back on.
local function setWifiBlocked(blocked)
    local lfs = require("libs/libkoreader-lfs")
    local base = "/sys/class/rfkill"
    if lfs.attributes(base, "mode") ~= "directory" then
        return
    end
    for entry in lfs.dir(base) do
        if entry:match("^rfkill%d+$") then
            local type_file = io.open(base .. "/" .. entry .. "/type")
            local radio_type = type_file and type_file:read("*l")
            if type_file then type_file:close() end
            if radio_type == "wlan" then
                local soft = io.open(base .. "/" .. entry .. "/soft", "w")
                if soft then
                    soft:write(blocked and "1" or "0")
                    soft:close()
                end
            end
        end
    end
end

function SecondChapter:suspend()
    logger.info("Second Chapter: going to sleep")
    -- Wi-Fi off while asleep: saves power and stops network traffic waking us.
    setWifiBlocked(true)
    -- Going to sleep takes a second or two. A button press in that time
    -- must cancel it, not wait in a queue: otherwise, on waking, KOReader
    -- gets that old press as well as the new one, wakes and goes straight
    -- back to sleep. Linux's "wakeup_count" does this: read the count of
    -- wake-up events, write it back, then sleep. If anything happens after
    -- the count was read, writing it back or the sleep itself fails.
    -- This returns once the tablet has woken up again (or at once if the
    -- sleep was cancelled).
    local slept = os.execute("c=$(cat /sys/power/wakeup_count) && echo \"$c\" > /sys/power/wakeup_count && echo mem > /sys/power/state")
    setWifiBlocked(false)
    if slept ~= 0 and slept ~= true then
        -- Cancelled by a button press: KOReader now handles that press,
        -- which wakes the screen.
        logger.info("Second Chapter: sleep cancelled by a wake-up event")
        return
    end
    logger.info("Second Chapter: woken up")
    -- If KOReader's clock alarm woke us (e.g. for automatic switch-off),
    -- carry out the scheduled task now.
    if self.wakeup_mgr:isWakeupAlarmScheduled() and self.wakeup_mgr:wakeupAction(60) then
        logger.info("Second Chapter: woken by a scheduled alarm")
    end
end

function SecondChapter:resume() end

function SecondChapter:powerOff()
    -- Clear any clock alarm (KOReader's automatic switch-off sets one while
    -- asleep). The clock is in the power chip, and a leftover alarm would
    -- switch the tablet back on when it goes off.
    local alarm = io.open("/sys/class/rtc/rtc0/wakealarm", "w")
    if alarm then
        alarm:write("0")
        alarm:close()
    end
    powerAction("poweroff")
end

function SecondChapter:reboot()
    powerAction("reboot")
end

function SecondChapter:initNetworkManager(NetworkMgr)
    -- Wi-Fi is managed by the system for now: report it as on, and
    -- connected whenever wlan0 has an address.
    function NetworkMgr:getNetworkInterfaceName()
        return "wlan0"
    end
    NetworkMgr.isWifiOn = function() return true end
    NetworkMgr.isConnected = NetworkMgr.ifHasAnAddress
end

function SecondChapter:UIManagerReady(uimgr)
    UIManager = uimgr

    -- Safety net: something still starting up could put the console back
    -- into text mode, drawing start-up messages over KOReader. Check a few
    -- times during the first minute, and redraw the screen if it happened.
    for _, delay in ipairs({ 2, 5, 10, 20, 40, 60 }) do
        uimgr:scheduleIn(delay, function()
            if consoleGraphicsMode() then
                logger.info("Second Chapter: console was in text mode; redrawing")
                uimgr:setDirty("all", "full")
            end
        end)
    end

    -- On the charger, "switch off" (from the Power button, the menu, or
    -- automatic switch-off) puts the tablet into deep sleep instead. It keeps
    -- charging, and automatic switch-off tries again later (after the usual
    -- time asleep), by when it may be unplugged. (Originally added because
    -- switching off always restarted the tablet; that turned out to be the
    -- kernel, fixed by kernel patch 0002, but a tablet that's charging has
    -- no reason to be off rather than asleep, so this stays.)
    -- This runs before KOReader's plugins start, so they all use this
    -- version (automatic switch-off finds its alarm by this function).
    local real_poweroff_action = uimgr.poweroff_action
    uimgr.poweroff_action = function()
        if not isPluggedIn() then
            real_poweroff_action()
            return
        end
        logger.info("Second Chapter: on the charger, so sleeping instead of switching off")
        if self.screen_saver_mode then
            -- Woken by the automatic switch-off alarm: straight back to sleep
            UIManager:nextTick(UIManager.event_handlers.Suspend)
            return
        end
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = "On the charger, so sleeping instead of switching off.\n(Switching off would start the tablet again.)",
            timeout = 3,
        })
        UIManager:scheduleIn(3, UIManager.event_handlers.Suspend)
    end
end

function SecondChapter:setEventHandlers(uimgr)
    UIManager.event_handlers.Suspend = function()
        self:intoScreenSaver()
        self:suspend()
    end
    UIManager.event_handlers.Resume = function()
        self:resume()
        self:outofScreenSaver()
    end
    -- Holding Power for 2 seconds shows a small menu: Switch off, Restart
    -- or Cancel. Nothing happens until one is tapped, so an accidental hold
    -- is harmless. (Tapping also means the button has been let go: switching
    -- off while it's still held would make the power chip start the tablet
    -- straight back up.)
    local power_menu
    local function closePowerMenu()
        if power_menu then
            UIManager:close(power_menu)
            power_menu = nil
        end
    end
    local function showPowerMenu()
        self.power_hold_ready = true
        closePowerMenu()
        local ButtonDialog = require("ui/widget/buttondialog")
        power_menu = ButtonDialog:new{
            title = "Power",
            title_align = "center",
            buttons = {
                {
                    {
                        text = "Switch off",
                        callback = function()
                            closePowerMenu()
                            UIManager:nextTick(UIManager.poweroff_action)
                        end,
                    },
                    {
                        text = "Restart",
                        callback = function()
                            closePowerMenu()
                            UIManager:nextTick(UIManager.reboot_action)
                        end,
                    },
                },
                {
                    {
                        text = "Cancel",
                        callback = closePowerMenu,
                    },
                },
            },
        }
        UIManager:show(power_menu)
    end
    UIManager.event_handlers.PowerPress = function()
        self.power_hold_ready = false
        UIManager:scheduleIn(2, showPowerMenu)
    end
    UIManager.event_handlers.PowerRelease = function()
        UIManager:unschedule(showPowerMenu)
        if self.power_hold_ready then
            -- A long press: the menu is showing; wait for a tap.
            self.power_hold_ready = false
            return
        end
        -- A short press: sleep or wake (closing the menu if it was open)
        closePowerMenu()
        if not UIManager._entered_poweroff_stage then
            if self.screen_saver_mode then
                if self.screen_saver_lock then
                    UIManager.event_handlers.Suspend()
                else
                    UIManager.event_handlers.Resume()
                end
            else
                UIManager.event_handlers.Suspend()
            end
        end
    end
end

return SecondChapter
