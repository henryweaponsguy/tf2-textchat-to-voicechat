#!/bin/bash

paplay_pid_file="/tmp/paplay.pid"
queue_dir="/tts/queue"
queue_file="/tts/queue.txt"
skip_vote_file="/tts/skip_votes.txt"
console_log="/tts/console.log"

mkdir -p "$queue_dir"
touch "$queue_file"
touch "$skip_vote_file"


cleanup() {
    > "$skip_vote_file"

    paplay_pid=$(cat "$paplay_pid_file" 2>/dev/null)
    kill "$paplay_pid" 2>/dev/null
    rm "$paplay_pid_file"
}

trap cleanup SIGINT


download_and_queue() {
    url="$1"
    echo "Downloading: $url"

    audio_format=opus

    # Get the filename
    file="$queue_dir/$(yt-dlp --skip-download --print title "$url").$audio_format"
    echo "Title: $file"

    # Check if the file is a music video
    if ! yt-dlp --no-warnings --print "%(categories)s" "$url" | grep -q "Music"; then
        echo "Not a music video: $file"
    else
        # Check if the file already exists
        if [[ -f "$file" ]]; then
            echo "Already downloaded: $file"
        else
            # Download the file
            yt-dlp --extract-audio --audio-format="$audio_format" --match-filter "duration < 1200" \
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
    fi
}

play_queue() {
    while [[ -s "$queue_file" ]]; do
        audio_file=$(head -n 1 "$queue_file")

        if [[ -f "$audio_file" ]]; then
            echo "Playing: $audio_file"
            paplay --client-name=radio "$audio_file" &
            paplay_pid=$!
            echo "$paplay_pid" > "$paplay_pid_file"
            wait "$paplay_pid"
            > "$paplay_pid_file"
        else
            echo "File not found: $audio_file"
        fi

        tail -n +2 "$queue_file" > "$queue_file.tmp" && cat "$queue_file.tmp" > "$queue_file" && rm "$queue_file.tmp"
    done
}

skip_current() {
    paplay_pid=$(cat "$paplay_pid_file" 2>/dev/null)

    if [[ -n "$paplay_pid" ]]; then
        echo "Stopping current playback..."
        kill "$paplay_pid" 2>/dev/null
    else
        echo "No active playback to stop..."
    fi
}

start_queue() {
    while true; do
        play_queue

        inotifywait -e modify "$queue_file"
    done
}


# Start the playback loop in the background
start_queue &


# Add '-condebug' as TF2's launch parameter.
# Alternatively, add "con_logfile <logfile location>" to autoexec.cfg
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="/tts/console.log"

# User blacklist:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
# Default: "$^"
blacklisted_names="$^"

# Alternatively, a whitelist:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
# Default: ".*"
whitelisted_names=".*"

# Example: "dQw4w9WgXcQ\|dwDns8x3Jb4\|ZZ5LpwO-An4"
# Default: "$^"
blacklisted_words="$^"


# Continuously read the last line of the log as it is updated
stdbuf -oL tail -fn 1 "$console_log" |
# Search for lines containing the command
grep --line-buffered -E ' :  !(queue|skip) ' |
# Remove messages from blacklisted players
grep --line-buffered -v "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${blacklisted_names} :  !" |
# Keep messages only from whitelisted players
grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${whitelisted_names} :  !" |
# Sanitize the message
stdbuf -o0 sed 's/[$;`()]//g' |
# Remove duplicate messages
#stdbuf -o0 uniq |
# Remove non-ASCII and control characters
stdbuf -o0 tr -cd '[:alnum:][:space:][:punct:]' |
# Remove messages with blacklisted words
grep --line-buffered -v "$blacklisted_words" |
while IFS= read -r line; do
    # Extract YouTube URLs
    if grep -q '!queue' <<< "$line" && \
    [[ "$line" =~ (https?://)?(www\.)?((youtube\.com/watch\?v=|youtu\.be/)[A-Za-z0-9_-]+) ]]; then
        download_and_queue "${BASH_REMATCH[0]}"
    # Vote to skip the currently playing file
    elif grep -q '!skip' <<< "$line"; then
        IFS=' :  ' read -r nickname command_name <<< "$line"

        # Check if the user has not voted yet
        if ! grep -q "$nickname" "$skip_vote_file"; then
            echo "$nickname" >> "$skip_vote_file"
            echo "Voted to skip: $nickname"
        fi

        # Skip the currently playing file if there are at least 5 skip votes
        if [[ $(wc -l < "$skip_vote_file") -ge 5 ]]; then
            # Clear skip votes
            > "$skip_vote_file"

            skip_current
            echo "Skipped the file..."
        fi
    fi
done
