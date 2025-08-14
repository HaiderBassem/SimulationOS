#!/bin/bash
# Get only microphone sources (exclude monitors and virtual sources)
SOURCES=$(pamixer --list-sources | grep -v "monitor" | grep -v "virtual" | awk -F: '{print $1}')

# Toggle mute for microphone sources only
for SRC in $SOURCES; do
    pamixer --source "$SRC" --toggle-mute
done

# Check and report the state of the default source
MIC_STATE=$(pamixer --default-source --get-mute)
if [ "$MIC_STATE" = "true" ]; then
    notify-send -u low -i microphone-sensitivity-high -t 1000 "Microphone" "Muted"
else
    notify-send -u low -i microphone-sensitivity-high -t 1000 "Microphone" "Unmuted"
fi
