#!/bin/bash

exit_cleanup() {
    if [ -e "$skip_vote_file" ]; then
        rm "$skip_vote_file"
    fi

    if [ -e "$skip_voting_open_state_file" ]; then
        rm "$skip_voting_open_state_file"
    fi

    queue_pid=$(cat "$queue_pid_file" 2>/dev/null)
    if [ -n "$queue_pid" ]; then
        kill "$queue_pid" 2>/dev/null
        wait "$queue_pid" 2>/dev/null
        rm "$queue_pid_file"
    fi

    if [ -e "$downloader_pid_file" ]; then
        while read -r pid; do
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
        done < "$downloader_pid_file"
        rm "$downloader_pid_file"
    fi
}

# Exit cleanly on CTRL+C and system shutdown
trap exit_cleanup SIGINT SIGTERM EXIT


announcer_pid_file="/tmp/announcer.pid"
downloader_pid_file="/tmp/downloader.pid"
paplay_pid_file="/tmp/paplay.pid"
queue_pid_file="/tmp/queue.pid"
queue_dir="/tts/queue"
queue_file="/tts/queue.txt"
skip_vote_file="/tts/skip_votes.txt"
skip_voting_open_state_file="/tmp/skip_voting.open"
recently_played_history_file="/tts/recently_played_history.txt"

mkdir -p "$queue_dir"
touch "$queue_file"
touch "$skip_vote_file"
touch "$recently_played_history_file"


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

# Word blacklist:
# Example: "dQw4w9WgXcQ\|dwDns8x3Jb4\|ZZ5LpwO-An4"
# Default: "$^"
blacklisted_words="$^"

speak_text() {
    local text="$1"

    local announcer_pid=$(cat "$announcer_pid_file" 2>/dev/null)
    if [ -n "$announcer_pid" ]; then
        kill "$announcer_pid" 2>/dev/null
    fi

        local audio_file="$(mktemp /tmp/dectalk_voice-XXXXXXXXXX.wav)"

        say -pre "[:name HARRY]" -e 1 -a "$text" -fo "$audio_file"

        paplay --client-name=radio-announcer "$audio_file" >/dev/null 2>&1 &
        local announcer_pid=$!
        echo "$announcer_pid" > "$announcer_pid_file"
        wait "$announcer_pid"
        > "$announcer_pid_file"

        rm -f "$audio_file"
}

