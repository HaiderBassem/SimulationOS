#!/bin/bash

WALLPAPER_DIR="/mnt/m.2_ssd/Linux/Wallpapers"
IMAGE=$(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.jpeg" \) | shuf -n 1)

# Supported transitions
TRANSITIONS=("wipe" "grow" "outer" "center" "fade" "simple" "left" "right" "top" "bottom" "wave")
TRANSITION=${TRANSITIONS[$RANDOM % ${#TRANSITIONS[@]}]}

# Random normalized position (0.0–1.0)
POS_X=$(awk -v seed=$RANDOM 'BEGIN { srand(seed); printf("%.2f", rand()) }')
POS_Y=$(awk -v seed=$RANDOM 'BEGIN { srand(seed); printf("%.2f", rand()) }')

# Start swww-daemon if not already running
if ! pgrep -x swww-daemon >/dev/null; then
    swww-daemon &
    sleep 0.5
fi

# Set wallpaper with random transition and position
swww img "$IMAGE" --transition-type "$TRANSITION" --transition-pos "$POS_X,$POS_Y" --transition-duration 3 --transition-fps 60


