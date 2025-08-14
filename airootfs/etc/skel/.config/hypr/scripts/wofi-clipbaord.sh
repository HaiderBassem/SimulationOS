#!/bin/bash

entries=$(cliphist list)

selection=$(echo "$entries" | wofi --dmenu --prompt "Clipboard")

if [[ -z "$selection" ]]; then
    exit 0
fi

# Use cliphist to decode and copy
echo "$selection" | cliphist decode | wl-copy

