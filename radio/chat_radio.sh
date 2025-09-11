#!/bin/bash

queue_dir="/tts/queue"
queue_file="/tts/queue.txt"
console_log="/tts/console.log"

mkdir -p "$queue_dir"
touch "$queue_file"


download_and_queue() {
    url="$1"
    echo "Downloading: $url"

    audio_format=opus

    # Get the filename
    file="$queue_dir/$(yt-dlp --skip-download --print title "$url").$audio_format"
    echo "Title: $file"

    # Check if the file already exists
    if [[ -f "$file" ]]; then
        echo "Already downloaded: $file"
    else
        # Download the file
        yt-dlp --extract-audio --audio-format="$audio_format" --match-filter "duration < 600" \
            -o "$queue_dir/%(title)s.%(ext)s" "$url" --no-playlist --quiet
        echo "Downloaded: $file"

        # Normalize audio
        ffmpeg -hide_banner -loglevel error -i "$file" \
        -af loudnorm=I=-23:TP=-1.0:LRA=11 temp."$audio_format" && mv temp."$audio_format" "$file"
        echo "Normalized: $file"
    fi

    # Add to the queue if not already queued
    if ! grep -Fxq "$file" "$queue_file"; then
        echo "$file" >> "$queue_file"
        echo "Queued: $file"
    else
        echo "Already in the queue: $file"
    fi
}

play_queue() {
    while [[ -s "$queue_file" ]]; do
        audio_file=$(head -n 1 "$queue_file")
        tail -n +2 "$queue_file" > "$queue_file.tmp" && cat "$queue_file.tmp" > "$queue_file" && rm "$queue_file.tmp"

        if [[ -f "$audio_file" ]]; then
            echo "Playing: $audio_file"
            paplay --client-name=radio "$audio_file"
        else
            echo "File not found: $audio_file"
        fi
    done
}

start_queue() {
    play_queue

    while inotifywait -e modify "$queue_file"; do
        play_queue
    done
}


# Start the playback loop in the background
start_queue &


# Add '-condebug' as TF2's launch parameter.
# Alternatively, add "con_logfile <logfile location>" to autoexec.cfg
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="/tts/console.log"

# Example: blacklisted_names="name1\|name2\|name3"
# Default: blacklisted_names="$^"
blacklisted_names="$^"

# Alternatively, a whitelist:
# Example: whitelisted_names="name1\|name2\|name3"
# Default: whitelisted_names=".*"
whitelisted_names=".*"

# Example: banned_words="nominate\|rtv\|nextmap"
# Default: banned_words="$^"
banned_words="$^"


# Continuously read the last line of the log as it is updated
stdbuf -oL tail -f -n 1 "$console_log" |
# Sanitize the message
stdbuf -o0 sed 's/[$;`()]//g' |
# Search for lines containing " :  !queue "
grep --line-buffered ' :  !queue ' |
# Remove messages with blacklisted names
grep -v --line-buffered "$blacklisted_names" |
# Keep only messages with whitelisted names
grep --line-buffered "$whitelisted_names" |
# Extract the message
stdbuf -o0 sed 's/^.*: *!queue *//' |
# Remove duplicate messages
#stdbuf -o0 uniq |
# Replace repeating exclamation marks with a single one
# ("!!" repeats the last executed command in bash)
stdbuf -o0 sed 's/!\{2,\}/!/g' |
stdbuf -o0 tr -cd '[:alnum:][:space:][:punct:]' |
# Remove messages with banned words
grep --line-buffered -v "$banned_words" |
while IFS= read -r line; do
    # Extract YouTube URLs
    if [[ "$line" =~ (https?://)?(www\.)?(youtube\.com/watch\?v=[A-Za-z0-9_-]+|youtu\.be/[A-Za-z0-9_-]+) ]]; then
        url="${BASH_REMATCH[0]}"
        download_and_queue "$url"
    fi
done
