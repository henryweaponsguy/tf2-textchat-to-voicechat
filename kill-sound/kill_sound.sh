#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# Target list:
declare -A user_directories=(
    # Example: ["John"]="john"
    # Example: ["pablo.gonzales.2007"]="pablo"
    # Example: ["Engineer Gaming"]="engineer gaming"
)

# Kill sounds directory
sound_dir="${script_dir}/sounds"


# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="${script_dir}/console.log"


while IFS= read -r username; do
    if [[ ! -v user_directories["$username"] ]]; then
        continue
    fi

    # Match files
    shopt -s nullglob
    matched_files=(
        "$sound_dir/${user_directories[$username]}/"*.*
        "$sound_dir/${user_directories[$username]}/"* [0-9]*.*
    )
    shopt -u nullglob

    if [[ ${#matched_files[@]} -gt 0 ]]; then
        selected_file="${matched_files[RANDOM % ${#matched_files[@]}]}"

        paplay --device=virtual_speaker --client-name=soundboard "$selected_file" >/dev/null 2>&1 &
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