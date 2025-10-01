#!/bin/bash

virtual_sink_name="virtual_sink"
virtual_mic_name="virtual_mic"
virtual_cable_modules="/tmp/virtual_cable_modules"

if [ ! -f "$virtual_cable_modules" ]; then
    touch "$virtual_cable_modules"

    # Create a virtual sink
    pactl load-module module-null-sink \
    sink_name="$virtual_sink_name" \
    sink_properties=device.description="$virtual_sink_name" \
    >> "$virtual_cable_modules"

    # Create a virtual mic
    pactl load-module module-null-sink \
    sink_name="$virtual_mic_name" \
    sink_properties=device.description="$virtual_mic_name" \
    media.class=Audio/Source/Virtual \
    channel_map=front-left,front-right \
    >> "$virtual_cable_modules"

    # Link the virtual sink and mic
    pw-link "$virtual_sink_name":monitor_FL "$virtual_mic_name":input_FL
    pw-link "$virtual_sink_name":monitor_FR "$virtual_mic_name":input_FR
else
    # Remove the virtual sink and mic
    while IFS= read -r line; do
        pactl unload-module "$line"
    done < "$virtual_cable_modules"

    rm "$virtual_cable_modules"
fi
