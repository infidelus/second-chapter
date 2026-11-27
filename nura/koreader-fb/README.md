# KOReader device profile for the Nexus 7 (2012)

KOReader's **Kobo build** with a Second Chapter **device profile**, so it
draws straight on the Linux framebuffer and reads the touchscreen and buttons
directly: no display server, Wayland or OpenGL.

| File | Purpose |
|---|---|
| `patches/1-second-chapter-device.lua` | Start-up patch: makes KOReader load this profile instead of its Kobo detection |
| `patches/2-autosuspend-while-charging.lua` | Lets KOReader's auto-sleep work on the charger (it otherwise postpones sleep while charging) |
| `second-chapter/device.lua` | The profile: framebuffer, touch (range read from the device and scaled), buttons, deep sleep through `/sys/power/state` (with `wakeup_count`, so a button press while going to sleep cancels it), clock-alarm wake-ups, the Power-button menu, Wi-Fi off while asleep (rfkill), and the console kept in graphics mode |
| `second-chapter/powerd.lua` | Battery (bq27541) and backlight, so KOReader's brightness slider works. The backlight never goes below 2%, as an LCD at 0 is black |
| `second-chapter/event_map.lua` | Power sleeps and wakes (hold for a Switch off / Restart menu); Volume Down/Up turn pages |
| `settings.reader.lua` | Starting settings, including KOReader's auto-sleep (2 minutes) and auto-switch-off (2 hours asleep) |

The image builder (`nura/build-image.sh`) installs these into
`/home/user/.config/koreader-fb` on the tablet. KOReader is started by
[`second-chapter-fb.service`](../rootfs/etc/systemd/system/second-chapter-fb.service)
and [`run-koreader-fb`](../rootfs/usr/local/libexec/second-chapter/run-koreader-fb).

KOReader's Kobo build needs glibc, so it runs inside a small Debian
environment on the tablet. The builder downloads the latest stable build and
checks it against the SHA-1 that KOReader publishes in
`koreader-kobo-latest-stable.zsync`.

To change a profile file on a running tablet, copy it to
`~/.config/koreader-fb/second-chapter/` and restart KOReader:

```bash
sudo systemctl restart second-chapter-fb
```

## Licence

These files build on KOReader's code, so they're under KOReader's own
licence, the [GNU AGPL-3.0](LICENSE).
