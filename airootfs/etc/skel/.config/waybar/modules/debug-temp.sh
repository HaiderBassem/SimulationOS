#!/bin/bash
# ~/.config/waybar/modules/debug-temp.sh

echo "=== Temperature Debug ==="
echo ""

echo "1. CPU Temperature Methods:"
echo "   sensors coretemp:"
sensors coretemp-isa-0000 2>/dev/null | grep "Package id 0"
echo ""

echo "   CPU from sensors (Package id 0):"
cpu_temp=$(sensors coretemp-isa-0000 2>/dev/null | grep "Package id 0" | awk '{print $4}' | sed 's/+//g' | sed 's/°C//g' | cut -d'.' -f1)
echo "   Result: '$cpu_temp'"
echo ""

echo "2. GPU Temperature Methods:"
echo "   nvidia-settings:"
nvidia-settings -q gpucoretemp -t 2>/dev/null
echo ""

echo "   nvidia-smi:"
nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null
echo ""

echo "3. Available hwmon sensors:"
for i in /sys/class/hwmon/hwmon*/name; do 
    if [ -f "$i" ]; then
        echo "   $i: $(cat $i 2>/dev/null)"
    fi
done
echo ""

echo "4. Available temperature inputs:"
for i in /sys/class/hwmon/hwmon*/temp*_input; do 
    if [ -f "$i" ]; then
        temp_val=$(cat $i 2>/dev/null)
        temp_c=$((temp_val / 1000))
        echo "   $i: ${temp_val} (${temp_c}°C)"
    fi
done
echo ""

echo "5. Testing waybar scripts:"
echo "   CPU script:"
if [ -f ~/.config/waybar/modules/cpu-temp.sh ]; then
    ~/.config/waybar/modules/cpu-temp.sh
else
    echo "   CPU script not found"
fi
echo ""

echo "   GPU script:"
if [ -f ~/.config/waybar/modules/gpu-temp.sh ]; then
    ~/.config/waybar/modules/gpu-temp.sh
else
    echo "   GPU script not found"
fi
