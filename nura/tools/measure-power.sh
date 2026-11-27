#!/bin/sh
#
# Second Chapter: measure how much current each part of the tablet uses.
#
# Takes an average battery-current reading with everything on, then switches
# parts off one at a time (backlight, Wi-Fi, Bluetooth, KOReader) and measures
# again, then puts everything back as it was. Results go to standard output.
#
# Wi-Fi is switched off part-way through, which drops any SSH connection, so
# run it in the background and read the results afterwards:
#
#   sudo -v
#   sudo nohup sh measure-power.sh > measure-power.log 2>&1 &
#   (wait about 3 minutes, reconnect, then)  cat measure-power.log

BATTERY=/sys/class/power_supply/bq27541-0
SAMPLES=15

measure() {
    # Average of $SAMPLES one-second readings, shown in mA (positive = drain)
    sleep 5  # let things settle after a change
    total=0
    i=0
    while [ "$i" -lt "$SAMPLES" ]; do
        now=$(cat "$BATTERY/current_now")
        total=$((total + now))
        i=$((i + 1))
        sleep 1
    done
    echo "$1: $(( -total / SAMPLES / 1000 )) mA"
}

backlight=$(ls -d /sys/class/backlight/* 2>/dev/null | head -n 1)
old_brightness=""
[ -n "$backlight" ] && old_brightness=$(cat "$backlight/brightness")

echo "Second Chapter power measurement, $(date)"
echo "Battery: $(cat "$BATTERY/capacity")%"
echo "Backlight: ${backlight:-not found} (brightness ${old_brightness:-?} of $(cat "$backlight/max_brightness" 2>/dev/null || echo ?))"
echo

measure "1. Everything on (screen lit, Wi-Fi, KOReader)"

if [ -n "$backlight" ]; then
    echo 0 > "$backlight/brightness"
    measure "2. Backlight off"
fi

nmcli radio wifi off
measure "3. ...and Wi-Fi off"

if command -v rfkill >/dev/null 2>&1; then
    rfkill block bluetooth
    measure "4. ...and Bluetooth off"
else
    echo "4. (rfkill not available, Bluetooth step skipped)"
fi

systemctl stop second-chapter-fb
measure "5. ...and KOReader stopped"

echo
echo "Putting everything back..."
systemctl start second-chapter-fb
command -v rfkill >/dev/null 2>&1 && rfkill unblock bluetooth
nmcli radio wifi on
[ -n "$backlight" ] && [ -n "$old_brightness" ] && echo "$old_brightness" > "$backlight/brightness"
echo "Done, $(date)"
