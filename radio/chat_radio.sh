#!/bin/bash

# Add '-condebug' as TF2's launch parameter.
# Alternatively, add "con_logfile <logfile location>" to autoexec.cfg
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="/tts/console.log"

announcer_pid_file="/tmp/announcer.pid"
paplay_pid_file="/tmp/paplay.pid"
queue_pid_file="/tmp/queue.pid"
queue_dir="/tts/queue"
queue_file="/tts/queue.txt"
skip_vote_file="/tts/skip_votes.txt"

mkdir -p "$queue_dir"
touch "$queue_file"
touch "$skip_vote_file"


cleanup() {
    > "$skip_vote_file"

    queue_pid=$(cat "$queue_pid_file" 2>/dev/null)
    if [ -n "$queue_pid" ]; then
        kill "$queue_pid" 2>/dev/null
        wait "$queue_pid" 2>/dev/null
        rm "$queue_pid_file"
    fi
}

trap cleanup SIGINT SIGTERM EXIT


speak_text() {
    local text="$1"

    local audio_file="$(mktemp /tmp/dectalk_voice-XXXXXXXXXX.wav)"

    say -pre "[:name HARRY]" -e 1 -a "$text" -fo "$audio_file"

    paplay --client-name=radio-announcer "$audio_file" >/dev/null 2>&1
    rm -f "$audio_file"
}

announce_text() {
    local text="$1"

    local announcer_pid=$(cat "$announcer_pid_file" 2>/dev/null)
    if [ -n "$announcer_pid" ]; then
        kill "$announcer_pid" 2>/dev/null
    fi

    (
        local audio_file="$(mktemp /tmp/dectalk_voice-XXXXXXXXXX.wav)"

        say -pre "[:name HARRY]" -e 1 -a "$text" -fo "$audio_file"

        paplay --client-name=radio-announcer "$audio_file" >/dev/null 2>&1 &
        local announcer_pid=$!
        echo "$announcer_pid" > "$announcer_pid_file"
        wait "$announcer_pid"
        > "$announcer_pid_file"

        rm -f "$audio_file"
    ) &
}

download_and_queue() {
    local video_id="$1"
    echo "Downloading: $video_id"

    local audio_format=opus

    # Check if a file exists already
    shopt -s nullglob
    matches=( "$queue_dir/"*" ($video_id).$audio_format" )
    shopt -u nullglob

    if [[ ${#matches[@]} -gt 0 ]]; then
        local audio_file="${matches[0]}"
        echo "Already downloaded: $audio_file"
    else
        # Get the filename
        local audio_file="$queue_dir/$(yt-dlp --skip-download --print title "$video_id") ($video_id).$audio_format"
        echo "Title: $audio_file"

        # Check if the file is a music video
        if ! yt-dlp --no-warnings --print "%(categories)s" "$video_id" | grep -q "Music"; then
            echo "Not a music video: $audio_file"
        else
            # Download the file
            yt-dlp --extract-audio --audio-format="$audio_format" --match-filter "duration < 1200" \
            -o "$queue_dir/%(title)s ($video_id).%(ext)s" "$video_id" --no-playlist --quiet
            echo "Downloaded: $audio_file"

            # Normalize audio
            ffmpeg -hide_banner -loglevel error -i "$audio_file" \
            -af loudnorm=I=-23:TP=-1.0:LRA=11 -ac 1 -ar 24000 \
            temp."$audio_format" && mv temp."$audio_format" "$audio_file"
            echo "Normalized: $audio_file"
        fi
    fi

    # Add to the queue if not already queued
    if ! grep -Fxq "$audio_file" "$queue_file"; then
        echo "$audio_file" >> "$queue_file"
        echo "Queued: $audio_file"
    else
        echo "Already in the queue: $audio_file"
    fi
}

play_queue() {
    while [[ -s "$queue_file" ]]; do
        # Clear skip votes
        > "$skip_vote_file"

        local audio_file=$(head -n 1 "$queue_file")

        # Remove the current file from the queue file
        tail -n +2 "$queue_file" > "$queue_file.tmp" && cat "$queue_file.tmp" > "$queue_file" && rm "$queue_file.tmp"

        if [[ -f "$audio_file" ]]; then
            echo "Playing: $audio_file"

            local file_title="${audio_file##*/}"
            file_title="${file_title%.*}"
            file_title=$(echo "$file_title" | sed -E \
                -e "s/\([A-Za-z0-9_-]+\)$//g" \
                -e "s/[[\(]( *(4k|hd|hq|music|official|remastered|video)){1,7} *[]\)]//gI" \
                -e "s/[-_]/,/g"
            )

            speak_text "now playing: $file_title"

            paplay --client-name=radio "$audio_file" >/dev/null 2>&1 &
            local paplay_pid=$!
            echo "$paplay_pid" > "$paplay_pid_file"
            wait "$paplay_pid"
            > "$paplay_pid_file"
        else
            echo "File not found: $audio_file"
        fi
    done
}

skip_current() {
    # Clear skip votes
    > "$skip_vote_file"

    local paplay_pid=$(cat "$paplay_pid_file" 2>/dev/null)
    if [[ -n "$paplay_pid" ]]; then
        echo "Stopping current playback..."
        kill "$paplay_pid" 2>/dev/null
    else
        echo "No active playback to stop..."
    fi
}

start_queue() {
    trap '
        paplay_pid=$(cat "$paplay_pid_file" 2>/dev/null)
        if [ -n "$paplay_pid" ]; then
            kill "$paplay_pid" 2>/dev/null
            wait "$paplay_pid" 2>/dev/null
            rm -f "$paplay_pid_file"
        fi

        exit
    ' SIGINT SIGTERM EXIT

    while true; do
        play_queue

        inotifywait -e modify "$queue_file"
    done
}


# Start the playback loop in the background
start_queue &
queue_pid=$!
echo "$queue_pid" > "$queue_pid_file"


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


while IFS= read -r line; do
    # Extract YouTube URLs
    if grep -q '!queue' <<< "$line" && \
    [[ "$line" =~ (https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)([A-Za-z0-9_-]+) ]]; then
        download_and_queue "${BASH_REMATCH[-1]}"
    # Vote to skip the currently playing file
    elif grep -q '!skip' <<< "$line"; then
        # Check if there is a file playing
        if pgrep -f "^paplay --client-name=radio " > /dev/null; then
            IFS=' :  ' read -r nickname command_name <<< "$line"

            # Check if the user has not voted yet
            if ! grep -q "$nickname" "$skip_vote_file"; then
                echo "$nickname" >> "$skip_vote_file"
                echo "Voted to skip: $nickname"

                required_vote_count=5
                vote_count=$(wc -l < "$skip_vote_file")

                if [[ $(( $required_vote_count - $vote_count )) -gt 1 ]]; then
                    announce_text "$(( $required_vote_count - $vote_count )) votes remaining"
                elif [[ $(( $required_vote_count - $vote_count )) -eq 1 ]]; then
                    announce_text "$(( $required_vote_count - $vote_count )) vote remaining"
                # Skip the currently playing file if the required number of skip votes has been reached
                else
                    announce_text "skipping the file"

                    echo "Skipping the file..."
                    skip_current
                fi
            fi
        fi
    fi
done < <(
    # Continuously read the last line of the log as it is updated
    stdbuf -oL tail -fn 1 "$console_log" |
    # Search for lines containing the command
    grep --line-buffered -E ' :  !(queue |skip)' |
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
    grep --line-buffered -v "$blacklisted_words"
)
