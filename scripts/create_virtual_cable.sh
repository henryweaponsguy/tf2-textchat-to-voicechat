#!/bin/sh

pactl load-module module-null-sink sink_name=virtual_sink sink_properties=device.description="virtual_sink"
pactl load-module module-null-sink media.class=Audio/Source/Virtual sink_name=virtual_mic channel_map=front-left,front-right

pw-link virtual_sink:monitor_FL virtual_mic:input_FL
pw-link virtual_sink:monitor_FR virtual_mic:input_FR
