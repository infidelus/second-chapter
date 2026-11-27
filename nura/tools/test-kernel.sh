#!/bin/sh
#
# Second Chapter: install a test kernel alongside Nura's own, on the tablet.
#
# Nura's kernel and its start-up entry are never changed: the test kernel
# gets its own files and its own entry in /boot/extlinux/extlinux.conf.
#
#   sudo sh test-kernel.sh install    copy vmlinuz-sc and modules-sc.tar.gz
#                                     (from the current folder) into place
#   sudo sh test-kernel.sh use-test   start the test kernel from now on
#   sudo sh test-kernel.sh use-nura   go back to Nura's kernel
#   sudo sh test-kernel.sh remove     take the test kernel out again
#   sudo sh test-kernel.sh status     show which kernel starts next
#
# If the test kernel won't start at all: hold Volume Down and press Power,
# choose "mount internal storage", and on the PC edit extlinux/extlinux.conf
# on the boot partition, changing the "default" line back to postmarketOS.

set -eu

ROOT=${SC_ROOT:-}                      # only set when testing
EXTLINUX=${SC_EXTLINUX:-$ROOT/boot/extlinux/extlinux.conf}
BOOT=$(dirname "$(dirname "$EXTLINUX")")
LABEL=second-chapter-test
NURA_LABEL=postmarketOS
RELEASE=7.0.1-postmarketos-grate-sc

fail() { echo "Error: $*" >&2; exit 1; }

[ -f "$EXTLINUX" ] || fail "can't find $EXTLINUX"

case "${1:-}" in
    install)
        [ -f vmlinuz-sc ] || fail "vmlinuz-sc isn't in the current folder"
        [ -f modules-sc.tar.gz ] || fail "modules-sc.tar.gz isn't in the current folder"
        echo "Copying the test kernel to $BOOT/vmlinuz-sc"
        cp vmlinuz-sc "$BOOT/vmlinuz-sc"
        # On Nura, /lib is a link to /usr/lib. Unpacking straight into / would
        # replace that link with a plain folder and break the system, so
        # unpack into a temporary folder and move just the modules across.
        modules_dir=$(readlink -f "$ROOT/lib/modules")
        [ -d "$modules_dir" ] || fail "can't find the modules folder ($ROOT/lib/modules)"
        echo "Installing its modules to $modules_dir/$RELEASE"
        tmp=$(mktemp -d)
        tar -xzf modules-sc.tar.gz -C "$tmp"
        [ -d "$tmp/lib/modules/$RELEASE" ] || { rm -rf "$tmp"; fail "modules-sc.tar.gz doesn't contain $RELEASE"; }
        rm -rf "$modules_dir/$RELEASE"
        mv "$tmp/lib/modules/$RELEASE" "$modules_dir/"
        rm -rf "$tmp"
        # The module index (modules.dep) is already included in the bundle.
        [ -f "$EXTLINUX.before-test" ] || cp "$EXTLINUX" "$EXTLINUX.before-test"
        if ! grep -q "^label $LABEL\$" "$EXTLINUX"; then
            # Same settings as Nura's entry, but with the test kernel
            append=$(awk -v l="$NURA_LABEL" '
                $1 == "label" { inlabel = ($2 == l) }
                inlabel && $1 == "append" { sub(/^[ \t]*append[ \t]*/, ""); print; exit }' "$EXTLINUX")
            [ -n "$append" ] || fail "couldn't read Nura's start-up settings"
            printf '\nlabel %s\n\tkernel /vmlinuz-sc\n\tfdtdir /\n\tinitrd /initramfs\n\tappend %s\n' \
                "$LABEL" "$append" >> "$EXTLINUX"
        fi
        sync
        echo "Installed. Nura's kernel is still the default."
        echo "To try the test kernel:  sudo sh test-kernel.sh use-test  then  sudo reboot"
        ;;
    use-test)
        grep -q "^label $LABEL\$" "$EXTLINUX" || fail "run 'install' first"
        sed -i "s/^default .*/default $LABEL/" "$EXTLINUX"
        sync
        echo "The test kernel will start next time."
        ;;
    use-nura)
        sed -i "s/^default .*/default $NURA_LABEL/" "$EXTLINUX"
        sync
        echo "Nura's kernel will start next time."
        ;;
    remove)
        sed -i "s/^default .*/default $NURA_LABEL/" "$EXTLINUX"
        awk -v l="$LABEL" '
            $1 == "label" { skip = ($2 == l) }
            !skip' "$EXTLINUX" > "$EXTLINUX.new" && mv "$EXTLINUX.new" "$EXTLINUX"
        rm -f "$BOOT/vmlinuz-sc"
        rm -rf "$(readlink -f "$ROOT/lib/modules")/$RELEASE"
        sync
        echo "Test kernel removed; Nura's kernel will start next time."
        ;;
    status)
        echo "Next start-up: $(sed -n 's/^default //p' "$EXTLINUX")"
        echo "Running now:   $(uname -r)"
        ;;
    *)
        sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
