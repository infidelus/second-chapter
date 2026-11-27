#!/usr/bin/env bash
#
# Second Chapter: build a ready-to-flash Nura image for the Nexus 7 (2012)
#
# This script runs on your Linux PC (written for Linux Mint). It:
#   1. builds the Second Chapter kernel (Nura's, plus the LP1 deep sleep fix),
#      unless you already have one
#   2. downloads the official Nura "console" image for Tegra tablets and
#      checks it's genuine (SHA-256 checksum)
#   3. adds KOReader (its Kobo build, in a small Debian environment) with the
#      Second Chapter device profile, so it draws straight on the screen
#   4. adds SSH, your Wi-Fi details and a new tablet password
#   5. makes the Second Chapter kernel the default, keeping Nura's as a spare
#   6. sets the tablet to start straight into KOReader
#
# The result is a single .img file you write to the tablet's storage.
#
# Usage:
#   sudo ./build-image.sh
#
# It asks for your Wi-Fi name, Wi-Fi password and a new tablet password.
# Nothing you type is saved anywhere except inside the image itself.
#
# Requirements (install once):
#   sudo apt install qemu-user-static curl xz-utils fdisk e2fsprogs
# and, to build the kernel (skip if KERNEL_DIR points to one already built):
#   sudo apt install gcc-arm-linux-gnueabihf bc bison flex libssl-dev kmod cpio zstd git
#
set -euo pipefail

# --- Settings you might want to change --------------------------------------

NURA_RELEASE="${NURA_RELEASE:-v26.06}"          # Nura release (stable)
NURA_DEVICE="${NURA_DEVICE:-nvidia-tegra-armv7}" # Generic Tegra 2/3 image
NURA_UI="console"                                # Smallest image, no desktop
DEBIAN_SUITE="${DEBIAN_SUITE:-trixie}"           # Debian release for KOReader
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
KOREADER_OTA="https://ota.koreader.rocks"
KOREADER_ZSYNC="koreader-kobo-latest-stable.zsync" # Describes the latest Kobo build
# Time zone: the same as this PC's, unless set (e.g. TIMEZONE=Europe/Paris)
TIMEZONE="${TIMEZONE:-$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo UTC)}"
TABLET_HOSTNAME="${TABLET_HOSTNAME:-second-chapter}"
EXTRA_SPACE_MB=1536                              # Room added for KOReader
WORK_DIR="${WORK_DIR:-$PWD/build}"
OUTPUT_IMAGE="${OUTPUT_IMAGE:-$WORK_DIR/second-chapter-nexus7.img}"
# Folder with vmlinuz-sc and modules-sc.tar.gz (from nura/kernel/build-kernel.sh).
# Left as it is, the kernel is built there automatically, and rebuilt
# whenever the kernel recipe (nura/kernel) changes. Point it elsewhere to use
# a kernel you've built yourself, as it is.
KERNEL_DIR="${KERNEL_DIR:-$WORK_DIR/kernel/out}"

# --- Fixed values -----------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$SCRIPT_DIR/rootfs"
IMAGES_URL="https://images.nura.eco/bpo/$NURA_RELEASE/$NURA_DEVICE/$NURA_UI"
TABLET_USER="user"                               # Account name in Nura images
DEBIAN_DIR="/opt/second-chapter/debian"          # Path inside the image
KO_DIR="/opt/koreader-fb"                        # KOReader, inside the Debian environment
KERNEL_RELEASE="7.0.1-postmarketos-grate-sc"     # Second Chapter kernel

ROOT_MNT=""
LOOP_DEV=""

# --- Helpers ----------------------------------------------------------------

info() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
fail() { printf '\n\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

is_mounted() {
    awk -v p="$1" '$2 == p { found = 1 } END { exit !found }' /proc/mounts
}

# Undo all mounts, even if the script stops part-way through.
cleanup() {
    set +e
    if [ -n "$ROOT_MNT" ]; then
        local deb="$ROOT_MNT$DEBIAN_DIR"
        for m in "$deb/dev/pts" "$deb/dev" "$deb/sys" "$deb/proc" \
                 "$ROOT_MNT/dev/pts" "$ROOT_MNT/dev" "$ROOT_MNT/sys" "$ROOT_MNT/proc"; do
            is_mounted "$m" && umount "$m"
        done
        if [ -f "$ROOT_MNT/etc/resolv.conf.second-chapter" ]; then
            mv -f "$ROOT_MNT/etc/resolv.conf.second-chapter" "$ROOT_MNT/etc/resolv.conf"
        fi
        is_mounted "$ROOT_MNT" && umount "$ROOT_MNT"
        rmdir "$ROOT_MNT" 2>/dev/null
    fi
    [ -n "$LOOP_DEV" ] && losetup -d "$LOOP_DEV" 2>/dev/null
}
trap cleanup EXIT

# Run a command inside the Nura image (emulated ARM).
in_nura() {
    chroot "$ROOT_MNT" /usr/bin/env -i \
        PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
        ${http_proxy:+http_proxy="$http_proxy"} \
        ${https_proxy:+https_proxy="$https_proxy"} \
        "$@"
}

# Run a command inside the Debian environment within the image.
in_debian() {
    chroot "$ROOT_MNT$DEBIAN_DIR" /usr/bin/env -i \
        PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
        DEBIAN_FRONTEND=noninteractive \
        ${http_proxy:+http_proxy="$http_proxy"} \
        "$@"
}

mount_system_dirs() {
    local target="$1"
    mkdir -p "$target/proc" "$target/sys" "$target/dev"
    is_mounted "$target/proc" || mount -t proc proc "$target/proc"
    is_mounted "$target/sys"  || mount -t sysfs sysfs "$target/sys"
    is_mounted "$target/dev"  || mount --bind /dev "$target/dev"
    mkdir -p "$target/dev/pts"
    is_mounted "$target/dev/pts" || mount -t devpts devpts "$target/dev/pts"
}

ask() {
    # ask VARIABLE "Prompt" [secret]
    local var="$1" prompt="$2" secret="${3:-}" value=""
    if [ -n "${!var:-}" ]; then return; fi
    while [ -z "$value" ]; do
        if [ -n "$secret" ]; then
            read -r -s -p "$prompt: " value; echo
        else
            read -r -p "$prompt: " value
        fi
    done
    printf -v "$var" '%s' "$value"
}

# --- 1. Checks --------------------------------------------------------------

[ "$(id -u)" -eq 0 ] || fail "Please run with sudo:  sudo $0"

for tool in curl xz sfdisk losetup e2fsck resize2fs chroot sha256sum truncate; do
    command -v "$tool" >/dev/null || fail "'$tool' is missing. Install with:
    sudo apt install qemu-user-static curl xz-utils fdisk e2fsprogs"
done

if [ ! -e /proc/sys/fs/binfmt_misc/qemu-arm ]; then
    fail "ARM emulation isn't set up. Install it with:
    sudo apt install qemu-user-static
then run this script again. (If it's already installed, try restarting the PC.)"
fi

[ -d "$OVERLAY_DIR" ] || fail "Can't find $OVERLAY_DIR. Run the script from inside the second-chapter folder."

info "Second Chapter image builder"
note "This needs about 8 GB of free disc space and an internet connection."
note "Building takes roughly 30 to 90 minutes: the kernel is compiled (unless"
note "already built), and the tablet's ARM processor is emulated on your PC."

ask WIFI_SSID "Wi-Fi network name"
ask WIFI_PASSWORD "Wi-Fi password" secret
if [ -z "${TABLET_PASSWORD:-}" ]; then
    while true; do
        ask TABLET_PASSWORD "New password for the tablet (for SSH and admin tasks)" secret
        read -r -s -p "Type it again: " confirm; echo
        [ "$confirm" = "$TABLET_PASSWORD" ] && break
        echo "The passwords didn't match. Please try again."
        TABLET_PASSWORD=""
    done
fi

# Optional: add a Calibre-Web library to KOReader's OPDS catalogue list.
if [ -z "${CALIBRE_OPDS_URL+set}" ]; then
    echo "Calibre-Web OPDS address, for example http://YOUR-SERVER:8083/opds"
    read -r -p "(or press Enter to skip): " CALIBRE_OPDS_URL
fi
if [ -n "$CALIBRE_OPDS_URL" ]; then
    ask CALIBRE_USER "Calibre-Web username"
    ask CALIBRE_PASSWORD "Calibre-Web password" secret
fi

mkdir -p "$WORK_DIR"

# --- 2. The Second Chapter kernel --------------------------------------------

# A fingerprint of the kernel recipe (build script, settings and patches),
# so a kernel built from an older recipe is rebuilt automatically.
kernel_recipe=$(cd "$SCRIPT_DIR/kernel" && cat build-kernel.sh config-* patches/*.patch 2>/dev/null \
    | sha256sum | awk '{print $1}')

if [ -f "$KERNEL_DIR/vmlinuz-sc" ] && [ -f "$KERNEL_DIR/modules-sc.tar.gz" ] \
   && { [ "$KERNEL_DIR" != "$WORK_DIR/kernel/out" ] \
        || [ "$(cat "$KERNEL_DIR/recipe.sha256" 2>/dev/null)" = "$kernel_recipe" ]; }; then
    info "Using the kernel already built in $KERNEL_DIR"
else
    info "Building the Second Chapter kernel (15 to 60 minutes)"
    for tool in arm-linux-gnueabihf-gcc bc bison flex git zstd; do
        command -v "$tool" >/dev/null || fail "'$tool' is missing. To build the kernel, install:
    sudo apt install gcc-arm-linux-gnueabihf bc bison flex libssl-dev kmod cpio zstd git"
    done
    "$SCRIPT_DIR/kernel/build-kernel.sh" "$WORK_DIR/kernel" >"$WORK_DIR/kernel-build.log" 2>&1 \
        || fail "Building the kernel failed. See $WORK_DIR/kernel-build.log"
    KERNEL_DIR="$WORK_DIR/kernel/out"
    [ -f "$KERNEL_DIR/vmlinuz-sc" ] || fail "The kernel build didn't produce vmlinuz-sc. See $WORK_DIR/kernel-build.log"
    echo "$kernel_recipe" > "$KERNEL_DIR/recipe.sha256"
fi

# --- 3. Download the Nura image ---------------------------------------------

info "Finding the latest Nura $NURA_RELEASE image for $NURA_DEVICE"
build_dir=$(curl -fsSL "$IMAGES_URL/" | grep -oE 'href="[0-9]{8}-[0-9]{4}/"' \
    | sed -E 's/href="([^/]+)\/"/\1/' | sort | tail -n 1)
[ -n "$build_dir" ] || fail "Couldn't find any images at $IMAGES_URL"
image_name=$(curl -fsSL "$IMAGES_URL/$build_dir/" | grep -oE 'href="[^"/]+\.img\.xz"' \
    | head -n 1 | sed -E 's/href="([^"]+)"/\1/')
[ -n "$image_name" ] || fail "Couldn't find the image file in $IMAGES_URL/$build_dir/"
note "Found $image_name"

image_xz="$WORK_DIR/$image_name"
if [ ! -f "$image_xz" ]; then
    info "Downloading (about 200 MB)"
    curl -fL --progress-bar -o "$image_xz.part" "$IMAGES_URL/$build_dir/$image_name"
    mv "$image_xz.part" "$image_xz"
fi

info "Checking the download is genuine"
expected=$(curl -fsSL "$IMAGES_URL/$build_dir/$image_name.sha256" | awk '{print $1}')
actual=$(sha256sum "$image_xz" | awk '{print $1}')
if [ "$expected" != "$actual" ]; then
    rm -f "$image_xz"
    fail "Checksum mismatch: the download is damaged. It has been deleted; run the script again."
fi
note "Checksum OK"

# --- 4. Unpack and make room ------------------------------------------------

info "Unpacking the image"
rm -f "$OUTPUT_IMAGE"
xz -dc "$image_xz" > "$OUTPUT_IMAGE.part"

info "Adding ${EXTRA_SPACE_MB} MB of space for KOReader"
truncate -s "+${EXTRA_SPACE_MB}M" "$OUTPUT_IMAGE.part"
# Move the backup partition table to the new end, then grow partition 2
# (the system partition) to fill the space.
sfdisk -q --relocate gpt-bak-std "$OUTPUT_IMAGE.part" 2>/dev/null
echo ',+' | sfdisk -q --no-reread -N 2 "$OUTPUT_IMAGE.part" 2>/dev/null

part_line=$(sfdisk -d "$OUTPUT_IMAGE.part" | grep -F "$OUTPUT_IMAGE.part2 :")
root_start=$(sed -E 's/.*start= *([0-9]+).*/\1/' <<<"$part_line")
root_size=$(sed -E 's/.*size= *([0-9]+).*/\1/' <<<"$part_line")
[ -n "$root_start" ] && [ -n "$root_size" ] || fail "Couldn't read the image's partition table."

LOOP_DEV=$(losetup -f --show -o $((root_start * 512)) --sizelimit $((root_size * 512)) "$OUTPUT_IMAGE.part")
e2fsck -fy "$LOOP_DEV" >/dev/null 2>&1 || true
resize2fs "$LOOP_DEV" >/dev/null 2>&1 || fail "Couldn't enlarge the system partition."

ROOT_MNT=$(mktemp -d "$WORK_DIR/root.XXXXXX")
mount "$LOOP_DEV" "$ROOT_MNT"
mount_system_dirs "$ROOT_MNT"

# Use the PC's DNS settings while building; the original is put back afterwards.
mv "$ROOT_MNT/etc/resolv.conf" "$ROOT_MNT/etc/resolv.conf.second-chapter"
cat /etc/resolv.conf > "$ROOT_MNT/etc/resolv.conf"

in_nura /bin/true 2>/dev/null || fail "Can't run ARM programs. Is qemu-user-static installed?"

# --- 5. Install packages in Nura --------------------------------------------

if [ -n "${SC_APK_HTTP:-}" ]; then
    # Only for building behind a proxy that inspects HTTPS. Alpine packages
    # are signed, so they are still verified.
    cp "$ROOT_MNT/etc/apk/repositories" "$ROOT_MNT/etc/apk/repositories.second-chapter"
    sed -i 's#^https://#http://#' "$ROOT_MNT/etc/apk/repositories"
fi

info "Installing SSH, debootstrap and Python"
in_nura apk update -q
# python3: used at start-up to put the screen's console into graphics mode
in_nura apk add -q openssh debootstrap python3

# --- 6. Create the Debian environment and install KOReader ------------------

info "Creating the Debian environment for KOReader (the slowest step)"
if [ ! -x "$ROOT_MNT$DEBIAN_DIR/usr/bin/apt-get" ]; then
    rm -rf "$ROOT_MNT$DEBIAN_DIR"
    in_nura debootstrap --variant=minbase --arch=armhf \
        --keyring=/usr/share/keyrings/debian-archive-keyring.gpg \
        "$DEBIAN_SUITE" "$DEBIAN_DIR" "$DEBIAN_MIRROR" >"$WORK_DIR/debootstrap.log" 2>&1 \
        || fail "Creating the Debian environment failed. See $WORK_DIR/debootstrap.log"
fi
mount_system_dirs "$ROOT_MNT$DEBIAN_DIR"
cat /etc/resolv.conf > "$ROOT_MNT$DEBIAN_DIR/etc/resolv.conf"

# KOReader's Kobo build includes its own libraries and only needs the basic
# system libraries (glibc), which Debian's minimal base already has.
info "Downloading KOReader (Kobo build)"
# The .zsync file starts with a short text header naming the file and its SHA-1
curl -fsSL -o "$WORK_DIR/koreader.zsync" "$KOREADER_OTA/$KOREADER_ZSYNC" \
    || fail "Couldn't reach KOReader's download site."
zsync_header=$(head -c 2048 "$WORK_DIR/koreader.zsync" | tr -d '\r' | grep -a -E '^(Filename|SHA-1): ' || true)
koreader_file=$(sed -n 's/^Filename: //p' <<<"$zsync_header" | head -n 1)
koreader_sha1=$(sed -n 's/^SHA-1: //p' <<<"$zsync_header" | head -n 1)
case "$koreader_file" in
    koreader-kobo-*.targz) ;;
    *) fail "Couldn't find the latest KOReader Kobo build." ;;
esac
[ -n "$koreader_sha1" ] || fail "Couldn't find the latest KOReader Kobo build's checksum."
note "Latest is $koreader_file"
if [ ! -f "$WORK_DIR/$koreader_file" ]; then
    curl -fL --progress-bar -o "$WORK_DIR/$koreader_file.part" "$KOREADER_OTA/$koreader_file"
    mv "$WORK_DIR/$koreader_file.part" "$WORK_DIR/$koreader_file"
fi
# KOReader publishes the SHA-1 of the unpacked archive
if [ "$(zcat "$WORK_DIR/$koreader_file" | sha1sum | awk '{print $1}')" != "$koreader_sha1" ]; then
    rm -f "$WORK_DIR/$koreader_file"
    fail "The KOReader download is damaged. It has been deleted; run the script again."
fi
note "Checksum OK"

info "Installing KOReader"
mkdir -p "$ROOT_MNT$DEBIAN_DIR$KO_DIR"
tar -xzf "$WORK_DIR/$koreader_file" -C "$ROOT_MNT$DEBIAN_DIR$KO_DIR"
[ -x "$ROOT_MNT$DEBIAN_DIR$KO_DIR/koreader/luajit" ] || fail "KOReader didn't unpack as expected."
rm -rf "$ROOT_MNT$DEBIAN_DIR/var/lib/apt/lists/"*

# Give the Debian environment the same reader account as Nura, so file
# ownership matches.
uid=$(in_nura id -u "$TABLET_USER")
gid=$(in_nura id -g "$TABLET_USER")
if ! in_debian id -u "$TABLET_USER" >/dev/null 2>&1; then
    in_debian groupadd -g "$gid" "$TABLET_USER"
    in_debian useradd -u "$uid" -g "$gid" -M -d "/home/$TABLET_USER" -s /bin/sh "$TABLET_USER"
fi
mkdir -p "$ROOT_MNT$DEBIAN_DIR/home"

# --- 7. Configure the tablet ------------------------------------------------

info "Adding the Second Chapter start-up files"
cp -r "$OVERLAY_DIR/." "$ROOT_MNT/"
chmod 0755 "$ROOT_MNT/usr/local/libexec/second-chapter/run-koreader-fb" \
           "$ROOT_MNT/usr/local/libexec/second-chapter/stop-koreader" \
           "$ROOT_MNT/usr/local/libexec/second-chapter/power-request"
# Everything copied from the overlay belongs to root, whoever ran the build
(cd "$OVERLAY_DIR" && find . -mindepth 1) | while read -r path; do
    chown root:root "$ROOT_MNT/${path#./}"
done

info "Setting up the reader's home folder"
home="$ROOT_MNT/home/$TABLET_USER"
ko_home="$home/.config/koreader-fb"     # KOReader's settings (KO_HOME)
mkdir -p "$home/Books" "$ko_home/patches" "$ko_home/second-chapter" "$ko_home/settings"
if [ ! -f "$ko_home/settings.reader.lua" ]; then
    cp "$SCRIPT_DIR/koreader-fb/settings.reader.lua" "$ko_home/settings.reader.lua"
fi
# The Second Chapter device profile, and KOReader patches loaded at start-up
cp "$SCRIPT_DIR/koreader-fb/second-chapter/"*.lua "$ko_home/second-chapter/"
cp "$SCRIPT_DIR/koreader-fb/patches/"*.lua "$ko_home/patches/"

# KOReader's OPDS catalogue list: your Calibre-Web first, then KOReader's
# usual free catalogues.
if [ -n "${CALIBRE_OPDS_URL:-}" ]; then
    info "Adding your Calibre-Web library to KOReader"
    lua_string() {
        # Quote a value safely for a Lua file
        local s=${1//\\/\\\\}
        s=${s//\"/\\\"}
        printf '"%s"' "$s"
    }
    cat > "$ko_home/settings/opds.lua" <<EOF
-- Second Chapter: KOReader's OPDS catalogue list
return {
    ["servers"] = {
        {
            ["title"] = "Calibre-Web",
            ["url"] = $(lua_string "$CALIBRE_OPDS_URL"),
            ["username"] = $(lua_string "$CALIBRE_USER"),
            ["password"] = $(lua_string "$CALIBRE_PASSWORD"),
        },
        { ["title"] = "Project Gutenberg", ["url"] = "https://m.gutenberg.org/ebooks.opds/?format=opds" },
        { ["title"] = "Standard Ebooks", ["url"] = "https://standardebooks.org/feeds/opds" },
        { ["title"] = "ManyBooks", ["url"] = "http://manybooks.net/opds/index.php" },
        { ["title"] = "Internet Archive", ["url"] = "https://bookserver.archive.org/" },
    },
}
EOF
    chmod 0600 "$ko_home/settings/opds.lua"
fi
chown -R "$uid:$gid" "$home/Books" "$home/.config"

info "Setting the password, time zone and name"
printf '%s:%s\n' "$TABLET_USER" "$TABLET_PASSWORD" | in_nura chpasswd
[ -e "$ROOT_MNT/usr/share/zoneinfo/$TIMEZONE" ] || { note "Unknown time zone '$TIMEZONE'; using UTC"; TIMEZONE=UTC; }
ln -sf "/usr/share/zoneinfo/$TIMEZONE" "$ROOT_MNT/etc/localtime"
echo "$TABLET_HOSTNAME" > "$ROOT_MNT/etc/hostname"

info "Saving your Wi-Fi details"
nm_file="$ROOT_MNT/etc/NetworkManager/system-connections/second-chapter-wifi.nmconnection"
mkdir -p "$(dirname "$nm_file")"
cat > "$nm_file" <<EOF
[connection]
id=Home Wi-Fi
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=$WIFI_SSID

[wifi-security]
key-mgmt=wpa-psk
psk=$WIFI_PASSWORD

[ipv4]
method=auto

[ipv6]
method=auto
EOF
chmod 0600 "$nm_file"
chown root:root "$nm_file"

info "Turning on the start-up service and SSH"
# second-chapter-fb runs KOReader straight on the screen; KOReader itself
# handles the Power button, sleep, auto-sleep and auto-switch-off.
# second-chapter-power.path carries out KOReader's power-off/reboot requests.
in_nura systemctl enable second-chapter-fb.service second-chapter-power.path second-chapter-fastboot.service sshd.service >/dev/null 2>&1 \
    || fail "Couldn't enable the start-up services."
# Nura's sleep-inhibitor blocks sleep while an SSH session is open and only
# re-checks every few minutes, which makes the Power button seem broken.
in_nura systemctl disable sleep-inhibitor.service >/dev/null 2>&1 || true
# Services that only slow start-up on this tablet:
#   systemd-boot-update: for the systemd-boot bootloader (this uses U-Boot)
#   systemd-backlight@…: restores a saved brightness, possibly after KOReader
#                        has set its own (KOReader manages the backlight)
#   systemd-time-wait-sync: waits up to ~20 s for network time; the clock
#                        still sets itself from the network in the background
#   plymouth-*:          the splash screen. KOReader starts early, and the
#                        splash would otherwise be shown again afterwards
#                        and, when closed, put text over KOReader
in_nura systemctl mask systemd-boot-update.service \
    'systemd-backlight@backlight:backlight.service' \
    systemd-time-wait-sync.service \
    plymouth-start.service plymouth-read-write.service \
    plymouth-quit.service plymouth-quit-wait.service >/dev/null 2>&1 || true

if [ -f "$ROOT_MNT/etc/apk/repositories.second-chapter" ]; then
    mv -f "$ROOT_MNT/etc/apk/repositories.second-chapter" "$ROOT_MNT/etc/apk/repositories"
fi

# --- 8. The boot partition: Second Chapter kernel and start-up settings -----
#
# The Second Chapter kernel gets its own start-up entry, made the default;
# Nura's own kernel stays as a spare entry ("postmarketOS").
#
# With U-Boot built with EFI (see the install guide, step B7, for the
# recommended non-EFI U-Boot), the start-up file system (initramfs) isn't
# passed to the kernel. U-Boot still loads it at 0x83100000, so
# "initrd=address,size" tells the kernel where it is. Harmless otherwise.
# "quiet splash" is removed so start-up messages are visible.

info "Installing the Second Chapter kernel and start-up settings"
boot_line=$(sfdisk -d "$OUTPUT_IMAGE.part" | grep -F "$OUTPUT_IMAGE.part1 :")
boot_start=$(sed -E 's/.*start= *([0-9]+).*/\1/' <<<"$boot_line")
boot_size=$(sed -E 's/.*size= *([0-9]+).*/\1/' <<<"$boot_line")
[ -n "$boot_start" ] && [ -n "$boot_size" ] || fail "Couldn't find the boot partition."
BOOT_LOOP=$(losetup -f --show -o $((boot_start * 512)) --sizelimit $((boot_size * 512)) "$OUTPUT_IMAGE.part")
BOOT_MNT=$(mktemp -d "$WORK_DIR/boot.XXXXXX")
mount "$BOOT_LOOP" "$BOOT_MNT"
extlinux="$BOOT_MNT/extlinux/extlinux.conf"
if [ -f "$extlinux" ] && ! grep -q 'initrd=0x' "$extlinux"; then
    initrd_size=$(stat -c %s "$BOOT_MNT/initramfs")
    cp "$extlinux" "$extlinux.orig"
    sed -i "s/append quiet splash /append /; /^\s*append/ s/\$/ initrd=0x83100000,$initrd_size/" "$extlinux"
fi
grep -q 'initrd=0x83100000' "$extlinux" || note "Warning: couldn't add the initrd setting to $extlinux"

cp "$KERNEL_DIR/vmlinuz-sc" "$BOOT_MNT/vmlinuz-sc"
if ! grep -q '^label second-chapter$' "$extlinux"; then
    append=$(awk '$1 == "label" { inlabel = ($2 == "postmarketOS") }
                  inlabel && $1 == "append" { sub(/^[ \t]*append[ \t]*/, ""); print; exit }' "$extlinux")
    [ -n "$append" ] || fail "Couldn't read Nura's start-up settings."
    printf '\nlabel second-chapter\n\tkernel /vmlinuz-sc\n\tfdtdir /\n\tinitrd /initramfs\n\tappend %s\n' \
        "$append" >> "$extlinux"
fi
# Quick start-up entry: the same kernel without Nura's start-up file system
# (about 4 seconds quicker). The first start uses "second-chapter", as the
# start-up file system expands the system partition; then
# second-chapter-fastboot.service switches the default to this one.
if ! grep -q '^label second-chapter-fast$' "$extlinux"; then
    printf '\nlabel second-chapter-fast\n\tkernel /vmlinuz-sc\n\tfdtdir /\n\tappend console=tty0 rw root=/dev/mmcblk0p2 rootfstype=ext4 rootwait\n' \
        >> "$extlinux"
fi
sed -i 's/^default .*/default second-chapter/' "$extlinux"
umount "$BOOT_MNT"
rmdir "$BOOT_MNT"
losetup -d "$BOOT_LOOP"

# Kernel modules: unpacked to a temporary folder and moved into place, as
# /lib is a link to usr/lib on Nura and must not be replaced.
modules_tmp=$(mktemp -d "$WORK_DIR/modules.XXXXXX")
tar -xzf "$KERNEL_DIR/modules-sc.tar.gz" -C "$modules_tmp"
[ -d "$modules_tmp/lib/modules/$KERNEL_RELEASE" ] || fail "The kernel modules aren't for $KERNEL_RELEASE."
rm -rf "$ROOT_MNT/usr/lib/modules/$KERNEL_RELEASE"
mv "$modules_tmp/lib/modules/$KERNEL_RELEASE" "$ROOT_MNT/usr/lib/modules/"
chown -R root:root "$ROOT_MNT/usr/lib/modules/$KERNEL_RELEASE"
rm -rf "$modules_tmp"

# --- 9. Finish --------------------------------------------------------------

info "Tidying up"
rm -f "$ROOT_MNT$DEBIAN_DIR/etc/resolv.conf"
sync
cleanup
ROOT_MNT=""
LOOP_DEV=""
trap - EXIT
mv "$OUTPUT_IMAGE.part" "$OUTPUT_IMAGE"

info "Done!"
note "Your image is ready:"
note "  $OUTPUT_IMAGE"
note "Size: $(du -h "$OUTPUT_IMAGE" | cut -f1)"
note ""
note "Next, write it to the tablet. See docs/nexus7-install-guide.md, Part D."
