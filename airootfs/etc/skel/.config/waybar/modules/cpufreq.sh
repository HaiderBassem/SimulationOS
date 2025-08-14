#!/bin/bash
# Get current governor
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
else
    GOVERNOR="unknown"
fi

# Get current refresh rate from hyprctl
if command -v hyprctl >/dev/null 2>&1; then
    REFRESH_RATE=$(hyprctl monitors | grep -E '@[0-9]+\.[0-9]+' | head -1 | sed -n 's/.*@\([0-9]\+\.[0-9]\+\).*/\1/p')
    if [ -n "$REFRESH_RATE" ]; then
        # Round to nearest integer for cleaner display
        REFRESH_RATE=$(printf "%.0f" "$REFRESH_RATE")
        REFRESH_DISPLAY=" | 󰹑   ${REFRESH_RATE}Hz"
    else
        REFRESH_DISPLAY=""
    fi
else
    REFRESH_DISPLAY=""
fi

# Handle click actions
case $1 in
  toggle)
    # Toggle between powersave and performance
    if [ "$GOVERNOR" = "powersave" ]; then
        sudo -n auto-cpufreq --force performance >/dev/null 2>&1
    else
        sudo -n auto-cpufreq --force powersave >/dev/null 2>&1
    fi
    ;;
  reset)
    # Still requires explicit reset command
    sudo -n auto-cpufreq --force reset >/dev/null 2>&1
    ;;
esac

# Re-read governor after potential change
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
else
    GOVERNOR="unknown"
fi

# Map governor to icon + text with refresh rate
case $GOVERNOR in
    "performance")
        echo "󰾆   performance${REFRESH_DISPLAY}"
        ;;
    "powersave")
        echo "󰂏 powersave${REFRESH_DISPLAY}"
        ;;
    "ondemand")
        echo "⚖️ ondemand${REFRESH_DISPLAY}"
        ;;
    "conservative")
        echo "🐌 conservative${REFRESH_DISPLAY}"
        ;;
    "schedutil")
        echo "📊 schedutil${REFRESH_DISPLAY}"
        ;;
    "userspace")
        echo "👤 userspace${REFRESH_DISPLAY}"
        ;;
    *)
        echo "❓ $GOVERNOR${REFRESH_DISPLAY}"
        ;;
esac
