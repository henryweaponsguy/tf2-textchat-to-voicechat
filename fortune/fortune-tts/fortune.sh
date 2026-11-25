#!/usr/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# Minimum time between messages (in seconds)
rate_limit=0

# Fortune list file
fortune_file="${script_dir}/fortunes.txt"

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


piper_server="http://127.0.0.1:5000/synthesize"
announcer_pid_file="/tmp/announcer.pid"
declare -A rate_limiting

re_line="^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.+)"
re_command=("^(![fF][oO][rR][tT][uU][nN][eE])")
re_blacklisted_users="${blacklisted_users:-$^}"
re_whitelisted_users="${whitelisted_users:-.*}"


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
    # Skip the incoming announcement if there is one playing already
    announcer_pid=$(cat "$announcer_pid_file" 2>/dev/null)
    if [[ -n "$announcer_pid" ]]; then
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

    # Search for messages containing a command
    if [[ ! "$message" =~ $re_command ]]; then
        continue
    fi

    current_time="$(date +%s)"

    if [[ -v rate_limiting["$username"] ]] &&
        (( current_time - rate_limiting["$username"] <= rate_limit )); then
        continue
    fi

    rate_limiting["$username"]="$current_time"

    selected_fortune="$(grep -v '^$' "$fortune_file" | shuf -n1)"

    (speak_text "$selected_fortune") &
# Continuously read the last line of the log as it is updated
done < <(tail -fn 1 "$console_log")
