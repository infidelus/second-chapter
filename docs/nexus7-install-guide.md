# Installing Second Chapter on the Nexus 7 (2012)

This guide replaces Android (stock or LineageOS) on a Nexus 7 (2012, Wi-Fi
model, `grouper`) with Nura (formerly postmarketOS) and KOReader. When it's
finished, the tablet starts straight into KOReader, sleeps properly, and
behaves like a dedicated e-reader.

> **⚠️ Read this first**
>
> - This **erases everything on the tablet**.
> - Part B replaces the tablet's bootloader (the software that starts it up).
>   The backups taken in Part B are **the only way** to return the tablet to
>   Android later. Keep them safe, in more than one place.
> - Copy commands exactly, and stop if anything doesn't look like the guide
>   says.
> - You do this **at your own risk**. It has been tested on one tablet
>   (E1565 board, 8 GB); no guarantees for yours.

## What you get

| | |
|---|---|
| Start-up | About 30 seconds from pressing Power to the book list |
| Deep sleep | Works (with this project's kernel patch): about 1.6% battery an hour, so roughly 2½ days asleep on a charge |
| Reading | About 10% battery an hour (screen on, Wi-Fi on) |
| Power button | Short press: sleep and wake. Hold: a Switch off / Restart menu |
| Books | KOReader, with an optional Calibre-Web library (OPDS) |

## Overview

| Part | What you do | Time |
|---|---|---|
| A | Get ready | 10 minutes |
| B | Replace the bootloader with U-Boot (and back up the tablet) | 1 hour |
| C | Build the Second Chapter image on a PC | 30 to 90 minutes, mostly waiting |
| D | Write the image to the tablet | 20 minutes |
| E | First start and using the tablet | 10 minutes |

Part C can be done before Part B: it doesn't touch the tablet.

---

## Part A: Get ready

You'll need:

- A **Linux PC** with a **USB 3.0 port** (usually blue inside). This guide
  was written on Linux Mint; other Debian or Ubuntu-based systems should work
  the same way.
- A good micro-USB cable, plugged **straight into the PC** (not through a
  hub: hubs caused trouble in testing).
- The tablet charged to **at least 50%**.
- About **8 GB of free disc space** on the PC.
- Your Wi-Fi name and password.

Copy anything you want to keep off the tablet first.

### Get the Second Chapter files

Open a terminal and run:

```bash
sudo apt install git
```

```bash
git clone https://github.com/infidelus/second-chapter.git ~/second-chapter
```

---

## Part B: Replace the bootloader with U-Boot

This part follows the official
[U-Boot migration guide for the Nexus 7 (2012)](https://codeberg.org/libre-tegra/user-documentation/src/branch/master/asus-google-grouper-tilapia.md)
from the libre-tegra developers, with explanations added. If anything here
differs from that guide, **the official guide wins**. There are two
deliberate differences, both marked below.

> **Permissions:** if a command says "permission denied" or can't find the
> tablet, run it again with `sudo` in front.

### B1. Install the tools

```bash
sudo dpkg --add-architecture i386
```

```bash
sudo apt update
```

```bash
sudo apt install autoconf bash bison build-essential fastboot flex gcc-arm-none-eabi git libgnutls28-dev libncurses-dev libssl-dev make python3-cryptography python3-dev python3-setuptools python3-usb swig libc6:i386 libstdc++6:i386 zlib1g:i386
```

### B2. Download and build the tools

```bash
mkdir ~/grouper
```

```bash
cd ~/grouper
```

```bash
git clone --recursive https://codeberg.org/libre-tegra/fusee-tools.git
```

```bash
git clone https://codeberg.org/libre-tegra/re-crypt.git
```

**Difference 1:** U-Boot's full history is very large, so `--depth 1`
fetches only the latest version.

```bash
git clone --depth 1 https://source.denx.de/u-boot/u-boot
```

```bash
wget https://codeberg.org/clamor-s/bootloader-collection/raw/branch/master/asus-google-grouper-tilapia-4.23-bootloader.bin
```

```bash
mv asus-google-grouper-tilapia-4.23-bootloader.bin fusee-tools/bootloader.bin
```

Now build U-Boot. This takes a few minutes.

**Difference 2:** U-Boot is built with its "EFI" start-up route switched off
(the `scripts/config` and `olddefconfig` lines). Through that route, U-Boot
doesn't pass Nura's start-up file system to the kernel (the image builder
adds a workaround, but a Nura kernel update undoes it), and starting takes
much longer. Without EFI, U-Boot uses the traditional route (`bootz`), which
just works. This is the combination Second Chapter is tested with.

```bash
cd ~/grouper/u-boot
```

```bash
make mrproper
```

```bash
make ARCH=arm CROSS_COMPILE=arm-none-eabi- grouper_defconfig
```

```bash
./scripts/config --disable EFI_LOADER
```

```bash
make ARCH=arm CROSS_COMPILE=arm-none-eabi- olddefconfig
```

```bash
make ARCH=arm CROSS_COMPILE=arm-none-eabi- -j4
```

Copy the result to where the other tools need it:

```bash
cp u-boot-dtb-tegra.bin ../re-crypt
```

```bash
cp u-boot-dtb-tegra.bin ../fusee-tools
```

Build the helper programs:

```bash
cd ~/grouper/fusee-tools/payloads
```

```bash
make ARCH=arm CROSS_COMPILE=arm-none-eabi- -j1
```

```bash
cd ~/grouper/fusee-tools
```

### B3. Back up the tablet (essential)

This saves the tablet's unique, encrypted partitions. **Without these files
the tablet can never go back to Android.**

1. Connect the USB cable to the PC's **USB 3.0** port, but not to the tablet
   yet.
2. Power the tablet **off**.
3. Hold **Volume Up** and, while holding it, plug the cable into the tablet.
4. The screen stays black. That's expected. Check the PC can see it:

```bash
lsusb
```

You should see a line containing `ID 0955:7330 NVIDIA Corp. APX`.

Then run these one at a time, from `~/grouper/fusee-tools`:

```bash
./run_bootloader.sh -s T30 -t ./bct/grouper.bct -b bootloader.bin
```

The tablet's screen should light up with the Google logo. Then:

```bash
./utils/nvflash_v1.13.87205 --resume --rawdeviceread 0 2688 bricksafe.img
```

```bash
./utils/nvflash_v1.13.87205 --resume --read EKS eks.img
```

```bash
./utils/nvflash_v1.13.87205 --resume --read PER factory-config.img
```

```bash
./utils/nvflash_v1.13.87205 --resume --read MDA mda.img
```

```bash
./utils/nvflash_v1.13.87205 --resume --read GP1 gp1.img
```

```bash
./utils/nvflash_v1.13.87205 --resume --read GPT gpt.img
```

You should now have **six** `.img` files in `~/grouper/fusee-tools`:
`bricksafe.img`, `eks.img`, `factory-config.img`, `mda.img`, `gp1.img` and
`gpt.img`. (The 3G model, `tilapia`, has a seventh; this guide is for the
Wi-Fi model.)

**Copy all six to at least two other places**, such as a USB stick and cloud
storage, before carrying on.

### B4. Read the tablet's secret boot key (SBK)

1. Put the tablet back into APX mode: unplug it, power it off, then hold
   **Volume Up** while plugging the cable in.
2. Run:

```bash
./dump_sbk.sh -s T30
```

Look for a line like:

```
Dumped SBK [ 0xXXXXXXXX 0xXXXXXXXX 0xXXXXXXXX 0xXXXXXXXX ]
```

The tablet reboots, which is normal. **Copy the four values between the
square brackets** into a text file and keep it with the backups.

### B5. Prepare U-Boot for your tablet

Replace `<your sbk>` with the four values from B4, exactly as shown (for
example `0x12345678 0x9abcdef0 0x...`):

```bash
cd ~/grouper/re-crypt
```

```bash
./re-crypt.py --dev grouper --sbk <your sbk> --split
```

```bash
cp bct.img ebt.img ../fusee-tools
```

```bash
cd ~/grouper/fusee-tools
```

### B6. Flash U-Boot

1. Put the tablet into APX mode again (power off, hold **Volume Up**, plug
   in).
2. **Hold Volume Down** on the tablet and, while holding it, run:

```bash
./run_bootloader.sh -s T30 -t ./bct/grouper.bct
```

3. The **U-Boot boot menu** should appear on the tablet. If it doesn't, try
   B6 again.
4. Use the **volume buttons** to choose **Fastboot**, and press **Power** to
   select it.
5. On the PC, run these one at a time:

```bash
fastboot flash 0.1 bct.img
```

```bash
fastboot flash 0.2 ebt.img
```

```bash
fastboot reboot
```

U-Boot is now installed, and the tablet won't start Android any more.

> **If the tablet won't switch on with the Power button afterwards:** plug in
> the USB cable, which starts it. The official guide says reflashing U-Boot
> fixes this.

---

## Part C: Build the Second Chapter image

This runs entirely on the PC. It builds the Second Chapter kernel (Nura's
own, plus three fixes: deep sleep, switching off, and screen colours),
downloads the official Nura image, adds KOReader and your settings, and saves
a ready-made image file.

Install what the builder needs:

```bash
sudo apt install qemu-user-static curl xz-utils fdisk e2fsprogs
```

and, for building the kernel:

```bash
sudo apt install gcc-arm-linux-gnueabihf bc bison flex libssl-dev kmod cpio zstd git
```

Run the builder:

```bash
cd ~/second-chapter
```

```bash
sudo ./nura/build-image.sh
```

It asks for:

- **Wi-Fi network name** and **password**, so the tablet connects by itself.
- **A new tablet password.** This replaces Nura's default password
  (`147147`). It's only needed for SSH (remote access from the PC) and admin
  tasks.
- **A Calibre-Web OPDS address**, username and password (optional: press
  Enter to skip). If given, the library is already in KOReader's catalogue
  list when the tablet starts.

The first build takes 30 to 90 minutes, mostly compiling the kernel. Later
builds reuse the kernel unless the kernel recipe (`nura/kernel`) has changed.
The finished image is:

```
~/second-chapter/build/second-chapter-nexus7.img
```

---

## Part D: Write the image to the tablet

1. Power the tablet off.
2. Hold **Volume Down**, then press and release **Power**.
3. When the **U-Boot boot menu** appears, choose **mount internal storage**
   with the volume buttons and press **Power**.
4. Connect the tablet to the PC. It appears like a USB drive.

Find the tablet's name:

```bash
lsblk -o NAME,SIZE,MODEL
```

It's the one called **UMS disk 0** (about 7, 15 or 29 GB), for example
`sdb`. **Double-check it**: never choose the computer's own drive. Then,
replacing `sdX` with that name:

```bash
sudo dd if=$HOME/second-chapter/build/second-chapter-nexus7.img of=/dev/sdX bs=4M oflag=direct status=progress
```

```bash
sync
```

Writing takes about 6 to 10 minutes. If `dd` finishes in seconds, the tablet
wasn't connected in storage mode and `dd` has made an ordinary file called
`/dev/sdX` instead: remove it with `sudo rm /dev/sdX`, unplug and replug the
tablet, and write again.

### Check the write (don't skip this)

Read the image back from the tablet and compare (a few minutes). Don't start
the tablet before this check. An old tablet's storage can have worn patches:
in testing, a few writes arrived with one megabyte damaged, which left the
tablet starting but KOReader, Wi-Fi and the touchscreen not working.

```bash
img=$HOME/second-chapter/build/second-chapter-nexus7.img; size=$(stat -c %s "$img"); sudo dd if=/dev/sdX bs=4M count=$(( (size + 4194303) / 4194304 )) iflag=direct status=progress | cmp -n $size - "$img" && echo "VERIFIED: the tablet matches the image"
```

If it says **VERIFIED**, carry on. If it reports a difference instead, list
the damaged megabytes:

```bash
img=$HOME/second-chapter/build/second-chapter-nexus7.img; size=$(stat -c %s "$img"); sudo dd if=/dev/sdX bs=4M count=$(( (size + 4194303) / 4194304 )) iflag=direct 2>/dev/null | cmp -l -n $size - "$img" | awk '{ print "MB " int(($1-1)/1048576) }' | uniq -c
```

Rewrite each listed megabyte (replace `30` with its number), then check it
reads back correctly three times (each line should print `0`):

```bash
sudo dd if="$img" of=/dev/sdX bs=1M skip=30 seek=30 count=1 oflag=direct
```

```bash
for i in 1 2 3; do sudo dd if=/dev/sdX bs=1M skip=30 count=1 iflag=direct 2>/dev/null | cmp -l - <(dd if="$img" bs=1M skip=30 count=1 2>/dev/null) | wc -l; done
```

If many megabytes are damaged, write the whole image again, ideally with a
different cable or USB port.

### Restart the tablet

Unplug the cable, then hold **Power** until the tablet switches off. Press
**Power** again to start it.

---

## Part E: First start and using the tablet

- The **first start takes a few minutes**: the system expands itself to fill
  the tablet's storage. From the second start on, it takes about 30 seconds.
- KOReader appears full screen, drawing straight on the screen with no
  display server in between.
- If you skipped the Calibre-Web question in Part C, add a library in
  KOReader: tap the **top of the screen** → **magnifying glass** → **OPDS
  catalog** → **+**, then enter its address (for example
  `http://YOUR-SERVER:8083/opds`, replacing `YOUR-SERVER` with the server's
  name or address) and your Calibre-Web username and password. Downloaded
  books go in the **Books** folder.

### The Power button

- **Short press:** deep sleep (screen off). Press again to wake, which takes
  about a second; KOReader is just as you left it. Pressing again while it's
  still going to sleep cancels the sleep.
- **Hold for 2 seconds:** a small menu with **Switch off**, **Restart** and
  **Cancel**. Nothing happens until one is tapped, so an accidental hold does
  no harm. Switching off saves your place.
- **Hold for about 10 seconds:** forces the tablet off, if it ever stops
  responding.

While charging, switching off puts the tablet into deep sleep instead, and
it keeps charging.

### Automatic sleep and switching off

KOReader handles both:

- After **2 minutes** without a touch or button press, the tablet sleeps
  (on the charger too).
- After **2 hours** asleep, it switches itself off completely, saving your
  place first.

Both times can be changed in KOReader's settings (the **cog** tab, under
**Device**), and set to never.

### Connecting from the PC (SSH)

```bash
ssh user@second-chapter.local
```

Use the tablet password chosen in Part C. If `second-chapter.local` doesn't
work, use the tablet's IP address from your router's list of devices.

---

## Troubleshooting

**KOReader doesn't appear.** Connect by SSH and look at its log:

```bash
journalctl -b -u second-chapter-fb --no-pager | tail -n 50
```

**The tablet won't connect to Wi-Fi.** Nura's Wi-Fi driver for this tablet
doesn't work with "802.11w / Protected Management Frames" (PMF). Set that
option on your router to **off** or **optional**.

**After a system update, deep sleep stops waking up.** If `sudo apk upgrade`
installs a new Nura kernel, Nura rewrites the start-up menu
(`/boot/extlinux/extlinux.conf`) and the Second Chapter entries disappear,
so the tablet starts on Nura's kernel, whose deep sleep doesn't wake. Check
with `uname -r`: it should end in `-sc`. If not, the simplest fix is to
rebuild and rewrite the image; `nura/tools/test-kernel.sh` (`install`, then
`use-test`) can also add the Second Chapter kernel back on its own.

**The tablet doesn't start after a change to the start-up menu.** The menu
is on the boot partition. Put the tablet in **mount internal storage** mode
(Part D), then on the PC mount the first partition (`sudo mount /dev/sdX1
/mnt`) and edit or restore `extlinux/extlinux.conf`. The entries are:
`second-chapter-fast` (the normal one, without Nura's start-up file system),
`second-chapter` (with it: used for the first start) and `postmarketOS`
(Nura's own kernel, kept as a spare).

---

## Going back to Android

The
[official guide's "Reverting back" section](https://codeberg.org/libre-tegra/user-documentation/src/branch/master/asus-google-grouper-tilapia.md#reverting-back)
explains how to restore the backups from Part B. After that, a factory image
or LineageOS can be installed again.

---

## Updating U-Boot later

U-Boot's menu has an **update bootloader** option. It reads
`u-boot-dtb-tegra.bin` from the tablet's boot partition and installs it,
re-encrypting it for the tablet as it goes. No APX mode or `nvflash` is
needed.

1. Build the new `u-boot-dtb-tegra.bin` (see B2).
2. On the tablet: hold **Volume Down** and press **Power**, then choose
   **mount internal storage**, and connect it to the PC.
3. On the PC (check the tablet's name with `lsblk` first, here `sdb`):

```bash
sudo mkdir -p /mnt/tabletboot && sudo mount /dev/sdb1 /mnt/tabletboot
```

```bash
sudo cp ~/grouper/u-boot/u-boot-dtb-tegra.bin /mnt/tabletboot/
```

```bash
sudo umount /mnt/tabletboot
```

4. On the tablet, press a volume button to leave storage mode and return to
   the menu. Choose **update bootloader** and wait for "Bootloader written
   successfully", then press a button to restart.

**If the new U-Boot doesn't start**, put the tablet in APX mode and repeat
step B6 with the `bct.img` and `ebt.img` made before.
