#!/bin/bash

STATUS=$(hyprctl monitors -j | jq -r '.[] | select(.name=="eDP-2") | .dpmsStatus')

if [[ "$STATUS" == "true" ]]; then
    hyprctl dispatch dpms off eDP-2
else
    hyprctl dispatch dpms on eDP-2
fi

