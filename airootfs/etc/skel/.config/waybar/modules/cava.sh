#!/bin/sh
trap 'exit 0' PIPE TERM INT

# Create vertical bars like terminal cava
bar="▁▂▃▄▅▆▇█"
dict="s/;//g;"
i=0
while [ $i -lt 8 ]; do
    dict="${dict}s/$i/${bar:$i:1}/g;"
    i=$((i+1))
done

# Add spaces between bars for terminal look
dict="${dict}s/\(.\)/\1 /g;"

# Write cava config for raw output
echo "[general]
bars = 12
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7" > /tmp/cava_config

check_counter=0
current_state="stopped"

cava -p /tmp/cava_config 2>/dev/null | while read -r line; do
    check_counter=$((check_counter + 1))
    if [ $check_counter -ge 20 ]; then
        if pactl list sink-inputs 2>/dev/null | grep -q "Sink Input"; then
            current_state="playing"
        else
            current_state="stopped"
        fi
        check_counter=0
    fi
    
    if [ "$current_state" = "playing" ]; then
        echo "$line" | sed "$dict" 2>/dev/null || exit 0
    else
        echo "" 2>/dev/null || exit 0
    fi
done
