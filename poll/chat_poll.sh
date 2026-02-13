#!/bin/bash

exit_cleanup() {
    if [ -e "$poll_open_state_file" ]; then
        rm "$poll_open_state_file"
    fi

    if [ -e "$poll_running_state_file" ]; then
        rm "$poll_running_state_file"
    fi

    if [ -e "$vote_file" ]; then
        rm "$vote_file"
    fi

    poll_pid=$(cat "$poll_pid_file" 2>/dev/null)
    if [ -n "$poll_pid" ]; then
        kill "$poll_pid" 2>/dev/null
        wait "$poll_pid" 2>/dev/null
        rm "$poll_pid_file"
    fi
}

# Exit cleanly on CTRL+C and system shutdown
trap exit_cleanup SIGINT SIGTERM EXIT


sound_dir="/tts/sounds"
vote_file="/tts/votes.txt"
poll_pid_file="/tmp/poll.pid"
poll_open_state_file="/tmp/poll.open"
poll_running_state_file="/tmp/poll.running"

touch "$vote_file"


# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="/tts/console.log"

# User blacklist:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
# Empty: "$^"
blacklisted_names="$^"

# Alternatively, a whitelist:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
# Empty: ".*"
whitelisted_names=".*"

# Word blacklist:
# Example: "nominate\|rtv\|nextmap"
# Empty: "$^"
blacklisted_words="$^"

# Whitelist for creating a poll:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
# Empty: ".*"
whitelisted_poll_names=".*"


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
    touch "$poll_running_state_file"

    local required_vote_count=10
    local time_limit=30

    play_sound "start"
    speak_text "A poll has started: $1"

    touch "$poll_open_state_file"

    local start_time=$(date +%s)
    while (( $(( $(date +%s) - start_time )) < time_limit )); do
        sleep 1

        if (( $(wc -l < "$vote_file") >= required_vote_count )); then
            break
        fi
    done

    rm "$poll_open_state_file"

    yes_count=$(grep -c -- '--SEP--yes$' "$vote_file")
    no_count=$(grep -c -- '--SEP--no$' "$vote_file")

    if (( $(wc -l < "$vote_file") == 0 )); then
        play_sound "failure"
        speak_text "The poll has ended: nobody has voted."
    elif (( "$yes_count" > "$no_count" )); then
        play_sound "success"
        speak_text "The poll has ended: the majority has voted 'yes'."
    elif (( "$yes_count" == "$no_count" )); then
        play_sound "failure"
        speak_text "The poll has ended in a draw."
    else
        play_sound "failure"
        speak_text "The poll has ended: the majority has voted 'no'."
    fi

    rm "$poll_running_state_file"
    > "$vote_file"
}


while IFS= read -r line; do
    command_input=$(sed 's/^\(\*DEAD\*\)\?\((TEAM)\)\? \?.\+ :  ![a-zA-Z0-9_]\+ *//' <<< "$line")

    if grep -q '!poll ' <<< "$line" && grep -q "$whitelisted_poll_names" <<< "$line"; then
        # Check if the poll is running
        if [ ! -e "$poll_running_state_file" ]; then
            start_poll "$command_input" &
            echo $! > "$poll_pid_file"
        fi
    elif grep -q '!pollvote ' <<< "$line"; then
        # Check if the poll is open
        if [ -e "$poll_open_state_file" ]; then
            username=$(sed 's/^\(\*DEAD\*\)\?\((TEAM)\)\? \?\(.\+\) :  .\+/\3/' <<< "$line")

            # Check if the user has not voted yet
            if ! grep -q "$username" "$vote_file"; then
                if [[ "$command_input" =~ ^y[a-zA-Z0-9_-]* ]]; then
                    echo "${username}--SEP--yes" >> "$vote_file"
                    play_sound "yes" &
                elif [[ "$command_input" =~ ^n[a-zA-Z0-9_-]* ]]; then
                    echo "${username}--SEP--no" >> "$vote_file"
                    play_sound "no" &
                fi
            fi
        fi
    fi
done < <(
    # Continuously read the last line of the log as it is updated
    stdbuf -oL tail -fn 1 "$console_log" |
    # Search for lines containing the command
    grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?.\+ :  !\(poll\|pollvote\) " |
    # Remove messages from blacklisted players
    grep --line-buffered -v "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${blacklisted_names} :  !" |
    # Keep messages only from whitelisted players
    grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${whitelisted_names} :  !" |
    # Sanitize the message
    stdbuf -o0 sed 's/[$;`()]//g' |
    # Replace certain patterns
    stdbuf -o0 sed  -e 's/btw/by the way/gI' \
                    -e 's/wtf/what the fuck/gI' \
                    -e 's/idk/i don'\''t know/gI' |
    # Remove messages with blacklisted words
    grep --line-buffered -iv "$blacklisted_words" |
    # Remove messages with excessive repetition
    grep --line-buffered -Ev '(.{2,})\1{5,}' |
    # Remove non-ASCII and control characters
    stdbuf -o0 tr -cd '[:alnum:][:space:][:punct:]' |
    # Trim and normalize whitespace
    stdbuf -o0 sed 's/^ \+//g; s/ \+$//g; s/ \+/ /g;'
)
