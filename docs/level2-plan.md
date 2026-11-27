# Nexus 7 development notes: kernel, sleep and start-up

This is the record of the Nexus 7 work, kept for anyone digging into the same
problems: originally a plan for a custom minimal Linux ("Level 2"). In the
end Nura was kept, with a patched kernel and a trimmed start-up. The results
are summarised in [devices/nexus7-grouper.md](devices/nexus7-grouper.md).

Status (November 2026): **done.** Deep sleep fixed, KOReader straight on the
screen, start-up about 30 seconds. Some sections below describe the earlier
set-up (KOReader under the cage display server), since replaced.

## Why

Measurements on the tablet (see [devices/nexus7-grouper.md](devices/nexus7-grouper.md))
show the programs on top (KOReader, cage, Nura's services) use only about
5 mA. Almost all the power goes to the Tegra 3 chip, its memory and power
supplies, which only the kernel's power management controls:

| State | Current |
|---|---|
| Awake, reading | ~400 mA |
| Awake, screen and radios off, nothing running | ~300 mA |
| "Freeze" sleep (what works now) | ~140 mA |
| Deep sleep, as on Android | a few mA |

So the big prize is **working deep sleep**. A slimmer system brings faster
start-up and simplicity, but little battery saving on its own.

## Target design

| Layer | Now (Nura) | Level 2 |
|---|---|---|
| Bootloader | U-Boot (EFI off) | unchanged |
| Kernel | Nura's `linux-postmarketos-grate` 7.0.1 | Our own build from the same source, only needed drivers, sleep debugging enabled, deep sleep fixed |
| System | systemd, NetworkManager, Avahi… (~170 processes) | BusyBox start-up, a handful of processes |
| Display | cage + Wayland + Mesa software OpenGL | Draw straight to the screen (DRM/framebuffer) |
| Reader | KOReader in a Debian chroot (SDL) | KOReader framebuffer mode, or later our own reader |
| Wi-Fi | managed all the time | on only while the library is open |

## Findings so far

From the `v26.06` image and its kernel configuration:

- **Kernel:** Linux 7.0.1, source
  [libre-tegra/linux on Codeberg](https://codeberg.org/libre-tegra/linux),
  commit `bfffc6d6656e87f3de3aa4c09d852849081ef088` (pmaports
  `device/testing/linux-postmarketos-grate`, tag `v26.06`).
- **Sleep mode:** the device tree sets `nvidia,suspend-mode = <1>` on the PMC,
  which is **LP1** (CPU complex off, memory in self-refresh). "Deep" sleep
  (`mem`) is LP1, not LP0.
- **Trusted Foundations:** the device tree has
  `firmware/trusted-foundations` and the kernel has
  `CONFIG_TRUSTED_FOUNDATIONS=y`. On the original bootloader, Nvidia's
  secure firmware ran alongside Linux, and Linux asks it to help enter and
  leave low-power states. **Open question: does U-Boot load it, or remove the
  node?** If the kernel is calling firmware that isn't there, that would
  explain "sleeps but never wakes". (Against this: the CPU idle state CC6,
  which also uses it, works.)
- **Debug tools missing:** `CONFIG_PM_DEBUG` is off (no `/sys/power/pm_test`
  to test sleep stage by stage) and `CONFIG_PSTORE_RAM` is off (no crash log
  that survives a failed wake).
- Already fine: `SUSPEND`, `PM_SLEEP_SMP`, `ARM_TEGRA_CPUIDLE`, `ARM_CPU_SUSPEND`,
  CPU frequency scaling (`ondemand`, down to 51 MHz), memory clock scaling
  (`tegra_actmon`).

## Phases

### 1. Investigate deep sleep (no changes to the tablet)

- [x] On the tablet: does `/proc/device-tree/firmware/trusted-foundations`
      exist? **No: U-Boot removes the `firmware` node** before starting Linux,
      and `dmesg` says nothing about Trusted Foundations. So the kernel runs
      without TF and handles LP1 entirely itself. The "missing firmware"
      theory is ruled out.
- [x] Asked the libre-tegra developers in a Codeberg issue on
      [libre-tegra/user-documentation issue #1](https://codeberg.org/libre-tegra/user-documentation/issues/1)
      (22–23 November 2026).
- Narrowing down: "freeze" sleep already suspends and resumes **all devices**
  successfully, so the fault is most likely in the later stages of LP1
  (taking the other processor cores offline, or the chip-level LP1 entry and
  exit), not in a device driver.
- [ ] Read the Tegra 3 suspend code in the kernel source (`arch/arm/mach-tegra/`,
      `drivers/soc/tegra/pmc.c`) and U-Boot's grouper board code for
      device-tree fix-ups.

### 2. Our own kernel build

- [ ] Cross-compile the same source and configuration, adding
      `PM_DEBUG`, `PM_ADVANCED_DEBUG`, `PSTORE_RAM` (+ console), with a
      reserved memory area for the crash log.
- [ ] Install it as an **extra** start-up option alongside Nura's kernel,
      so the tablet can always go back.
- [ ] Use `pm_test` to find which stage of LP1 fails.

### Results so far (23 November 2026)

- Test kernel `7.0.1-postmarketos-grate-sc` (same source and settings as Nura's,
  plus `PM_DEBUG` and `PSTORE_RAM`) installed alongside Nura's with
  `nura/tools/test-kernel.sh`. It starts and runs normally.
  (A first version of the installer unpacked the modules over Nura's
  `/lib → usr/lib` link and broke the system; repaired from U-Boot's
  storage mode, and the installer fixed.)
- **`pm_test`: all five stages pass** (freezer, devices, platform,
  processors, core). So everything up to the final LP1 step works, and the
  fault is in `tegra_suspend_enter` itself: the low-level LP1 entry and exit.
- **Wake-up sources:** the Power and volume buttons and the magnetic cover
  sensor are Tegra GPIOs marked `wakeup-source`; the clock alarm comes through
  the MAX77663 power chip (interrupt SPI 86).
- **LP2 works.** With a copy of the device tree set to
  `nvidia,suspend-mode = <2>` (only used by the test entry), `mem` sleep
  enters LP2 and wakes with both the clock alarm and the Power button. So the
  wake-up signals reach the chip; **LP1's problem is specifically restoring
  memory (self-refresh exit) and clocks**, which LP2 doesn't do.
- Note: after waking from a sleep started directly (not via logind), logind
  saw the wake-up key press and went straight back to sleep. To check that
  this doesn't happen when logind starts the sleep.
- LP2 battery test: 90% → 84% in 1 h 51 min, about **3.2% an hour**, barely
  better than freeze (3.5%). So the processor section isn't the big drain;
  the memory and core are, which only LP1 handles.
- **The libre-tegra developers replied** (issue #1): U-Boot removes the TF
  node, as found; and LP1 is known not to wake on the Surface RT, another
  Tegra 3, with a fix in
  [libre-tegra/linux pull request #10](https://codeberg.org/libre-tegra/linux/pulls/10).
  The cause: on wake-up the power controller runs from the 12 MHz CLK_M,
  but the CPU power-good wait was calculated for 32 kHz, so 2 ms became a few
  microseconds and CPU0 never came back.
- **With that fix backported** (`nura/kernel/patches/0001-…`), **LP1 wakes on
  the Nexus 7**, with both the clock alarm and the Power button. The log
  shows "Entering suspend state LP1" and a power-good timer of 24000 ticks
  (2000 µs at 12 MHz). Test kernel 3 limits the extra log line to LP1 sleep.
- Nura's own kernel is built with clang and `CONFIG_CFI`, so it would also
  need the pull request's kCFI fix for the assembly sleep functions; our GCC
  test kernel doesn't.
- **LP1 battery test** (test kernel 3, normal sleep set to `mem`): 80% at
  14:00 → 77% at 15:50, about **1.6% an hour**, less than half of freeze
  (3.5%) and LP2 (3.2%). Roughly 65 mA asleep (fuel gauge: 3965 mAh full
  charge, 4400 mAh design), so about 2½ days asleep on a full charge.
  Whole-percent readings, so the true figure could be 1.1–2.2% an hour.

Status after phase 3: **deep sleep fixed** (with the backported patch).
Remaining options: raise the after-sleep switch-off time; make the patched
kernel permanent (image builder, or wait for the fix in Nura's kernel, which
being clang/CFI-built also needs the PR's kCFI change); then phases 4–5.

### 3. Fix deep sleep

Open-ended: depends on what phases 1 and 2 show. Possibilities include the
Trusted Foundations calls, wake-up sources (Power button and clock alarm
through the power chip), or power-chip settings for LP1.

### Switching off (23 November 2026)

- Every power-off restarted the tablet. Cause: the kernel's Tegra power
  controller code restarts the Nexus 7 into a battery-status mode of
  Google's bootloader when USB power seems present (and the smb347 charger
  always says it is). Kernel patch `0002` removes that; tested with test
  kernel 4: the tablet stays off.
- KOReader clears the clock alarm when switching off (the clock is in the
  power chip, so a leftover alarm would start the tablet again), and sleeps
  instead of switching off while charging (tested: works).
- Holding Power for 2 seconds shows a Switch off / Restart / Cancel menu.
  Tested: all three work.

### 4. Minimal system image

BusyBox start-up, Wi-Fi on demand, SSH for maintenance. Built by a script
like today's `nura/build-image.sh`.

**Done instead (27 November 2026): trimming Nura.** Start-up went from 45 to
about 30 seconds by letting KOReader start early, masking unneeded services
and starting without Nura's start-up file system (details in
[devices/nexus7-grouper.md](devices/nexus7-grouper.md)). KOReader
no longer waits for the rest of the system, so a whole new minimal system
would now save little more; not planned.

### 5. KOReader straight to the screen (done)

KOReader's Kobo build with our own device profile: see
[nura/koreader-fb](../nura/koreader-fb/README.md). Working on the tablet
(touch, page turns, volume-button page turns, colours, deep sleep and wake,
power off); the default start-up on the tablet, and what the image builder
now installs, along with the patched kernel (November 2026).

### 6. Later, optional

A reader of our own, if KOReader ever gets in the way.
