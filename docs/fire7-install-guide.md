# Installing Second Chapter on the Amazon Fire 7 (2022)

This guide replaces Fire OS on an Amazon Fire 7 (2022, 12th generation,
codename `quartz`) with LineageOS 20 (Android 13) and KOReader: no Amazon
apps, no ads, and a battery that lasts about two weeks between charges with
an hour's reading a day.

> **⚠️ Read this first**
>
> - It needs an **unlocked bootloader**. Unlocking uses a third-party tool
>   (see step 1) that depends on a security flaw; it can **permanently break
>   the tablet**, and Amazon may have fixed the flaw in newer Fire OS
>   builds. It was tested on build **RS8338**.
> - It **erases everything on the tablet**, including Fire OS and your Amazon
>   account on it.
> - Copy commands exactly, and stop if anything doesn't look like the guide
>   says.
> - You do this **at your own risk**. It has been tested on one tablet; no
>   guarantees for yours.

## What you get

| | |
|---|---|
| System | LineageOS 20 (Android 13), 64-bit, no Google apps. Noticeably quicker than Fire OS |
| Battery asleep | About 0.16% an hour: roughly three weeks on a charge |
| Battery reading | About 3.6% an hour (screen at about half brightness) |
| Books | KOReader from F-Droid, with an optional Calibre-Web library (OPDS) |
| Kindle and Google books | Through the official web readers in the browser |

Tested and working: Wi-Fi, touch, brightness, sleep and wake. Not tested:
camera, sound, Bluetooth.

You'll need a Linux PC with `adb` (`sudo apt install adb`), a USB-C cable,
and about 10 GB of free disc space.

---

## 1. Unlock the bootloader and install TWRP

Follow the developer's own instructions:

