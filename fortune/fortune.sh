#!/usr/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


exit_cleanup() {
    > "$text_message_file"
}


# Exit cleanly on CTRL+C and system shutdown
trap exit_cleanup SIGINT SIGTERM EXIT


# Minimum time between messages (in seconds)
rate_limit=5

# Fortune list file
fortune_file="${script_dir}/fortunes.txt"

# Add '-condebug' to TF2's launch parameters.
# Alternatively add "con_logfile <logfile location>" to TF2's autoexec.cfg,
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
# Example: "nominate|rtv|nextmap"
blacklisted_words=""


> "$text_message_file"

last_text_message_time=""

re_line="^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.+)"
re_command=("^(![fF][oO][rR][tT][uU][nN][eE])")
re_text_message_signal=("^\[ ?FORTUNE\]")
re_blacklisted_users="${blacklisted_users:-$^}"
re_whitelisted_users="${whitelisted_users:-.*}"


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

    # Search for messages containing a command
    if [[ ! "$message" =~ $re_command ]]; then
        continue
    fi

    # Apply rate limiting
    if [[ -n "$last_text_message_time" ]] && (( $(date +%s) - last_text_message_time <= rate_limit )); then
        continue
    fi

    selected_fortune="$(grep -v '^$' "$fortune_file" | shuf -n1)"

    send_text_message "[FORTUNE] $selected_fortune"
# Continuously read the last line of the log as it is updated
done < <(tail -fn 1 "$console_log")