download_and_queue() {
    local video_id="$1"
    echo "Downloading: $video_id"

    local audio_format="opus"

    # Check if a file exists already
    shopt -s nullglob
    matched_files=( "$queue_dir/"*" ($video_id).$audio_format" )
    shopt -u nullglob

    if [[ ${#matched_files[@]} -gt 0 ]]; then
        local audio_file="${matched_files[0]}"
        echo "Already downloaded: $audio_file"
    else
        # Get the filename and video categories
        local metadata=$(yt-dlp --skip-download --no-warnings --print "%(title)s--SEP--%(categories)s" "$video_id")
        local title="${metadata%%--SEP--*}"
        local categories="${metadata#*--SEP--}"
        local audio_file="$queue_dir/$title ($video_id).$audio_format"

        echo "Title: $title"

        # Check if the file is a music video
        #if [[ "$categories" != *Music* ]]; then
        #    echo "Not a music video: $title"
        #    return
        #fi

        # Download the file
        yt-dlp --extract-audio --audio-format="$audio_format" --match-filter "duration < 1200" \
        -o "$queue_dir/%(title)s ($video_id).%(ext)s" "$video_id" --no-playlist --quiet

        # Check if the file has been downloaded successfully
        if [ ! -f "$audio_file" ]; then
            echo "Video unavailable: $title"
            return
        fi

        echo "Downloaded: $audio_file"

        # Normalize audio
        ffmpeg -hide_banner -loglevel error -i "$audio_file" \
        -af loudnorm=I=-23:TP=-1.0:LRA=11 -ac 1 -ar 24000 \
        temp."$audio_format" && mv temp."$audio_format" "$audio_file"

        echo "Normalized: $audio_file"
    fi

    # Check if the file is queued already
    if grep -Fxq "$audio_file" "$queue_file"; then
        echo "Already in the queue: $audio_file"
    # Check if the file has been recently played
    elif grep -Fxq "$audio_file" "$recently_played_history_file"; then
        echo "File recently played: $audio_file"
    else
        # Queue the file
        echo "$audio_file" >> "$queue_file"
        echo "Queued: $audio_file"

        recently_played_history_length=5

        # Add the file to the recently played files list
        echo "$audio_file" >> "$recently_played_history_file"
        tail -n "$recently_played_history_length" "$recently_played_history_file" > "$recently_played_history_file.tmp"
        mv "$recently_played_history_file.tmp" "$recently_played_history_file"
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
                -e "s/[[\(]( *([48]k|hd|hq|music|official|remastered|audio|video)){1,7}[]\)] *//gI" \
                -e "s/[-_]/,/g"
            )
            file_title=$(echo "$file_title" | tr -cd '[:alnum:][:space:][:punct:]')

            speak_text "Now playing: $file_title."

            touch "$skip_voting_open_state_file"

            paplay --client-name=radio "$audio_file" >/dev/null 2>&1 &
            local paplay_pid=$!
            echo "$paplay_pid" > "$paplay_pid_file"
            wait "$paplay_pid"
            > "$paplay_pid_file"

            rm "$skip_voting_open_state_file"
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
        echo "Stopping current playback."
        kill "$paplay_pid" 2>/dev/null
    else
        echo "No active playback to stop."
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
echo $! > "$queue_pid_file"


while IFS= read -r line; do
    # Extract YouTube URLs
    if grep -q '!queue' <<< "$line" && \
    [[ "$line" =~ (https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)([A-Za-z0-9_-]+) ]]; then
        download_and_queue "${BASH_REMATCH[-1]}" &
        echo $! >> "$downloader_pid_file"
    # Vote to skip the currently playing file
    elif grep -q '!skip' <<< "$line"; then
        # Check if there is a file playing
        if [ -e "$skip_voting_open_state_file" ]; then
            username=$(sed 's/^\(\*DEAD\*\)\?\((TEAM)\)\? \?\(.\+\) : .\+/\3/' <<< "$line")

            # Check if the user has not voted yet
            if ! grep -q "$username" "$skip_vote_file"; then
                echo "$username" >> "$skip_vote_file"
                echo "Voted to skip: $username"

                required_vote_count=5
                remaining_vote_count=$(( $required_vote_count - $(wc -l < "$skip_vote_file") ))

                if [[ "$remaining_vote_count" -gt 1 ]]; then
                    (speak_text "${remaining_vote_count} votes remaining.") &
                elif [[ "$remaining_vote_count" -eq 1 ]]; then
                    (speak_text "1 vote remaining.") &
                # Skip the currently playing file if the required number of skip votes has been reached
                else
                    (speak_text "Skipping the file.") &

                    echo "Skipping the file."
                    skip_current
                fi
            fi
        fi
    fi
done < <(
    # Continuously read the last line of the log as it is updated
    stdbuf -oL tail -fn 1 "$console_log" |
    # Search for lines containing the command
    grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?.\+ :  !\(queue \|skip\)" |
    # Remove messages from blacklisted players
    grep --line-buffered -v "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${blacklisted_names} :  !" |
    # Keep messages only from whitelisted players
    grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${whitelisted_names} :  !" |
    # Sanitize the message
    stdbuf -o0 sed 's/[$;`()]//g' |
    # Remove messages with blacklisted words
    grep --line-buffered -v "$blacklisted_words" |
    # Remove non-ASCII and control characters
    stdbuf -o0 tr -cd '[:alnum:][:space:][:punct:]'
    # Remove duplicate messages
    #| stdbuf -o0 uniq
)
