#!/usr/bin/bash

shopt -s nullglob

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# Notification sounds directory
sound_dir="${script_dir}/sounds"

# Add '-condebug' to TF2's launch parameters.
# Alternatively add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="${script_dir}/console.log"

# User blacklist:
# Example: "John|pablo\.gonzales\.2007|Engineer Gaming"
blacklisted_users=""

# Alternatively, a whitelist:
whitelisted_users=""

# Word whitelist:
# Example: "your_username|help|afk"
whitelisted_words=""


player_process=""
previous_line=""

re_line="^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :  "
re_blacklisted_users="${blacklisted_users:-$^}"
re_whitelisted_users="${whitelisted_users:-.*}"
re_whitelisted_words="${whitelisted_words:-.*}"


while IFS= read -r line; do
    # Skip the incoming notification if there is one playing already
    if [[ -n "$player_process" ]] && kill -0 "$player_process" 2>/dev/null; then
        continue
    fi

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

    # Remove duplicate messages
#     if [[ "$line" == "$previous_line" ]]; then
#         continue
#     fi
#     previous_line="$line"

    # Keep messages only with whitelisted words
    shopt -s nocasematch
    if [[ ! "$message" =~ $re_whitelisted_users ]]; then
        continue
    fi
    shopt -u nocasematch

    matched_files=( "$sound_dir/"*.* )

    if (( ${#matched_files[@]} )); then
        selected_file="${matched_files[RANDOM % ${#matched_files[@]}]}"

        paplay --client-name=chat-notification "$selected_file" >/dev/null 2>&1 &
        player_process="$!"
    fi
# Continuously read the last line of the log as it is updated
done < <(tail -fn 1 "$console_log")
