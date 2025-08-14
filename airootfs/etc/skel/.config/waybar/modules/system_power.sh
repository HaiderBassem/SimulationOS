#!/bin/bash
# ~/.config/waybar/scripts/system_power.sh


echo "=== SYSTEM POWER USAGE ==="
echo

# Check for powertop
if command -v powertop &> /dev/null; then
    echo "Getting system power usage (this may take a few seconds)..."
    sudo powertop --dump --quiet --time=1 2>/dev/null | grep -A 10 "Power est" | head -10
    echo
fi

# CPU frequency and governor
echo "=== CPU INFO ==="
if [[ -f /proc/cpuinfo ]]; then
    echo "CPU: $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
fi

if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
    echo "Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
fi

if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
    freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
    echo "Frequency: $(awk "BEGIN {printf \"%.2f\", $freq / 1000}")MHz"
fi

echo
echo "=== THERMAL INFO ==="
# Temperature info
if command -v sensors &> /dev/null; then
    sensors | grep -E "(Core|Package|temp)" | head -5
elif [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    temp=$(cat /sys/class/thermal/thermal_zone0/temp)
    echo "CPU Temp: $(awk "BEGIN {printf \"%.1f\", $temp / 1000}")°C"
fi

echo
echo "=== LOAD AVERAGE ==="
echo "Load: $(uptime | awk -F'load average:' '{print $2}' | xargs)"

# Memory usage
echo
echo "=== MEMORY USAGE ==="
free -h | grep -E "(Mem|Swap)" | head -2


