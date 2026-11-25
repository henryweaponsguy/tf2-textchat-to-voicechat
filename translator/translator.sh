#!/usr/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


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


re_line="^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.+)"
re_blacklisted_users="${blacklisted_users:-$^}"
re_whitelisted_users="${whitelisted_users:-.*}"
re_blacklisted_words="${blacklisted_words:-$^}"
re_repetition="(.{2,})\1{5,}"


while IFS= read -r line; do
    # Search for lines containing a command
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
    if [[ "$message" =~ $re_blacklisted_words ]]; then
        continue
    fi
    shopt -u nocasematch

    # Remove messages with excessive repetition
    if grep -Pq "$re_repetition" <<< "$message"; then
        continue
    fi

    # Trim and normalize whitespace
    message="$(sed 's/^ \+//g; s/ \+$//g; s/ \+/ /g;' <<< "$message")"

    [[ -z "$message" ]] && continue

    "${script_dir}/get_translation.sh" "$message" &
# Continuously read the last line of the log as it is updated
done < <(tail -fn 1 "$console_log")
