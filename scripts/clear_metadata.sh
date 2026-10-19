#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: ${0} <directory>"
    exit 1
fi

input_directory="$1"

for file in "$input_directory"/*; do
    # Only process audio files
    if [ ! -f "$file" ] ||
        ! (ffprobe -v error -select_streams a:0 -show_entries stream=codec_type \
            -of csv=p=0 "$file" 2>/dev/null | grep -q audio); then
        echo "Skipping:   $file (not an audio file)"
        continue
    fi

    echo "Processing: $file"

    # Remove metadata
    ffmpeg -hide_banner -loglevel error -i "$file" \
        -fflags +bitexact -flags:a +bitexact \
        -map a:0 \
        -map_metadata -1 \
        -c:a copy \
        "tmp.${file##*.}" \
    && mv "tmp.${file##*.}" "$file"

    echo "Cleared:    $file"
done
