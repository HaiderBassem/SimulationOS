#!/bin/bash

CONFIG_FILE="$HOME/.config/hypr/monitors.conf"
MONITOR_NAME="eDP-1"

# Get current refresh rate from hyprctl
get_current_refresh_rate() {
    hyprctl monitors | grep -A 1 "Monitor $MONITOR_NAME" | grep -o '@[0-9]*\.[0-9]*' | sed 's/@//' | head -1
}

# Update the config file
update_config_file() {
    local target_rate=$1
    
    if [ -f "$CONFIG_FILE" ]; then
        # Comment out current line and uncomment target line
        if [ "$target_rate" = "165" ]; then
            sed -i 's/^monitor=eDP-1,2560x1600@165/#&/' "$CONFIG_FILE"
            sed -i 's/^#monitor=eDP-1,2560x1600@60/monitor=eDP-1,2560x1600@60/' "$CONFIG_FILE"
        else
            sed -i 's/^monitor=eDP-1,2560x1600@60/#&/' "$CONFIG_FILE"
            sed -i 's/^#monitor=eDP-1,2560x1600@165/monitor=eDP-1,2560x1600@165/' "$CONFIG_FILE"
        fi
    fi
}

# Handle click actions
case $1 in
    toggle)
        # Get current refresh rate
        CURRENT_RATE=$(get_current_refresh_rate)
        CURRENT_RATE_INT=$(printf "%.0f" "$CURRENT_RATE")
        
        if [ "$CURRENT_RATE_INT" = "165" ] || [ "$CURRENT_RATE_INT" = "164" ]; then
            # Switch to 60Hz
            hyprctl keyword monitor "$MONITOR_NAME,2560x1600@60,0x0,1.0" >/dev/null 2>&1
            update_config_file 165
            echo "🔄 Switched to 60Hz"
        else
            # Switch to 165Hz
            hyprctl keyword monitor "$MONITOR_NAME,2560x1600@165,0x0,1.0" >/dev/null 2>&1
            update_config_file 60
            echo "🔄 Switched to 165Hz"
        fi
        ;;
    status)
        # Show current refresh rate
        CURRENT_RATE=$(get_current_refresh_rate)
        CURRENT_RATE_INT=$(printf "%.0f" "$CURRENT_RATE")
        
        if [ "$CURRENT_RATE_INT" = "165" ] || [ "$CURRENT_RATE_INT" = "164" ]; then
            echo "🖥️  ${CURRENT_RATE_INT}Hz"
        else
            echo "🖥️  ${CURRENT_RATE_INT}Hz"
        fi
        ;;
    *)
        # Default: show current status
        CURRENT_RATE=$(get_current_refresh_rate)
        CURRENT_RATE_INT=$(printf "%.0f" "$CURRENT_RATE")
        
        if [ "$CURRENT_RATE_INT" = "165" ] || [ "$CURRENT_RATE_INT" = "164" ]; then
            echo "🖥️  ${CURRENT_RATE_INT}Hz"
        else
            echo "🖥️  ${CURRENT_RATE_INT}Hz"
        fi
        ;;
esac
