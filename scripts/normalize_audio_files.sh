#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: ${0} <directory>"
    exit 1
fi

input_directory="$1"

# LUFS normalization parameters
lufs="-23"
tolerance="-1.0"
loudness_range="11"
# Peak normalization parameters
target_peak="-9" # around LUFS -23 volume
#target_peak="-6" # around LUFS -18 volume
#target_peak="-3" # around LUFS -16 volume
peak_tolerance="0.3"

for file in "$input_directory"/*; do
    # Only process audio files
    if [ ! -f "$file" ] ||
        ! (ffprobe -v error -select_streams a:0 -show_entries stream=codec_type \
            -of csv=p=0 "$file" 2>/dev/null | grep -q audio); then
        echo "Skipping:   $file (not an audio file)"
        continue
    fi

    echo "Processing: $file"

    temp_file="${file%.*}-tmp.${file##*.}"

    # Get codec, sample rate, channel count and duration
    IFS=$'\t' read codec sample_rate channel_count duration < <(
        ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels \
        -show_entries format=duration -of json "$file" |
        jq -r '[.streams[0].codec_name, .streams[0].sample_rate, .streams[0].channels, .format.duration] | @tsv'
    )

    # LUFS normalization cannot be calculated for very short files, use peak normalization instead
    if (( $(echo "$duration < 0.4" | bc -l) )); then
        # Analyze the file
        current_peak=$(ffmpeg -hide_banner -loglevel info -i "$file" -filter:a "volumedetect" -f null - 2>&1 |
            grep "max_volume: " | cut -d ':' -f 2 | cut -d ' ' -f 2
        )
        gain=$(echo "$target_peak - $current_peak" | bc -l)

        # Check if the file has been normalized already
        if (( $(bc -l <<< "($current_peak - $target_peak)^2 < $peak_tolerance^2") )); then
            echo "Skipping:   $file (already normalized)"
        else
            # Normalize the file
            ffmpeg -hide_banner -loglevel error -i "$file" -filter:a "volume=${gain}dB" "$temp_file" \
            && mv "$temp_file" "$file"
        fi
    else
        # Analyze the file
        IFS=$'\t' read input_i input_tp input_lra input_thresh < <(
            ffmpeg -hide_banner -loglevel info -i "$file" \
                -filter:a "loudnorm=\
                I=${lufs}:\
                TP=${tolerance}:\
                LRA=${loudness_range}:\
                print_format=json" \
                -f null - 2>&1 |
            sed -n '/^{/,/}$/p' |
            jq -r '[.input_i, .input_tp, .input_lra, .input_thresh] | @tsv'
        )

        # Skip silent files
        if [[ "$input_i" == "-inf" ]]; then
            echo "Skipping:   $file (silent file)"
        # Check if the file has been normalized already
        elif (( $(bc -l <<< "($input_i - $lufs)^2 < $tolerance^2") )); then
            echo "Skipping:   $file (already normalized)"
        else
            # Normalize the file
            ffmpeg -hide_banner -loglevel error -i "$file" \
                -filter:a "loudnorm=\
                I=${lufs}:\
                TP=${tolerance}:\
                LRA=${loudness_range}:\
                linear=true:\
                measured_I=${input_i}:\
                measured_LRA=${input_lra}:\
                measured_tp=${input_tp}:\
                measured_thresh=${input_thresh}" \
                -acodec "$codec" \
                -ar "$sample_rate" \
                -ac "$channel_count" \
                "$temp_file" \
            && mv "$temp_file" "$file"
        fi
    fi

    # Remove metadata
    ffmpeg -hide_banner -loglevel error -i "$file" \
        -fflags +bitexact -flags:a +bitexact \
        -map a:0 \
        -map_metadata -1 \
        -c:a copy \
        "$temp_file" \
    && mv "$temp_file" "$file"

    echo "Normalized: $file"
done
