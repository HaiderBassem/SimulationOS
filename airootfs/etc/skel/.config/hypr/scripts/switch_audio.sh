#!/bin/bash

# Define sinks (output devices)
USB_SINK="alsa_output.usb-GeneralPlus_USB_Audio_Device-00.analog-stereo"
SPEAKER_SINK="alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Speaker__sink"

# Define USB mic (input device)
USB_MIC="alsa_input.usb-GeneralPlus_USB_Audio_Device-00.mono-fallback"

# Function to move all app streams to the current default sink
move_streams_to_default_sink() {
    DEFAULT_SINK=$(pactl info | grep "Default Sink" | awk '{print $3}')
    pactl list short sink-inputs | while read -r id _; do
        pactl move-sink-input "$id" "$DEFAULT_SINK"
    done
}

# Function to set mic volume and unmute
set_usb_mic() {
    pactl set-default-source "$USB_MIC"
    pactl set-source-volume "$USB_MIC" 70%
    pactl set-source-mute "$USB_MIC" 0
}

# Get current default sink
CURRENT_SINK=$(pactl info | grep 'Default Sink' | awk '{print $3}')

# Toggle output sink and apply USB mic
if [[ "$CURRENT_SINK" == "$USB_SINK" ]]; then
    pactl set-default-sink "$SPEAKER_SINK"
    pactl set-sink-mute "$SPEAKER_SINK" 0
    pactl set-sink-volume "$SPEAKER_SINK" 100%
    echo "Switched to Speaker output"
else
    pactl set-default-sink "$USB_SINK"
    pactl set-sink-mute "$USB_SINK" 0
    echo "Switched to USB output"
fi

# Apply USB mic settings
set_usb_mic
echo "USB Microphone set as input with 100% volume"

# Move all streams to current default sink
move_streams_to_default_sink
echo "All app streams moved to default sink"

