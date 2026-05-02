#!/bin/bash

virtual_speaker_name="virtual_speaker"
virtual_microphone_name="virtual_microphone"
virtual_cable_modules="/tmp/virtual_cable_modules"

if [ ! -f "$virtual_cable_modules" ]; then
    touch "$virtual_cable_modules"

    # Create a virtual speaker
    pactl load-module module-null-sink \
    sink_name="$virtual_speaker_name" \
    sink_properties=device.description="$virtual_speaker_name" \
    >> "$virtual_cable_modules"

    # Create a virtual microphone
    pactl load-module module-null-sink \
    sink_name="$virtual_microphone_name" \
    sink_properties=device.description="$virtual_microphone_name" \
    media.class=Audio/Source/Virtual \
    channel_map=front-left,front-right \
    >> "$virtual_cable_modules"

    # Link the virtual speaker and microphone
    pw-link "$virtual_speaker_name":monitor_FL "$virtual_microphone_name":input_FL
    pw-link "$virtual_speaker_name":monitor_FR "$virtual_microphone_name":input_FR
else
    # Remove the virtual speaker and microphone
    while IFS= read -r line; do
        pactl unload-module "$line"
    done < "$virtual_cable_modules"

    rm "$virtual_cable_modules"
fi
