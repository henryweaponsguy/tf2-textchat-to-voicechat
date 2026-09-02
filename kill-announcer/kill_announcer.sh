#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# Target list:
declare -A kill_messages=(
    # Example: ["John"]="John is gone!|John died. Shit happens."
    # Example: ["pablo.gonzales.2007"]="pablo is down!|pablo got owned!"
    # Example: ["Engineer Gaming"]="the grease monkey bites the dust!"
)

piper_server="http://localhost:5000/synthesize"


# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="${script_dir}/console.log"


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


while IFS= read -r username; do
    if [[ -v kill_messages["$username"] ]]; then
        IFS="|" read -ra user_messages <<< "${kill_messages[$username]}"
        kill_message="${user_messages[RANDOM % ${#user_messages[@]}]}"

        speak_text "$kill_message" &
    fi
done < <(
    # Continuously read the last line of the log as it is updated
    stdbuf -oL tail -fn 1 "$console_log" |
    # Search for lines containing the command
    grep --line-buffered "^\(.\+ \(suicided\|died\)\|.\+ killed .\+ with .\+\)\.\( (crit)\)\?$" |
    # Extract the username
    stdbuf -o0 sed -E 's/^(.+) (suicided|died)\.( \(crit\))?$/\1/' |
    stdbuf -o0 sed -E 's/^.+ killed (.+) with .+\.( \(crit\))?$/\1/'
)
