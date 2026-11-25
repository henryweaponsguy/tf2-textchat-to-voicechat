#!/usr/bin/bash

shopt -s nullglob

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


exit_cleanup() {
    > "$text_message_file"

    if [[ -e "$voting_open_state_file" ]]; then
        rm "$voting_open_state_file"
    fi

    queue_pid=$(cat "$queue_pid_file" 2>/dev/null)
    if [[ -n "$queue_pid" ]]; then
        kill "$queue_pid" 2>/dev/null
        wait "$queue_pid" 2>/dev/null
        rm "$queue_pid_file"
    fi

    download_queue_pid=$(cat "$download_queue_pid_file" 2>/dev/null)
    if [[ -n "$download_queue_pid" ]]; then
        kill "$download_queue_pid" 2>/dev/null
        wait "$download_queue_pid" 2>/dev/null
        rm "$download_queue_pid_file"
    fi
}


# Exit cleanly on CTRL+C and system shutdown
trap exit_cleanup SIGINT SIGTERM EXIT


# The length of the recently played list (-1 to make it infinite).
# Files in the recently played list cannot be queued again
recently_played_length=5

# Required votes to skip the currently playing file
required_vote_count=5

# Chance of playing a sound cue between files (0-100)
interlude_chance=100

# Announcement sounds directory
sound_dir="${script_dir}/sounds"

# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="${script_dir}/console.log"

# Location of the file storing generated text chat messages.
# This file should be in the same directory as TF2's autoexec.cfg
text_message_file="${script_dir}/message.cfg"

# User blacklist:
# Example: "John|pablo\.gonzales\.2007|Engineer Gaming"
blacklisted_users=""

# Alternatively, a whitelist:
whitelisted_users=""

# Word blacklist:
# Example: "dQw4w9WgXcQ|dwDns8x3Jb4|ZZ5LpwO-An4"
blacklisted_words=""


paplay_pid_file="/tmp/paplay.pid"
queue_pid_file="/tmp/queue.pid"
download_queue_pid_file="/tmp/downloader.pid"
queue_dir="${script_dir}/queue"
queue_file="${queue_dir}/queue.txt"
download_queue_file="${queue_dir}/download_queue.txt"
recently_played_file="${queue_dir}/recently_played.txt"
voting_open_state_file="/tmp/voting.open"

mkdir -p "$queue_dir"

for file in "$queue_file" "$download_queue_file" "$recently_played_file"; do
    touch "$file"
done

> "$text_message_file"

declare -A vote_list
last_text_message_time=""

re_line="^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.*)"
re_command=("^(![qQ][uU][eE][uU][eE]|![sS][kK][iI][pP]) *(.+)?")
re_text_message_signal=("^\[ ?RADIO\]")
re_blacklisted_users="${blacklisted_users:-$^}"
re_whitelisted_users="${whitelisted_users:-.*}"
re_blacklisted_words="${blacklisted_words:-$^}"
re_url="(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)([A-Za-z0-9_-]+)"

replacements=(
    -e "s/\([A-Za-z0-9_-]+\)$//g"
    -e "s/[[\(]( *([48]k|hd|hq|music|official|remastered|audio|video)){1,7}[]\)] *//gI"
)


send_text_message() {
    local text_message="$(sed 's/^ \+//g; s/ \+$//g; s/ \+/ /g;' <<< "$1")"
    text_message="${text_message:0:127}"

    printf "%s\n" "say \"${text_message}\"" > "$text_message_file"

    last_text_message_time="$(date +%s)"
}

clear_text_message() {
    > "$text_message_file"
    last_text_message_time=""
}

