#!/bin/bash
#
# Second Chapter: build the test kernel for the Nexus 7 (2012).
#
# Same source and configuration as Nura v26.06's linux-postmarketos-grate,
# plus sleep-testing (PM_DEBUG) and crash-log (PSTORE_RAM) options, and its
# own name (7.0.1-postmarketos-grate-sc) so it can sit alongside Nura's
# kernel. Patches in patches/ are applied first: a backport of the LP1
# wake-up fix from libre-tegra/linux pull request #10 (by Berclaz), which
# counts the CPU power-good time on CLK_M rather than 32 kHz, and a fix so
# switching off doesn't restart the tablet (see patches/README.md). Produces out/vmlinuz-sc and out/modules-sc.tar.gz for
# nura/tools/test-kernel.sh.
#
# Needs (Debian/Ubuntu/Mint):
#   sudo apt install gcc-arm-linux-gnueabihf bc bison flex libssl-dev kmod cpio zstd git
#
# Usage:  ./build-kernel.sh [work-folder]     (default: ./kernel-build)
# Takes about 15-60 minutes depending on the PC, and ~3 GB of disc space.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK=$(mkdir -p "${1:-kernel-build}" && cd "${1:-kernel-build}" && pwd)
REPO=https://codeberg.org/libre-tegra/linux.git
COMMIT=bfffc6d6656e87f3de3aa4c09d852849081ef088   # Nura v26.06 linux-postmarketos-grate 7.0.1
MAKE=(make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LOCALVERSION=)

cd "$WORK"
if [ ! -f src/Makefile ]; then
    echo "== Fetching the kernel source"
    rm -rf src; git init -q src
    git -C src remote add origin "$REPO"
    for attempt in 1 2 3 4; do
        git -C src fetch -q --depth 1 origin "$COMMIT" && break
        echo "   attempt $attempt failed; retrying"; sleep $((attempt * 15))
    done
    git -C src checkout -q FETCH_HEAD
fi

cd src
# Second Chapter patches. Put the source back to the original first, so a
# rebuild always uses the current versions of the patches (only the files
# they touch are compiled again).
git checkout -q -- .
for patch in "$HERE"/patches/*.patch; do
    [ -e "$patch" ] || continue
    echo "== Applying $(basename "$patch")"
    git apply "$patch" || { echo "Error: $(basename "$patch") doesn't apply" >&2; exit 1; }
done

echo "== Configuring"
cp "$HERE/config-nura-v26.06-grate.armv7" .config
./scripts/config --set-str LOCALVERSION "-postmarketos-grate-sc" \
    --enable PM_DEBUG --enable PM_ADVANCED_DEBUG --enable PM_SLEEP_DEBUG \
    --enable PSTORE_RAM --enable PSTORE_CONSOLE --enable PSTORE_PMSG
"${MAKE[@]}" -s olddefconfig

echo "== Building (this takes a while)"
"${MAKE[@]}" -j"$(nproc)" zImage modules

echo "== Packaging"
rm -rf ../out; mkdir -p ../out
cp arch/arm/boot/zImage ../out/vmlinuz-sc
"${MAKE[@]}" -s INSTALL_MOD_PATH=../out/modroot INSTALL_MOD_STRIP=1 modules_install
(cd ../out/modroot && tar -czf ../modules-sc.tar.gz lib)
cp .config ../out/config-sc
echo "Kernel release: $("${MAKE[@]}" -s kernelrelease)"
ls -la ../out
