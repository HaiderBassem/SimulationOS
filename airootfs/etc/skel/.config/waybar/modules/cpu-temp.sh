#!/bin/bash
# ~/.config/waybar/modules/cpu-temp-fan.sh
# Combined CPU temperature and fan speed monitor for Waybar

# SysFS path for fan speed (from your Predator Sense script)
FAN_SYSFS_PATH="/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/predator_sense/fan_speed"

# Function to get CPU temperature
get_cpu_temp() {
    local temp=""
    
    # Method 1: Use sensors command to get Package id 0 temperature
    if command -v sensors &> /dev/null; then
        temp=$(sensors 2>/dev/null | grep "Package id 0" | awk '{print $4}' | sed 's/+//g' | sed 's/°C//g' | cut -d'.' -f1)
    fi
    
    # Method 2: Fallback to hwmon9 (coretemp) temp1_input which corresponds to Package id 0
    if [ -z "$temp" ] && [ -f "/sys/class/hwmon/hwmon9/temp1_input" ]; then
        temp_raw=$(cat /sys/class/hwmon/hwmon9/temp1_input 2>/dev/null)
        if [ -n "$temp_raw" ]; then
            temp=$((temp_raw / 1000))
        fi
    fi
    
    # Method 3: Alternative hwmon path fallback
    if [ -z "$temp" ]; then
        for hwmon in /sys/class/hwmon/hwmon*/name; do
            if [ "$(cat "$hwmon" 2>/dev/null)" = "coretemp" ]; then
                hwmon_dir=$(dirname "$hwmon")
                if [ -f "$hwmon_dir/temp1_input" ]; then
                    temp_raw=$(cat "$hwmon_dir/temp1_input" 2>/dev/null)
                    if [ -n "$temp_raw" ]; then
                        temp=$((temp_raw / 1000))
                        break
                    fi
                fi
            fi
        done
    fi
    
    # Remove any whitespace/newlines
    temp=$(echo "$temp" | tr -d ' \n\r')
    echo "$temp"
}

# Function to get CPU fan speed percentage
get_cpu_fan_speed() {
    local fan_speed=""
    
    # Check if the fan speed sysfs path exists
    if [ -f "$FAN_SYSFS_PATH" ]; then
        # Read the fan speed value (format: "cpu_speed,gpu_speed")
        fan_data=$(cat "$FAN_SYSFS_PATH" 2>/dev/null)
        if [ -n "$fan_data" ]; then
            # Extract CPU fan speed (first value before comma)
            fan_speed=$(echo "$fan_data" | cut -d',' -f1)
            # Handle special case for auto mode (0,0)
            if [ "$fan_speed" = "0" ]; then
                fan_speed="Auto"
            else
                fan_speed="${fan_speed}%"
            fi
        fi
    fi
    
    # Return empty string if no fan data available (instead of "N/A")
    echo "$fan_speed"
}

# Function to determine temperature class and icon
get_temp_status() {
    local temp=$1
    
    if [ "$temp" -lt 40 ]; then
        echo "❄️" "cold"
    elif [ "$temp" -lt 60 ]; then
        echo "🟢" "good"
    elif [ "$temp" -lt 70 ]; then
        echo "🟡" "warm"
    elif [ "$temp" -lt 80 ]; then
        echo "🟠" "hot"
    else
        echo "🔥" "critical"
    fi
}

# Function to determine fan class
get_fan_status() {
    local fan_speed=$1
    
    case "$fan_speed" in
        "Auto") echo "auto" ;;
        "") echo "unknown" ;;  # Empty string instead of "N/A"
        *%)
            # Extract numeric value for percentage-based classification
            local speed_num=$(echo "$fan_speed" | sed 's/%//')
            if [ "$speed_num" -lt 30 ]; then
                echo "low"
            elif [ "$speed_num" -lt 60 ]; then
                echo "medium"
            else
                echo "high"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}

# Main execution
main() {
    # Get CPU temperature
    cpu_temp=$(get_cpu_temp)
    
    # Get CPU fan speed
    cpu_fan=$(get_cpu_fan_speed)
    
    # Handle case where temperature is not available
    if [ -z "$cpu_temp" ] || [ "$cpu_temp" = "0" ]; then
        if [ -n "$cpu_fan" ]; then
            echo "{\"text\":\"🔍 CPU N/A | 🌀 $cpu_fan\",\"class\":\"unknown\",\"tooltip\":\"CPU temperature not available\"}"
        else
            echo "{\"text\":\"🔍 CPU N/A\",\"class\":\"unknown\",\"tooltip\":\"CPU temperature not available\"}"
        fi
        exit 0
    fi
    
    # Get temperature status
    read temp_icon temp_class <<< "$(get_temp_status "$cpu_temp")"
    
    # Get fan status
    fan_class=$(get_fan_status "$cpu_fan")
    
    # Determine overall class (prioritize temperature for critical situations)
    if [ "$temp_class" = "critical" ]; then
        overall_class="critical"
    elif [ "$temp_class" = "hot" ]; then
        overall_class="hot"
    elif [ "$temp_class" = "warm" ]; then
        overall_class="warm"
    elif [ "$fan_class" = "unknown" ]; then
        overall_class="unknown"
    else
        overall_class="good"
    fi
    
    # Format output text - only include fan info if available
    if [ -n "$cpu_fan" ]; then
        display_text="$temp_icon ${cpu_temp}°C | 🌀 $cpu_fan"
        tooltip="CPU Temperature: ${cpu_temp}°C\\nCPU Fan Speed: $cpu_fan"
    else
        display_text="$temp_icon ${cpu_temp}°C"
        tooltip="CPU Temperature: ${cpu_temp}°C\\nCPU Fan Speed: Not available"
    fi
    
    # Output JSON for waybar
    echo "{\"text\":\"$display_text\",\"class\":\"$overall_class\",\"tooltip\":\"$tooltip\"}"
}

# Run main function
main
