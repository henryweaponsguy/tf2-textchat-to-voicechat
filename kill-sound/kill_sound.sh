#!/usr/bin/bash

shopt -s nullglob

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


for username in "${!user_directories[@]}"; do
    mkdir -p "$sound_dir/${user_directories[$username]}"
done

re_line="^((.+) (suicided|died)|.+ killed (.+) with .+)\.( \(crit\))?$"


while IFS= read -r line; do
    # Extract usernames
    if [[ "$line" =~ $re_line ]]; then
        username="${BASH_REMATCH[2]:-${BASH_REMATCH[4]}}"
    else
        continue
    fi

    if [[ ! -v user_directories["$username"] ]]; then
        continue
    fi

    # Match files
    matched_files=(
        "$sound_dir/${user_directories[$username]}/"*.*
        "$sound_dir/${user_directories[$username]}/"* [0-9]*.*
    )

    if (( ${#matched_files[@]} )); then
        selected_file="${matched_files[RANDOM % ${#matched_files[@]}]}"

        paplay --device=virtual_speaker --client-name=soundboard "$selected_file" >/dev/null 2>&1 &
    fi
# Continuously read the last line of the log as it is updated
done < <(tail -fn 1 "$console_log")
