#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# Minimum time between messages (in seconds)
rate_limit=20

# Fortune list file
fortune_file="${script_dir}/fortunes.txt"


# Add '-condebug' to TF2's launch parameters.
# Alternatively add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="${script_dir}/console.log"

# User blacklist:
# Example: "John\|pablo\.gonzales\.2007\|Engineer Gaming"
blacklisted_names=""

# Alternatively, a whitelist:
whitelisted_names=""

# Word blacklist:
# Example: "nominate\|rtv\|nextmap"
blacklisted_words=""


piper_server="http://localhost:5000/synthesize"
announcer_pid_file="/tmp/announcer.pid"
declare -A rate_limiting


speak_text() {
    local text="$1"

    local audio_file="$(mktemp /tmp/piper_voice-XXXXXXXXXX.wav)"

    data="$(
cat <<EOF
{
    "text": "$text",
    "voice": "en_US-joe-medium",
    "length_scale": "1"
}
EOF
)"

    curl -X POST -H "Content-Type: application/json" --data "$data" \
    --silent --show-error --output "$audio_file" "$piper_server"

    paplay --device=virtual_speaker --client-name=piper "$audio_file" >/dev/null 2>&1 &
    local announcer_pid=$!
    echo "$announcer_pid" > "$announcer_pid_file"
    wait "$announcer_pid"
    > "$announcer_pid_file"

    rm -f "$audio_file"
}


while IFS= read -r line; do
    # Skip the current announcement if there is one playing already
    announcer_pid=$(cat "$announcer_pid_file" 2>/dev/null)
    if [ -n "$announcer_pid" ]; then
        continue
    fi

    # Extract usernames
    username="$(sed -n 's/^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?\([^:]\+\) :  .\+/\3/p' <<< "$line")"

    current_time="$(date +%s)"

    if [[ -v rate_limiting["$username"] ]] &&
        (( current_time - rate_limiting["$username"] <= rate_limit )); then
        continue
    fi

    rate_limiting["$username"]="$current_time"

    selected_fortune="$(shuf -n1 "$fortune_file")"

    (speak_text "$selected_fortune") &
done < <(
    # Continuously read the last line of the log as it is updated
    stdbuf -oL tail -fn 1 "$console_log" |
    # Search for lines containing the command
    grep --line-buffered "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?[^:]\+ :  !fortune" |
    # Remove messages from blacklisted players
    grep --line-buffered -v "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?${blacklisted_names:-$^} :  !" |
    # Keep messages only from whitelisted players
    grep --line-buffered "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?${whitelisted_names:-.*} :  !"
    # Remove duplicate messages
    #| stdbuf -o0 uniq
)
