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


timer_pid_file="/tmp/timer.pid"

re_line="^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *![tT][iI][mM][eE][rR] +([0-9]+)"
re_blacklisted_users="${blacklisted_users:-$^}"
re_whitelisted_users="${whitelisted_users:-.*}"


while IFS= read -r line; do
    # Skip the incoming timer if there is one running already
    timer_pid=$(cat "$timer_pid_file" 2>/dev/null)
    if [[ -n "$timer_pid" ]]; then
        continue
    fi

    # Extract usernames and duration
    if [[ "$line" =~ $re_line ]]; then
        username="${BASH_REMATCH[3]}"
        duration="${BASH_REMATCH[4]}"
    fi

    # Remove messages from blacklisted players
    if [[ "$username" =~ $re_blacklisted_users ]]; then
        continue
    fi

    # Keep messages only from whitelisted players
    if [[ ! "$username" =~ $re_whitelisted_users ]]; then
        continue
    fi

    # Start the timer
    "${script_dir}/get_timer.sh" "$duration" &
# Continuously read the last line of the log as it is updated
done < <(tail -fn 1 "$console_log")
