#!/usr/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# Target list:
declare -A kill_messages=(
    # Example: ["John"]="John is gone!|John died. Shit happens."
    # Example: ["pablo.gonzales.2007"]="pablo is down!|pablo got owned!"
    # Example: ["Engineer Gaming"]="the grease monkey bites the dust!"
)

# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="${script_dir}/console.log"


piper_server="http://127.0.0.1:5000/synthesize"

re_line="^((.+) (suicided|died)|.+ killed (.+) with .+)\.( \(crit\))?$"


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

    paplay --device=virtual_speaker --client-name=piper "$audio_file" >/dev/null 2>&1
    rm -f "$audio_file"
}


while IFS= read -r line; do
    # Extract usernames
    if [[ "$line" =~ $re_line ]]; then
        username="${BASH_REMATCH[2]:-${BASH_REMATCH[4]}}"
    else
        continue
    fi

    if [[ -v kill_messages["$username"] ]]; then
        IFS="|" read -ra user_messages <<< "${kill_messages[$username]}"
        kill_message="${user_messages[RANDOM % ${#user_messages[@]}]}"

        speak_text "$kill_message" &
    fi
# Continuously read the last line of the log as it is updated
done < <(tail -fn 1 "$console_log")
