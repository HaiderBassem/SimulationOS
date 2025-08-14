#!/bin/bash
# ~/.config/waybar/scripts/power_monitor.sh
# Portable power monitoring script for waybar

# Get battery voltage information from any available battery
get_battery_voltage() {
    # Use the same approach as your working version - find first available battery
    local battery_dir=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
    
    if [[ -d "$battery_dir" ]]; then
        # Try voltage_now first (like your working version)
        local voltage_now=$(cat "$battery_dir/voltage_now" 2>/dev/null)
        if [[ -n "$voltage_now" && "$voltage_now" -gt 0 ]]; then
            local voltage_v=$(awk "BEGIN {printf \"%.2f\", $voltage_now / 1000000}")
            echo "$voltage_v V"
            return
        fi
        
        # Try voltage_avg as alternative
        local voltage_avg=$(cat "$battery_dir/voltage_avg" 2>/dev/null)
        if [[ -n "$voltage_avg" && "$voltage_avg" -gt 0 ]]; then
            local voltage_v=$(awk "BEGIN {printf \"%.2f\", $voltage_avg / 1000000}")
            echo "$voltage_v V"
            return
        fi
        
        # Fallback to design voltage
        local design_voltage=$(cat "$battery_dir/voltage_min_design" 2>/dev/null)
        if [[ -n "$design_voltage" && "$design_voltage" -gt 0 ]]; then
            local voltage_v=$(awk "BEGIN {printf \"%.2f\", $design_voltage / 1000000}")
            echo "$voltage_v V (design)"
            return
        fi
        
        # Try alternative design voltage file
        local design_voltage2=$(cat "$battery_dir/voltage_design" 2>/dev/null)
        if [[ -n "$design_voltage2" && "$design_voltage2" -gt 0 ]]; then
            local voltage_v=$(awk "BEGIN {printf \"%.2f\", $design_voltage2 / 1000000}")
            echo "$voltage_v V (design)"
            return
        fi
    fi
    
    echo "N/A"
}

# Get power consumption (watts) if available and non-zero
get_power_consumption() {
    # Use the same battery finding approach for consistency
    local battery_dir=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
    
    if [[ -d "$battery_dir" ]]; then
        # Check for power_now file first (most direct)
        if [[ -f "$battery_dir/power_now" ]]; then
            local power_now=$(cat "$battery_dir/power_now" 2>/dev/null)
            if [[ -n "$power_now" && "$power_now" != "0" && "$power_now" =~ ^-?[0-9]+$ ]]; then
                local power_w=$(awk "BEGIN {printf \"%.1f\", $power_now / 1000000}")
                echo "${power_w}W"
                return
            fi
        fi
        
        # Alternative: calculate from current and voltage
        if [[ -f "$battery_dir/current_now" ]]; then
            local current_now=$(cat "$battery_dir/current_now" 2>/dev/null)
            if [[ -n "$current_now" && "$current_now" != "0" && "$current_now" =~ ^-?[0-9]+$ ]]; then
                # Get voltage for power calculation
                local voltage_now=$(cat "$battery_dir/voltage_now" 2>/dev/null)
                if [[ -z "$voltage_now" || "$voltage_now" == "0" ]]; then
                    voltage_now=$(cat "$battery_dir/voltage_avg" 2>/dev/null)
                fi
                
                if [[ -n "$voltage_now" && "$voltage_now" -gt 0 ]]; then
                    # Calculate power in watts (current in microamps * voltage in microvolts / 1000000000000)
                    local power_uw=$(awk "BEGIN {printf \"%.0f\", ($current_now * $voltage_now) / 1000000}")
                    if [[ "$power_uw" != "0" ]]; then
                        local power_w=$(awk "BEGIN {printf \"%.1f\", $power_uw / 1000000}")
                        echo "${power_w}W"
                        return
                    fi
                fi
            fi
        fi
    fi
    
    echo ""
}

# Get battery status from first available battery  
get_battery_status() {
    local status_file=$(ls /sys/class/power_supply/BAT*/status 2>/dev/null | head -1)
    if [[ -f "$status_file" ]]; then
        cat "$status_file" 2>/dev/null | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

# Get battery percentage from first available battery
get_battery_percentage() {
    local capacity_file=$(ls /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
    if [[ -f "$capacity_file" ]]; then
        cat "$capacity_file" 2>/dev/null
    else
        echo "N/A"
    fi
}

# Check if AC adapter is connected (supports various naming conventions)
is_ac_connected() {
    # Check standard patterns like your working version
    for ac in /sys/class/power_supply/A{C,DP}*; do
        if [[ -d "$ac" && -f "$ac/online" ]]; then
            [[ $(cat "$ac/online" 2>/dev/null) == "1" ]] && return 0
        fi
    done
    
    # Additional check for ACAD pattern
    for ac in /sys/class/power_supply/ACAD*; do
        if [[ -d "$ac" && -f "$ac/online" ]]; then
            [[ $(cat "$ac/online" 2>/dev/null) == "1" ]] && return 0
        fi
    done
    
    return 1
}

# Get battery count for tooltip
get_battery_count() {
    local count=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | wc -l)
    echo "$count"
}

# Main execution
voltage=$(get_battery_voltage)
power=$(get_power_consumption)
status=$(get_battery_status)
percentage=$(get_battery_percentage)
battery_count=$(get_battery_count)

# Build display text
text="$voltage"
if [[ -n "$power" ]]; then
    text="$text | $power"
fi

# Create detailed tooltip
if is_ac_connected; then
    tooltip="🔌 AC Connected"
else
    tooltip="🔋 On Battery"
fi

tooltip="$tooltip | Voltage: $voltage"

if [[ -n "$power" ]]; then
    tooltip="$tooltip | Power: $power"
fi

tooltip="$tooltip | Battery: ${percentage}% (${status})"

if [[ "$battery_count" -gt 1 ]]; then
    tooltip="$tooltip | ${battery_count} batteries detected"
fi

# Determine CSS class based on status
css_class="power-monitor"
if is_ac_connected; then
    css_class="$css_class ac-connected"
else
    css_class="$css_class battery-mode"
    # Add low battery warning class
    if [[ "$percentage" != "N/A" && "$percentage" -lt 20 ]]; then
        css_class="$css_class low-battery"
    fi
fi

# Output JSON for waybar
printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$text" "$tooltip" "$css_class"
