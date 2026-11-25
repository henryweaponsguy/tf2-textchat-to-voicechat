#!/usr/bin/bash

shopt -s nullglob

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# Minimum time between messages (in seconds)
rate_limit=0

# Soundboard sounds directory
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

# Word blacklist:
# Example: "nominate|rtv|nextmap"
blacklisted_words=""


declare -A rate_limiting
previous_line=""

re_line="^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.+)"
re_blacklisted_users="${blacklisted_users:-$^}"
re_whitelisted_users="${whitelisted_users:-.*}"
re_blacklisted_words="${blacklisted_words:-$^}"


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

    # Remove duplicate messages
#     if [[ "$line" == "$previous_line" ]]; then
#         continue
#     fi
#     previous_line="$line"

    # Remove messages with blacklisted words
    shopt -s nocasematch
    if [[ "$line" =~ $re_blacklisted_words ]]; then
        continue
    fi
    shopt -u nocasematch

    # Remove non-ASCII and control characters
    message="$(LC_ALL=C tr -cd '[:alnum:][:space:][:punct:]' <<< "$message")"

    # Convert the message to lowercase
    message="${message,,}"

    # Trim and normalize whitespace
    message="$(sed 's/^ \+//g; s/ \+$//g; s/ \+/ /g;' <<< "$message")"

    [[ -z "$message" ]] && continue


    matched_files=(
        "$sound_dir/$message".*
        "$sound_dir/$message "[0-9]*.*
    )

    if (( ! ${#matched_files[@]} )); then
        continue
    fi

    # Apply rate limiting
    current_time="$(date +%s)"

    if [[ -v rate_limiting["$username"] ]] &&
        (( current_time - rate_limiting["$username"] <= rate_limit )); then
        continue
    fi

    rate_limiting["$username"]="$current_time"

    selected_file="${matched_files[RANDOM % ${#matched_files[@]}]}"

    paplay --device=virtual_speaker --client-name=soundboard "$selected_file" >/dev/null 2>&1 &
# Continuously read the last line of the log as it is updated
done < <(tail -fn 1 "$console_log")
