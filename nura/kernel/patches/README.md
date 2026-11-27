# Kernel patches

Applied by `../build-kernel.sh` on top of Nura v26.06's kernel source.

| Patch | What it does | Origin |
|---|---|---|
| `0001-pmc-count-LP1-power-good-time-in-clk_m-cycles.patch` | When waking from LP1 deep sleep, the power controller waits for the CPU power supply to settle before switching the CPU back on. That wait was calculated for a 32 kHz clock, but at wake-up the controller runs from the 12 MHz CLK_M, so 2 ms became a few microseconds and CPU0 never came back. This counts it in CLK_M cycles. Also logs the timer value during LP1 sleep (test kernel only) | Backport of a commit in [libre-tegra/linux pull request #10](https://codeberg.org/libre-tegra/linux/pulls/10) (Surface RT suspend fixes), adjusted for the older source |
| `0002-pmc-power-off-grouper-instead-of-restarting.patch` | On power-off, the kernel restarts the Nexus 7 into a battery-status mode of Google's original bootloader if USB seems connected. U-Boot has no such mode and just starts the system again, and the smb347 charger reports USB as connected even with no cable, so switching off always restarted. This leaves power-off to the MAX77663 power chip | Second Chapter (the upstream code is in `tegra_pmc_power_off_handler`) |
| `0003-drm-grate-fbdev-use-XBGR8888.patch` | Sets up the screen (framebuffer) in red-green-blue byte order instead of the usual blue-green-red. KOReader draws straight to the framebuffer in that order, and its EPUB renderer can't swap red and blue itself, so book covers and pictures showed red and blue swapped. The display supports both orders, and the text console is unaffected | Second Chapter |

The pull request also adds kCFI type hashes to Tegra's assembly sleep
functions. Nura's own kernel is built with clang and `CONFIG_CFI`, so it
needs that too; our test kernel is built with GCC, where CFI is off.
