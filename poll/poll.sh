#!/usr/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


exit_cleanup() {
    > "$text_message_file"

    if [[ -e "$poll_open_state_file" ]]; then
        rm "$poll_open_state_file"
    fi

    if [[ -e "$poll_running_state_file" ]]; then
        rm "$poll_running_state_file"
    fi

    poll_pid=$(cat "$poll_pid_file" 2>/dev/null)
    if [[ -n "$poll_pid" ]]; then
        kill "$poll_pid" 2>/dev/null
        wait "$poll_pid" 2>/dev/null
        rm "$poll_pid_file"
    fi
}


# Exit cleanly on CTRL+C and system shutdown
trap exit_cleanup SIGINT SIGTERM EXIT


# Required votes for the poll to close automatically
required_vote_count=24

# The time after which the poll closes
time_limit=30

# Poll sounds directory
sound_dir="${script_dir}/sounds"

# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="${script_dir}/console.log"

# User blacklist:
# Example: "John|pablo\.gonzales\.2007|Engineer Gaming"
blacklisted_users=""

# Alternatively, a whitelist:
whitelisted_users=""

# Word blacklist:
# Example: "nominate|rtv|nextmap"
blacklisted_words=""

# Whitelist for starting a poll:
# Example: "John|pablo\.gonzales\.2007|Engineer Gaming"
whitelisted_poll_users=""


poll_pid_file="/tmp/poll.pid"
poll_open_state_file="/tmp/poll.open"
poll_running_state_file="/tmp/poll.running"

> "$text_message_file"

declare -A vote_list
last_text_message_time=""

re_line="^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.+)"
re_command=("^(![pP][oO][lL][lL]|[yY][eE][sS]|[nN][oO]) *(.+)?")
re_text_message_signal=("^\[ ?POLL\]")
re_vote="^yes|no$"
re_blacklisted_users="${blacklisted_users:-$^}"
re_whitelisted_users="${whitelisted_users:-.*}"
re_whitelisted_poll_users="${whitelisted_poll_users:-.*}"
re_blacklisted_words="${blacklisted_words:-$^}"
re_repetition="(.{2,})\1{5,}"

replacements=(
    -e "s/btw/by the way/gI"
    -e 's/wtf/what the fuck/gI'
    -e "s/idk/i don't know/gI"
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
    paplay --device=virtual_speaker --client-name=poll "$sound_dir/${1}.wav" >/dev/null 2>&1
}

start_poll() {
    touch "$poll_running_state_file"

    play_sound "start"
    send_text_message "[POLL] $1"

    touch "$poll_open_state_file"

    local start_time=$(date +%s)
    while (( $(( $(date +%s) - start_time )) < time_limit )); do
        sleep 1

        if (( ${#vote_list[@]} >= required_vote_count )); then
            break
        fi
    done

    rm "$poll_open_state_file"

    total_count="${#vote_list[@]}"
    yes_count=0

    for value in "${vote_list[@]}"; do
        [[ "$value" == "yes" ]] && ((++yes_count))
    done

    if (( total_count == 0 )); then
        play_sound "failure"
        send_text_message "[POLL] Nobody has voted."
    elif (( yes_count * 2 > total_count )); then
        play_sound "success"
        send_text_message "[POLL] The majority has voted 'yes' (${yes_count}/${total_count})"
    elif (( yes_count * 2 == total_count )); then
        play_sound "failure"
        send_text_message "[POLL] The poll has ended in a draw (${yes_count}/${total_count})"
    else
        play_sound "failure"
        send_text_message "[POLL] The majority has voted 'no' (${yes_count}/${total_count})"
    fi

    rm "$poll_running_state_file"
    vote_list=()
}


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

    if [[ "$command_name" == '!poll' ]] && [[ "$username" =~ $re_whitelisted_poll_users ]]; then
        # Check if the poll is running
        if [[ ! -e "$poll_running_state_file" ]]; then
            # Replace certain patterns
            command_text="$(sed "${replacements[@]}" <<< "$command_text")"

            # Remove messages with excessive repetition
            if grep -Pq "$re_repetition" <<< "$command_text"; then
                continue
            fi

            # Remove non-ASCII and control characters
            command_text="$(LC_ALL=C tr -cd '[:alnum:][:space:][:punct:]' <<< "$command_text")"

            # Trim and normalize whitespace
            command_text="$(sed 's/^ \+//g; s/ \+$//g; s/ \+/ /g;' <<< "$command_text")"
            [[ -z "$command_text" ]] && continue

            start_poll "$command_text" &
            echo $! > "$poll_pid_file"
        fi
    elif [[ "$command_name" =~ $re_vote ]]; then
        vote="${BASH_REMATCH[0]}"

        # Check if the poll is open
        if [[ -e "$poll_open_state_file" ]]; then
            # Check if the user has not voted yet
            if [[ ! -v vote_list["$username"] ]]; then
                vote_list["$username"]="$vote"
                play_sound "$vote" &
            fi
        fi
    fi
# Continuously read the last line of the log as it is updated
done < <(tail -fn 1 "$console_log")
