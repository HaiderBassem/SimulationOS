#!/bin/bash
# ~/.config/waybar/scripts/power_details.sh


echo "=== BATTERY DETAILS ==="
echo

# Battery info via upower
if command -v upower &> /dev/null; then
    battery_device=$(upower -e | grep -i bat | head -1)
    if [[ -n "$battery_device" ]]; then
        upower -i "$battery_device" | grep -E "state|energy|voltage|percentage|time to|power" | sed 's/^  *//'
    else
        echo "No battery device found"
    fi
else
    echo "upower not installed"
fi

echo
echo "=== POWER SUPPLY FILES ==="
echo

# Raw power supply information
for bat in /sys/class/power_supply/BAT*; do
    if [[ -d "$bat" ]]; then
        echo "Battery: $(basename "$bat")"
        if [[ -f "$bat/power_now" ]]; then
            power_uw=$(cat "$bat/power_now" 2>/dev/null)
            power_w=$(awk "BEGIN {printf \"%.2f\", $power_uw / 1000000}" 2>/dev/null)
            echo "  Power Now: $power_uw µW ($power_w W)"
        fi
        [[ -f "$bat/voltage_now" ]] && echo "  Voltage: $(cat "$bat/voltage_now" 2>/dev/null) µV"
        [[ -f "$bat/current_now" ]] && echo "  Current: $(cat "$bat/current_now" 2>/dev/null) µA"
        [[ -f "$bat/status" ]] && echo "  Status: $(cat "$bat/status" 2>/dev/null)"
        [[ -f "$bat/capacity" ]] && echo "  Capacity: $(cat "$bat/capacity" 2>/dev/null)%"
        echo
    fi
done


