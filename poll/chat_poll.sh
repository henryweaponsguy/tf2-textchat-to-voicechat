#!/bin/bash

sound_dir="/tts/sounds"
vote_file="/tts/votes.txt"
poll_pid_file="/tmp/poll.pid"
poll_state_file="/tmp/poll.open"

touch "$vote_file"


cleanup() {
    if [ -e "$poll_state_file" ]; then
        rm "$poll_state_file"
    fi

    > "$vote_file"

    poll_pid=$(cat "$poll_pid_file" 2>/dev/null)
    if [ -n "$poll_pid" ]; then
        kill "$poll_pid" 2>/dev/null
        wait "$poll_pid" 2>/dev/null
        rm "$poll_pid_file"
    fi
}

trap cleanup SIGINT SIGTERM EXIT


play_sound() {
    paplay --client-name=poll "$sound_dir/${1}.wav" >/dev/null 2>&1
}

speak_text() {
    local text="$1"

    local audio_file="$(mktemp /tmp/dectalk_voice-XXXXXXXXXX.wav)"

    say -pre "[:name HARRY]" -e 1 -a "$text" -fo "$audio_file"

    paplay --client-name=poll "$audio_file" >/dev/null 2>&1
    rm -f "$audio_file"
}

start_poll() {
    required_vote_count=10
    time_limit=30

    play_sound "start"
    speak_text "A poll has started: $1"

    touch "$poll_state_file"

    start_time=$(date +%s)
    while (( $(( $(date +%s) - start_time )) < time_limit )); do
        sleep 1

        if (( $(wc -l < "$vote_file") >= required_vote_count )); then
            break
        fi
    done

    rm "$poll_state_file"

    if (( $(wc -l < "$vote_file") == 0 )); then
        play_sound "failure"
        speak_text "The poll has ended: nobody has voted."
    elif (( $(grep -c -- '----yes$' "$vote_file") > $(grep -c -- '----no$' "$vote_file") )); then
        play_sound "success"
        speak_text "The poll has ended: the majority has voted 'yes'."
    else
        play_sound "failure"
        speak_text "The poll has ended: the majority has voted 'no'."
    fi

    > "$vote_file"
}


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

# Word blacklist (all words must be in lowercase):
# Example: "nominate\|rtv\|nextmap"
# Default: "$^"
blacklisted_words="$^"

# Whitelist for creating a poll:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
# Default: ".*"
whitelisted_poll_names=".*"


while IFS= read -r line; do
    username=$(sed 's/\(\*DEAD\*\)\?\((TEAM)\)\? \?\(.\+\) : .\+/\3/' <<< "$line")
    command_content=$(sed 's/^.* :  ![a-zA-Z0-9_]\+ *//' <<< "$line")

    if grep -q '!poll' <<< "$line" && grep -q "$whitelisted_poll_names" <<< "$line"; then
        if [ ! -e "$poll_state_file" ]; then
            start_poll "$command_content" &
            echo $! > "$poll_pid_file"
        fi
    elif grep -q '!pollvote' <<< "$line"; then
        # Check if the poll is open
        if [ -e "$poll_state_file" ]; then
            # Check if the user has not voted yet
            if ! grep -q "$username" "$vote_file"; then
                if [[ "$command_content" =~ ^y[A-Za-z0-9_-]+ ]]; then
                    echo "${username}----yes" >> "$vote_file"
                    play_sound "yes" &
                elif [[ "$command_content" =~ ^n[A-Za-z0-9_-]+ ]]; then
                    echo "${username}----no" >> "$vote_file"
                    play_sound "no" &
                fi
            fi
        fi
    fi
done < <(
    # Continuously read the last line of the log as it is updated
    stdbuf -oL tail -fn 1 "$console_log" |
    # Search for lines containing the command
    grep --line-buffered -E ' :  !(poll|pollvote) ' |
    # Remove messages from blacklisted players
    grep --line-buffered -v "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${blacklisted_names} :  !" |
    # Keep messages only from whitelisted players
    grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${whitelisted_names} :  !" |
    # Sanitize the message
    stdbuf -o0 sed 's/[$;`()]//g' |
    # Replace certain patterns
    stdbuf -o0 sed  -e 's/btw/by the way/g' \
                    -e 's/wtf/what the fuck/g' \
                    -e 's/idk/i don'\''t know/g' |
    # Remove non-ASCII and control characters
    stdbuf -o0 tr -cd '[:alnum:][:space:][:punct:]' |
    # Remove messages with blacklisted words
    grep --line-buffered -v "$blacklisted_words" |
    # Remove messages with excessive repetition
    grep --line-buffered -Ev '(.{2,})\1{5,}'
)
