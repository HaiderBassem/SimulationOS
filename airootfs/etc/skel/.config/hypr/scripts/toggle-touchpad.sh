#!/bin/sh

# Fast touchpad toggle for Hyprland - streamlined version

# Find the touchpad device event number
TOUCHPAD_EVENT=$(grep -A 5 -B 5 "SYNA7DB5:00 06CB:CEAF Touchpad" /proc/bus/input/devices | grep -o 'event[0-9]*' | head -n1)

[ -z "$TOUCHPAD_EVENT" ] && { notify-send -t 1000 "Error: Touchpad not found"; exit 1; }

# Path to the device inhibit file
INHIBIT_FILE="/sys/class/input/$TOUCHPAD_EVENT/device/inhibited"

# Check current state and toggle (0=enabled, 1=disabled)
CURRENT_STATE=$(cat "$INHIBIT_FILE" 2>/dev/null || echo "0")

if [ "$CURRENT_STATE" = "0" ]; then
    if echo 1 | tee "$INHIBIT_FILE" >/dev/null 2>&1; then
        notify-send -t 1000 "Touchpad Disabled"
    else
        notify-send -t 1000 "Failed to disable"
    fi
else
    if echo 0 | tee "$INHIBIT_FILE" >/dev/null 2>&1; then
        notify-send -t 1000 "Touchpad Enabled"
    else
        notify-send -t 1000 "Failed to enable"
    fi
fi
