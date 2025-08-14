#!/bin/bash

sleep 5

wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 0.4


#!/bin/bash

# Set USB mic as default input
pactl set-default-source alsa_input.usb-GeneralPlus_USB_Audio_Device-00.mono-fallback
#pactl set-source-volume alsa_input.usb-GeneralPlus_USB_Audio_Device-00.mono-fallback 100%
pactl set-source-mute alsa_input.usb-GeneralPlus_USB_Audio_Device-00.mono-fallback 0

# Mute all other mics
pactl set-source-mute alsa_input.usb-Sony_Interactive_Entertainment_DualSense_Wireless_Controller-00.analog-stereo 1
pactl set-source-mute alsa_input.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Mic1__source 1
pactl set-source-mute alsa_input.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Mic2__source 1