- [MeisterLone/Amazon-Fire7-HD-Rooted-Unlocked (GitHub)](https://github.com/MeisterLone/Amazon-Fire7-HD-Rooted-Unlocked)
- [[KERNEL] Amazon Fire 7 HD 12th-Gen (XDA)](https://xdaforums.com/t/kernel-amazon-fire-7-hd-12th-gen.4800626/)

They aren't covered here. The result should be an unlocked bootloader and
**TWRP** (a recovery system) on the tablet. Start TWRP as the developer
describes. Everything below is done from TWRP, with the tablet plugged into
the PC; check the PC can see it with `adb devices`.

## 2. Back up everything

Nothing below can be undone without these.

1. **TWRP backup:** in TWRP, **Backup**, tick every partition, and save to a
   **microSD card** (all partitions come to about 8.7 GB, more than the
   tablet's free space). Copy the backup folder to the PC, and check it with
   `for f in *.sha2; do sha256sum -c "$f"; done` in that folder: every line
   should say OK.
2. **The partitions TWRP doesn't list**, straight to the PC:

```bash
mkdir -p ~/fire7-dump && cd ~/fire7-dump && for p in lk_real tee1_real tee2_real kb dkb keys misc misc_ext metadata mmcblk0boot1; do adb exec-out "dd if=/dev/block/by-name/$p 2>/dev/null" > $p.img; done; ls -la
```

3. **The preloader.** TWRP links it to `/dev/null` on purpose, so nothing can
   overwrite it by mistake; it can still be read through its device numbers.
   First:

```bash
adb shell cat /sys/block/mmcblk0boot0/dev
```

   It prints two numbers such as `179:32`. Put them in place of `179 32`:

```bash
adb shell "mknod /tmp/boot0 b 179 32" && adb exec-out "dd if=/tmp/boot0 bs=4096 2>/dev/null" > ~/fire7-dump/mmcblk0boot0.img
```

4. **The start-up file and the vendor part**, as they are now:

```bash
adb exec-out "dd if=/dev/block/by-name/boot 2>/dev/null" > ~/fire7-dump/boot.img
```

```bash
adb exec-out "dd if=/dev/block/mapper/vendor bs=4M 2>/dev/null" > ~/fire7-dump/vendor.img
```

Check that no file in `~/fire7-dump` is 0 bytes, then keep the folder and the
TWRP backup somewhere safe, ideally in two places.

## 3. Download LineageOS

From [AndyYan's GSI builds on SourceForge](https://sourceforge.net/projects/andyyan-gsi/files),
open the **lineage-20-td** folder and download the newest file ending in
**`arm64_bvN.img.gz`**: 64-bit, vanilla (no Google apps), no built-in root.
Avoid the look-alikes (`a64_…`, `…-vndklite`, `bgN`, `bvS`). Tested with
`lineage-20.0-20251021-UNOFFICIAL-arm64_bvN.img.gz`. Then unpack it:

```bash
cd ~/Downloads && gunzip -k lineage-20.0-*-arm64_bvN.img.gz && ls -la lineage-20.0-*-arm64_bvN.img
```

It must be smaller than 3,393,028,096 bytes (the tablet's system partition).

**Why not Android 14 (LineageOS 21)?** It doesn't start on this tablet's
kernel (Linux 4.14) without kernel changes that haven't been published.
Android 13 does.

## 4. Turn off verified boot

Otherwise the tablet would only accept Amazon's own system. First check
(this only reads):

```bash
adb shell "head -c 4 /dev/block/by-name/vbmeta; echo; od -A d -t x1 -j 120 -N 4 /dev/block/by-name/vbmeta"
```

Expect `AVB0`, then a line ending in `00 00 00 02` (or `00`). Then:

```bash
adb shell "printf '\003' | dd of=/dev/block/by-name/vbmeta bs=1 seek=123 conv=notrunc && od -A d -t x1 -j 120 -N 4 /dev/block/by-name/vbmeta"
```

Expect a line ending in `00 00 00 03`.

## 5. Write LineageOS

1. In TWRP: **Wipe → Format Data**, type **yes**. This removes Fire OS's data
   and gives a clean storage area to copy the image to.
2. Copy the image to the tablet, then check the copy. The two numbers must
   match:

```bash
adb push ~/Downloads/lineage-20.0-*-arm64_bvN.img /data/system.img
```

```bash
adb shell "sha1sum /data/system.img"; sha1sum ~/Downloads/lineage-20.0-*-arm64_bvN.img
```

3. Write it into the system partition, check it again (replace `SIZE` with
   the image's size in bytes from step 3), and remove the copy:

```bash
adb shell "blockdev --setrw /dev/block/mapper/system && dd if=/data/system.img of=/dev/block/mapper/system bs=4M && sync && echo WRITTEN"
```

```bash
adb shell "head -c SIZE /dev/block/mapper/system | sha1sum"
```

```bash
adb shell rm /data/system.img
```

> **Don't use TWRP's "Install Image"** for this: it only offers the whole
> **Super** partition, which would also wipe the vendor part and the
> partition table. And don't stream the image with `adb exec-in`: in testing
> it arrived damaged.

## 6. Fix Amazon's SELinux naming

Without this, LineageOS stops at "Compiling SELinux policy" and the tablet
restarts into TWRP. Android's security rules come in two halves, the
system's (LineageOS) and the vendor's (Amazon), joined by version number.
Amazon writes its version as `30.0.0` instead of Android's `30.0`, both in
`plat_sepolicy_vers.txt` and in every versioned rule name, so the halves
don't match. One of Amazon's file labels also clashes with Android 13's.

This command corrects all three in the vendor part. It writes the files back
in place, so they keep their security labels:

```bash
adb shell 'mkdir -p /tmp/v && blockdev --setrw /dev/block/mapper/vendor && mount -o rw /dev/block/mapper/vendor /tmp/v && printf "30.0\n" > /tmp/v/etc/selinux/plat_sepolicy_vers.txt && for f in plat_pub_versioned.cil vendor_sepolicy.cil; do sed "s/_30_0_0/_30_0/g" /tmp/v/etc/selinux/$f > /tmp/$f && cat /tmp/$f > /tmp/v/etc/selinux/$f; done; f=/tmp/v/etc/selinux/vendor_sepolicy.cil && sed "/^(genfscon proc \/sys\/kernel\/sched_util_clamp_min_rt_default (u object_r proc_sched_util_clamp_min_rt_default /d" $f > /tmp/vs.cil && cat /tmp/vs.cil > $f && sync; grep -c _30_0_0 /tmp/v/etc/selinux/*.cil; umount /tmp/v'
```

Both counts it prints should be `0`.

## 7. Start LineageOS

In TWRP: **Reboot → System**. The first start can take up to 10 minutes;
then LineageOS's setup screens appear. Connect to Wi-Fi when asked, and skip
anything optional.

If it restarts into TWRP instead, see [Troubleshooting](#troubleshooting).

## 8. Set up KOReader

1. In the browser, install **F-Droid** from **f-droid.org**, then install
   **KOReader** from F-Droid. F-Droid keeps it up to date.
2. In KOReader's file browser, go to the top of the storage, tap **+** →
   **New folder** and make a **Books** folder. Long-press it → **Set as HOME
   folder**. KOReader now starts there.
3. Add a Calibre-Web library, if you have one: tap the **top of the screen**
   → **magnifying glass** → **OPDS catalog** → **+**, with its address (for
   example `http://YOUR-SERVER:8083/opds`) and your username and password.
4. When downloading a book, tap **Choose folder** in the download window and
   pick **Books**. KOReader remembers it.

Books moved within KOReader's file browser (long-press → **Cut**, then
**Paste**) keep their reading positions.

Optional tidying: put KOReader in the dock along the bottom of the home
screen, and in **Settings → Apps** disable apps you'll never use.

## 9. Kindle and Google books

The official web readers work in the browser: **read.amazon.com** (or your
own country's Amazon site) and **play.google.com/books**. With the page
open, the browser's **⋮ → Add to home screen** puts a shortcut next to
KOReader. They need Wi-Fi, and use more battery than KOReader.

---

## Troubleshooting

**It restarts into TWRP instead of starting LineageOS.** The reason is in
the kernel log of the failed attempt, in TWRP:

```bash
adb shell "sed -n '/Opening SELinux policy/,/Restarting system/p' /sys/fs/pstore/console-ramoops"
```

If the log has gaps ("output lines suppressed due to ratelimiting"), Android's
start-up messages are being dropped. Adding `printk.devkmsg=on` to the
start-up file shows them all, using
[`fire7/tools/bootimg-cmdline.py`](../fire7/tools/bootimg-cmdline.py):

```bash
python3 fire7/tools/bootimg-cmdline.py add ~/fire7-dump/boot.img ~/fire7-boot-devkmsg.img "printk.devkmsg=on"
```

```bash
adb push ~/fire7-boot-devkmsg.img /tmp/boot.img && adb shell "dd if=/tmp/boot.img of=/dev/block/by-name/boot && sync"
```

Once it works, put the original back the same way, from
`~/fire7-dump/boot.img`.

**`adb push` fails at the end, or `adb` loses the tablet.** After a Format
Data, `/sdcard` isn't on the tablet's storage: copying there fills TWRP's
memory. Copy to `/data` instead, as in step 5.

## Going back

- **To Fire OS:** in TWRP, restore the backup from step 2 (at least `super`
  and `vbmeta`, and `boot` if changed).
- **To undo only the vendor change** from step 6:

```bash
adb push ~/fire7-dump/vendor.img /data/vendor.img && adb shell "blockdev --setrw /dev/block/mapper/vendor && dd if=/data/vendor.img of=/dev/block/mapper/vendor bs=4M && sync && rm /data/vendor.img"
```

Background, partition layout and test notes:
[devices/fire7-2022.md](devices/fire7-2022.md).
