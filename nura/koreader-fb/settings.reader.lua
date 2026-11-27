-- Second Chapter: starting settings for KOReader on the framebuffer.
-- KOReader rewrites this file itself once it has run.
return {
    ["home_dir"] = "/home/user/Books",
    ["download_dir"] = "/home/user/Books",
    ["start_with"] = "filemanager",
    ["collate"] = "access",
    ["auto_save_settings_interval_minutes"] = 2,
    -- KOReader's own auto-sleep (2 minutes) and auto-switch-off (2 hours)
    ["auto_suspend_timeout_seconds"] = 120,
    ["autoshutdown_timeout_seconds"] = 7200,
    -- Screen brightness (percent); the backlight never goes fully off
    ["frontlight_intensity"] = 10,
}