play_sound() {
    local sound="$1"

    # Match files
    local matched_files=(
        "$sound_dir/$sound".*
        "$sound_dir/$sound "[0-9]*.*
        "$sound_dir/$sound/"*.*
        "$sound_dir/$sound/"* [0-9]*.*
    )

    if [[ ${#matched_files[@]} -eq 0 ]]; then
        return
    fi

    local selected_file="${matched_files[RANDOM % ${#matched_files[@]}]}"

    paplay --device=virtual_speaker --client-name=soundboard "$selected_file" >/dev/null 2>&1
}

download_file() {
    local video_id="$1"
    local username="$2"
    printf "%-25s%s\n" "Downloading:" "$video_id" >&2
    printf "%-25s%s\n" "Queued by:" "$username" >&2

    local audio_format="opus"

    # Check if the file has been downloaded already
    matched_files=( "$queue_dir/"*" ($video_id).$audio_format" )

    if (( ${#matched_files[@]} > 0 )); then
        local audio_file="${matched_files[0]}"
        local audio_file_stem=${audio_file##*/}
        audio_file_stem=${audio_file_stem%.*}

        printf "%-25s%s\n" "Already downloaded:" "$audio_file_stem" >&2
    else
        # Get the video's filename, title and channel
        local yt_dlp_output
        if ! yt_dlp_output="$(
            yt-dlp \
                --js-runtimes "deno" \
                --add-headers "User-Agent:Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/157.0.0.0 Safari/537.36" \
                --limit-rate 500K \
                --skip-download \
                --no-warnings \
                -o "%(title)s" \
                --print-json \
                -- "$video_id" 2>&1
        )"; then
            printf '\033[31m%-25s%s\033[0m\n' "yt-dlp error:" "$yt_dlp_output" >&2
            return
        fi

        local title="$(jq -r '.filename' <<< "$yt_dlp_output")"
        local channel="$(jq -r '.channel' <<< "$yt_dlp_output")"
        local audio_file="$queue_dir/$title ($video_id).$audio_format"
        local audio_file_stem=${audio_file##*/}
        audio_file_stem=${audio_file_stem%.*}

        printf "%-25s%s\n" "Title:" "$title" >&2
        printf "%-25s%s\n" "Channel:" "$channel" >&2

        # Download the file
        yt-dlp \
            --js-runtimes "deno" \
            --add-headers "User-Agent:Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36" \
            --limit-rate 500K \
            --extract-audio \
            --audio-format="$audio_format" \
            --match-filter "duration < 1200" \
            -o "$queue_dir/%(title)s ($video_id).%(ext)s" \
            --no-playlist \
            --quiet \
            -- "$video_id"

        # Check if the file has been downloaded successfully
        if [[ ! -f "$audio_file" ]]; then
            audio_file=""
            printf "%-25s%s\n" "Video unavailable:" "$title" >&2
        else
            # Normalization parameters
            local lufs="-23"
            local tolerance="-1.0"
            local loudness_range="9"
            local target_peak="-9"
            local peak_tolerance="0.3"

            local temp_file="${audio_file%.*}-tmp.${audio_file##*.}"

            # Get codec, sample rate, channel count and duration
            local codec sample_rate channels duration
            IFS=$'\t' read codec sample_rate channels duration < <(
                ffprobe \
                    -hide_banner \
                    -v error \
                    -select_streams a:0 \
                    -show_entries stream=codec_name,sample_rate,channels \
                    -show_entries format=duration \
                    -of json \
                    "$audio_file" |
                jq -r '[.streams[0].codec_name, .streams[0].sample_rate, .streams[0].channels, .format.duration] | @tsv'
            )

            [[ "$codec" == "opus" ]] && codec="libopus"
            [[ "$codec" == "vorbis" ]] && codec="libvorbis"

            # LUFS normalization cannot be calculated for very short files, use peak normalization instead
            if (( $(bc -l <<< "$duration < 0.4") )); then
                # Analyze the file
                local current_peak=$(
                    ffmpeg \
                        -hide_banner \
                        -loglevel info \
                        -i "$audio_file" \
                        -filter:a "volumedetect" \
                        -f null - 2>&1 |
                    grep "max_volume: " | cut -d ':' -f 2 | cut -d ' ' -f 2
                )
                local gain=$(bc -l <<< "$target_peak - $current_peak")

                # Normalize the file
                ffmpeg \
                    -hide_banner \
                    -loglevel error \
                    -i "$audio_file" \
                    -filter:a "volume=${gain}dB" \
                    -acodec "$codec" \
                    -ar "$sample_rate" \
                    -ac "$channels" \
                    -y \
                    "$temp_file" \
                && mv "$temp_file" "$audio_file"
            else
                # Analyze the file
                local input_i input_tp input_lra input_thresh
                IFS=$'\t' read input_i input_tp input_lra input_thresh < <(
                    ffmpeg \
                        -hide_banner \
                        -loglevel info \
                        -i "$audio_file" \
                        -filter:a \
                            "loudnorm=\
                            I=${lufs}:\
                            TP=${tolerance}:\
                            LRA=${loudness_range}:\
                            print_format=json" \
                        -f null - 2>&1 |
                    sed -n '/^{/,/}$/p' |
                    jq -r '[.input_i, .input_tp, .input_lra, .input_thresh] | @tsv'
                )

                # Skip silent files
                if [[ "$input_i" != "-inf" ]]; then
                    # Normalize the file
                    ffmpeg \
                        -hide_banner \
                        -loglevel error \
                        -i "$audio_file" \
                        -filter:a \
                            "loudnorm=\
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
                        -ac "$channels" \
                        -y \
                        "$temp_file" \
                    && mv "$temp_file" "$audio_file"
                fi
            fi

            printf "%-25s%s\n" "Downloaded:" "$audio_file_stem" >&2
        fi
    fi

    printf "%s" "$audio_file"
}

download_queue() {
    while [[ -s "$download_queue_file" ]]; do
        local video_id username
        IFS=$'\t' read -r video_id username < "$download_queue_file"

        local audio_file=$(download_file "$video_id" "$username")
        local audio_file_stem=${audio_file##*/}
        audio_file_stem=${audio_file_stem%.*}

        # Check if the file has been downloaded
        if [[ -z "$audio_file" ]]; then
            printf "\033[32m%-25s%s\033[0m\n" "Failed to download:" "$video_id" >&2
        # Check if the file is queued already
        elif grep -Fxq "$audio_file" "$queue_file"; then
            printf "\033[32m%-25s%s\033[0m\n" "Already in the queue:" "$audio_file_stem" >&2
        # Check if the file has been recently played
        elif grep -Fxq "$audio_file" "$recently_played_file"; then
            printf "\033[32m%-25s%s\033[0m\n" "File recently played:" "$audio_file_stem" >&2
        else
            # Queue the file
            printf "%s\n" "$audio_file" >> "$queue_file"
            printf "\033[32m%-25s%s\033[0m\n" "Queued:" "$audio_file_stem" >&2

            # Add the file to the recently played files list
            printf "%s\n" "$audio_file" >> "$recently_played_file"

            if (( recently_played_length > -1 )); then
                tail -n "$recently_played_length" "$recently_played_file" > "$recently_played_file.tmp"
                mv "$recently_played_file.tmp" "$recently_played_file"
            fi
        fi

        # Remove the current file from the download queue file
        tail -n +2 "$download_queue_file" > "$download_queue_file.tmp" && cat "$download_queue_file.tmp" > "$download_queue_file" && rm "$download_queue_file.tmp"
    done
}

play_queue() {
    while [[ -s "$queue_file" ]]; do
        local audio_file=$(head -n 1 "$queue_file")
        local audio_file_stem=${audio_file##*/}
        local audio_file_stem=${audio_file_stem%.*}

        # Remove the current file from the queue file
        tail -n +2 "$queue_file" > "$queue_file.tmp" && cat "$queue_file.tmp" > "$queue_file" && rm "$queue_file.tmp"

        if [[ -f "$audio_file" ]]; then
            printf "\033[33m%-25s%s\033[0m\n" "Now playing:" "$audio_file_stem" >&2

            [[ "$audio_file_stem" =~ \(([A-Za-z0-9_-]+)\)$ ]] && local video_id="${BASH_REMATCH[1]}"

            local clean_title="$(sed -E "${replacements[@]}" <<< "$audio_file_stem")"

            if (( RANDOM % 100 < interlude_chance )); then
                play_sound "interlude"
            fi

            local text_message_prefix="[RADIO] "
            local text_message_suffix=""
            [[ -n "$video_id" ]] && text_message_suffix=" ($video_id)"
            local truncated_title_length=$((127 - ${#text_message_prefix} - ${#text_message_suffix}))
            local truncated_title="$(sed 's/^ \+//g; s/ \+$//g; s/ \+/ /g;' <<< "$clean_title")"
            truncated_title="${truncated_title:0:$truncated_title_length}"

            send_text_message "${text_message_prefix}${truncated_title}${text_message_suffix}"

            # Clear votes
            vote_list=()

            touch "$voting_open_state_file"

            paplay --device=virtual_speaker --client-name=radio "$audio_file" >/dev/null 2>&1 &
            local paplay_pid=$!
            echo "$paplay_pid" > "$paplay_pid_file"
            wait "$paplay_pid"
            > "$paplay_pid_file"

            rm "$voting_open_state_file"
        else
            printf "\033[36m%-25s%s\033[0m\n" "File not found:" "$audio_file" >&2
        fi
    done
}

skip_current() {
    local paplay_pid=$(cat "$paplay_pid_file" 2>/dev/null)
    if [[ -n "$paplay_pid" ]]; then
        kill "$paplay_pid" 2>/dev/null
    fi
}

start_download_queue() {
    while true; do
        download_queue

        inotifywait -e modify "$download_queue_file" >/dev/null 2>&1
    done
}

start_queue() {
    trap '
        paplay_pid=$(cat "$paplay_pid_file" 2>/dev/null)
        if [[ -n "$paplay_pid" ]]; then
            kill "$paplay_pid" 2>/dev/null
            wait "$paplay_pid" 2>/dev/null
            rm -f "$paplay_pid_file"
        fi

        exit
    ' SIGINT SIGTERM EXIT

    while true; do
        play_queue

        printf "\033[36m%-25s%s\033[0m\n" "Queue:" "No more files in the queue" >&2

        inotifywait -e modify "$queue_file" >/dev/null 2>&1
    done
}


# Start the downloader in the background
start_download_queue &
echo $! > "$download_queue_pid_file"

# Start the audio player in the background
start_queue &
echo $! > "$queue_pid_file"


while IFS= read -r line; do
    # Search for lines containing a message
    if [[ "$line" =~ $re_line ]]; then
        # Extract the username and the message
        username="${BASH_REMATCH[3]}"
        message="${BASH_REMATCH[4]}"
    else
        continue
    fi

    # Remove messages from blacklisted players
    if [[ "$username" =~ $re_blacklisted_users ]]; then
        continue
    fi

    # Keep messages only from whitelisted players
    if [[ ! "$username" =~ $re_whitelisted_users ]]; then
        continue
    fi

    # Clear the old text message
    if [[ "$message" =~ $re_text_message_signal ]] || (
        [[ -n "$last_text_message_time" ]] && (( $(date +%s) - last_text_message_time > 5 ))
    ); then
        clear_text_message
        continue
    fi

    # Remove messages with blacklisted words
    shopt -s nocasematch
    if [[ "$message" =~ $re_blacklisted_words ]]; then
        continue
    fi
    shopt -u nocasematch

    # Search for messages containing a command
    if [[ "$message" =~ $re_command ]]; then
        # Extract the command and its argument
        command_name="${BASH_REMATCH[1],,}"
        command_text="${BASH_REMATCH[2]}"
    else
        continue
    fi

    if [[ "$command_name" == '!queue' ]] && [[ "$command_text" =~ $re_url ]]; then
        video_id="${BASH_REMATCH[4]}"

        printf "%s\t%s\n" "$video_id" "$username" >> "$download_queue_file"
    # Vote to skip the currently playing file
    elif [[ "$command_name" == '!skip' ]]; then
        # Check if there is a file playing
        if [[ -e "$voting_open_state_file" ]]; then
            # Check if the user has not voted yet
            if [[ ! -v vote_list["$username"] ]]; then
                vote_list["$username"]="$vote"

                remaining_vote_count=$(( required_vote_count - ${#vote_list[@]} ))

                printf "\033[34m%-25s%-10s%s\033[0m\n" "Voted to skip:" "$(( required_vote_count - remaining_vote_count ))/$required_vote_count:" "$username" >&2

                send_text_message "[RADIO] Remaining votes: ${remaining_vote_count}"

                if (( remaining_vote_count > 0 )); then
                    play_sound "$remaining_vote_count" &
                # Skip the currently playing file if the required number of skip votes has been reached
                else
                    printf "\033[36m%-25s%s\033[0m\n" "Queue:" "Skipping the file" >&2

                    clear_text_message

                    skip_current
                fi
            fi
        fi
    fi
# Continuously read the last line of the log as it is updated
done < <(tail -fn 1 "$console_log")
