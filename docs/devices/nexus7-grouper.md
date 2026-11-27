# Asus Nexus 7 (2012), Wi-Fi model (`grouper`)

How to install: [nexus7-install-guide.md](../nexus7-install-guide.md). These
are the background notes.

| | |
|---|---|
| Processor | Nvidia Tegra 3 (T30L), quad-core 1.2 GHz Cortex-A9, 32-bit ARM (`armv7`) |
| Memory | 1 GB |
| Storage | 8, 16 or 32 GB (tested: 8 GB, shown as 7.1 GB) |
| Screen | 800 × 1280 IPS LCD |
| Board | E1565 (tested) or PM269; the image handles both |
| Second Chapter approach | Nura with a patched kernel, and KOReader drawing straight on the screen |

## The system

[Nura](https://nura.eco/) (postmarketOS, renamed in September 2026) supports
this tablet in its generic `nvidia-tegra-armv7` image, with a mainline
("grate") Linux kernel. The image builder starts from Nura's `v26.06`
console image, which has systemd, NetworkManager, `sudo` and Avahi (so
`second-chapter.local` works on the network), and needs U-Boot in place of
Google's bootloader. Nura's wiki lists 3D graphics as missing, which
KOReader doesn't need.

KOReader's Kobo build needs glibc, while Nura uses musl, so KOReader runs
inside a small Debian (trixie) environment at `/opt/second-chapter/debian`
(about 250 MB). It draws straight on the Linux framebuffer through a Second
Chapter device profile ([nura/koreader-fb](../../nura/koreader-fb/README.md)).

## Battery

| State | Current | Battery |
|---|---|---|
| Awake, reading (backlight 15/254, Wi-Fi on) | about 400 mA | about 10% an hour |
| Awake, screen and radios off | about 300 mA | |
| "Freeze" sleep (all Nura's kernel can do) | about 140 mA | about 3.5% an hour |
| Deep sleep (LP1), with kernel patch 0001 | about 65 mA | about 1.6% an hour |

(Fuel gauge: 3965 mAh full charge, 4400 mAh design.) Wi-Fi is switched off
while asleep. KOReader switches the tablet off after 2 hours asleep.

## Findings

### Deep sleep never woke

Writing `mem` to `/sys/power/state` (LP1 on this tablet: memory in
self-refresh, CPU complex off) went to sleep but never woke, not even by
the clock alarm. `pm_test` passed every stage, and LP2 (an adjusted device
tree) woke fine, so the fault was in LP1's own exit. The libre-tegra
developers pointed to the same bug on the Surface RT, another Tegra 3: on
wake-up the power controller runs from the 12 MHz CLK_M, but the CPU
power-good wait was calculated for 32 kHz, so 2 ms became a few
microseconds and CPU0 never came back. Their fix, from
[libre-tegra/linux pull request #10](https://codeberg.org/libre-tegra/linux/pulls/10),
is backported as kernel patch `0001`. Background:
[libre-tegra/user-documentation issue #1](https://codeberg.org/libre-tegra/user-documentation/issues/1)
and [level2-plan.md](../level2-plan.md).

U-Boot removes the Trusted Foundations firmware node from the device tree, so
the kernel handles LP1 entirely itself; that turned out not to matter.

### Switching off restarted the tablet

On power-off, the kernel's Tegra power-controller code restarts the Nexus 7
into a battery-status mode of Google's original bootloader whenever USB power
seems present. U-Boot has no such mode and simply starts the system again,
and the smb347 charger reports `online=1` even with no cable, so every
power-off restarted. Kernel patch `0002` leaves power-off to the MAX77663
power chip. KOReader also clears the clock alarm when switching off, as the
clock is in the power chip and a leftover alarm would switch the tablet back
on.

### Red and blue swapped

The kernel's framebuffer used blue-green-red byte order (XRGB8888), while
KOReader draws in red-green-blue order. KOReader can swap PDFs and pictures
but not EPUB pages, and the driver refuses requests to change the order, so
kernel patch `0003` sets up the screen as XBGR8888 in the grate display
driver (`drivers/gpu/drm/grate`, which this kernel builds instead of
`drivers/gpu/drm/tegra`). The framebuffer settings still report the old
layout, so the device profile doesn't rely on them.

### U-Boot's EFI route

U-Boot built with EFI starts the kernel through the EFI stub, which doesn't
pass the initramfs ("Booting <NULL>", then "Unable to mount root fs"), and
takes about a minute longer. U-Boot built with `EFI_LOADER` disabled uses
`bootz`, which works. The image builder also adds
`initrd=0x83100000,<size>` to the start-up entries, which makes the EFI
route work too until Nura rewrites `extlinux.conf`.

### Start-up time (about 30 seconds)

Nura's usual start-up took about 45 seconds to reach KOReader. These changes
make it about 30:

| Change | Why |
|---|---|
| The login manager ignores the Power button (KOReader handles it), and KOReader's service starts without waiting for the usual start-up (`DefaultDependencies=no`), loading the `evdev` input driver itself | KOReader no longer waits for the login manager, the message bus and the whole basic system: it starts about 10 seconds earlier |
| Plymouth (splash screen), `systemd-boot-update`, `systemd-backlight@…` and `systemd-time-wait-sync` masked | The splash was started again after KOReader and, when closed, put text over it; the others are useless here (or, for the backlight, could fight KOReader's own setting) |
| KOReader puts the console into graphics mode itself (`KDSETMODE` in the device profile), checking again during the first minute | Starting Python to do it took about 3 seconds and competed with KOReader |
| The kernel starts straight from the system partition, without Nura's start-up file system (`second-chapter-fast` entry: `root=/dev/mmcblk0p2 rootfstype=ext4 rootwait`) | Linux's part fell from 8.4 to 4.1 seconds. The storage, partition-table and ext4 drivers are built into the kernel. A fresh image still uses it once, to expand the system partition, then `second-chapter-fastboot.service` switches |

What's left: about 2 s before U-Boot shows anything, 3 s of U-Boot, a few
seconds for Linux to unpack and start its display, Linux's start-up, then
KOReader loading (4–5 s).

### A quick second Power press

Pressing Power again while the tablet was still going to sleep (a second or
two) did nothing; the next press then woke it and put it straight back to
sleep, because the quick press had been queued and was replayed on waking.
KOReader's sleep now uses Linux's `wakeup_count` (read the count of wake-up
events, write it back, then write `mem`), so a press in that time cancels the
sleep instead.

### Worn storage

Writing images over U-Boot's USB storage mode, a few writes arrived with one
megabyte wrong (about 750–800 bytes), in a different place each time; the
megabyte read back correctly once rewritten. The first time, the damage hit
the kernel modules' index and Debian's program loader, so the tablet started
but without Wi-Fi, touch or KOReader. The install guide's read-back check
catches this.

### Wi-Fi

Nura's Wi-Fi driver for this tablet doesn't work with 802.11w (Protected
Management Frames): set it to off or optional on the router.

## Hardware revision check (optional)

Not needed for the install, as the image works out the revision itself. From
TWRP (`adb shell`), per Nura's wiki:

```bash
find /sys/devices/ | grep -c max776 && echo You have E1565
```

```bash
find /sys/devices/ | grep -c tps6591 && echo You have PM269
```

## Sources

- [Nura wiki: Google Nexus 7 2012 (asus-grouper)](https://wiki.nura.eco/wiki/Google_Nexus_7_2012_(asus-grouper))
- [libre-tegra U-Boot migration guide](https://codeberg.org/libre-tegra/user-documentation/src/branch/master/asus-google-grouper-tilapia.md)
- [libre-tegra/linux pull request #10](https://codeberg.org/libre-tegra/linux/pulls/10)
