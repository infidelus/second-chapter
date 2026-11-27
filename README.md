# Second Chapter

Turning old tablets into simple, battery-friendly e-readers.

Second Chapter gives old tablets a second life as dedicated e-readers,
instead of a drawer or a skip. Each tablet starts straight into
[KOReader](https://koreader.rocks/), with no clutter, no notifications and as
little battery drain as possible.

## Supported tablets

| Tablet | What it runs | Battery | Guide |
|---|---|---|---|
| **Asus Nexus 7 (2012)**, Wi-Fi model (`grouper`) | [Nura](https://nura.eco/) (formerly postmarketOS) Linux with a patched kernel, and KOReader drawing straight on the screen | About 2½ days asleep, about 10 hours reading | [Install guide](docs/nexus7-install-guide.md) |
| **Amazon Fire 7 (2022)**, 12th generation (`quartz`) | LineageOS 20 (Android 13) with KOReader. Needs an unlocked bootloader | About three weeks asleep, about a day of reading | [Install guide](docs/fire7-install-guide.md) |

Each was tested on one tablet. Background and test notes:
[Nexus 7](docs/devices/nexus7-grouper.md),
[Fire 7](docs/devices/fire7-2022.md).

Any other Android tablet can at least run KOReader as an app:
[trying KOReader](docs/step-1-try-koreader.md).

## What's here

**Nexus 7 (2012).** A script on a Linux PC builds a ready-to-write image:
Nura's official image plus KOReader, a Second Chapter kernel, your Wi-Fi
details and (optionally) a [Calibre-Web](https://github.com/janeczku/calibre-web)
library. Fixes that made it work well as a reader:

- **Deep sleep.** Nura's kernel never woke from deep sleep on this tablet.
  A backported fix from the libre-tegra developers makes it work, cutting
  sleep drain from 3.5% to 1.6% an hour.
- **Switching off** really switches off (it used to restart), and **colours**
  are right in KOReader.
- **KOReader straight on the screen,** without a display server, through a
  device profile: touch, page turns with the volume buttons, Power button
  sleep and a Switch off / Restart menu, automatic sleep and switch-off.
- **Start-up in about 30 seconds** from pressing Power to the book list.

**Amazon Fire 7 (2022).** Once unlocked with a third-party tool, the tablet
can run a generic Android system image (GSI). Amazon's SELinux policy uses
an odd version naming (`30.0.0` instead of `30.0`) that stops any GSI from
starting; the guide shows how to correct it. LineageOS 20 then runs
noticeably quicker than Fire OS, with KOReader from F-Droid.

## Project layout

```
second-chapter/
├── nura/                    Nexus 7 (Nura)
│   ├── build-image.sh         Builds the ready-to-write image on a Linux PC
│   ├── kernel/                Kernel recipe and patches (deep sleep, power-off, colours)
│   ├── koreader-fb/           KOReader's device profile, patches and starting settings
│   ├── rootfs/                Files added to the tablet (start-up services and scripts)
│   └── tools/                 Helpers for testing and diagnosis on the tablet
├── fire7/tools/             Fire 7 helper (boot image command line)
└── docs/                    Install guides, device notes and development notes
```

## A note on DRM

This project doesn't remove DRM (copy protection) from books and won't
include tools for doing so. It reads DRM-free books, for example from your
own Calibre-Web library, and uses the official web readers for everything
else.

## Thanks

Second Chapter builds on other people's work:

- [KOReader](https://koreader.rocks/), the reading app.
- [Nura](https://nura.eco/) (formerly postmarketOS), and the
  [libre-tegra](https://codeberg.org/libre-tegra) developers, for U-Boot,
  the mainline kernel for Tegra tablets, and the LP1 wake-up fix
  ([pull request #10](https://codeberg.org/libre-tegra/linux/pulls/10)).
- [MeisterLone](https://github.com/MeisterLone/Amazon-Fire7-HD-Rooted-Unlocked),
  for the Fire 7 (2022) unlock.
- [AndyYan](https://sourceforge.net/projects/andyyan-gsi/files) and
  [TrebleDroid](https://github.com/TrebleDroid), for the LineageOS GSIs.

## How this was made

Much of the code and documentation was written with the help of an AI
assistant (Anthropic's Claude), working with the project's owner, who did
all the testing on real tablets. Everything described as working here was
tested on the hardware.

## Disclaimer

This is a hobby project, not affiliated with Amazon, Asus, Google, Nura or
KOReader. Replacing a tablet's bootloader or system can break it for good.
You follow these guides at your own risk.

## Licence

[GNU GPL-3.0](LICENSE), except:

- the kernel patches in `nura/kernel/patches/`, which are changes to Linux
  and so under the [GPL-2.0](nura/kernel/patches/LICENSE), and
- the KOReader device profile in `nura/koreader-fb/`, which builds on
  KOReader's code and so is under KOReader's licence, the
  [AGPL-3.0](nura/koreader-fb/LICENSE).

Issues and improvements are welcome.
