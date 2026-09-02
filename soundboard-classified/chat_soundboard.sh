#!/bin/bash

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
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
blacklisted_names=""

# Alternatively, a whitelist:
whitelisted_names=""

# Word blacklist:
# Example: "nominate\|rtv\|nextmap"
blacklisted_words=""


declare -A rate_limiting


while IFS= read -r line; do
    # Extract usernames and messages
    username="$(sed -n 's/^\(\*DEAD\*\|\*SPEC\* \)\?\((TEAM) \)\?\([^:]\+\): .\+/\3/p' <<< "$line")"
    #message="$(sed -n 's/^\(\*DEAD\*\|\*SPEC\* \)\?\((TEAM) \)\?[^:]\+: ![a-zA-Z0-9_]\+ \(.\+\)/\3/p' <<< "$line")"
    message="$(sed -n 's/^\(\*DEAD\*\|\*SPEC\* \)\?\((TEAM) \)\?[^:]\+: \(.\+\)/\3/p' <<< "$line")"

    message="$(
        # Convert the message to lowercase
        printf '%s' "${message,,}" |
        # Remove non-ASCII and control characters
        tr -cd '[:alnum:][:space:][:punct:]' |
        # Trim and normalize whitespace
        sed 's/^ \+//g; s/ \+$//g; s/ \+/ /g;'
    )"

    # Match files
    shopt -s nullglob
    matched_files=(
        "$sound_dir/$message".*
        "$sound_dir/$message "[0-9]*.*
    )
    shopt -u nullglob

    if [[ ${#matched_files[@]} -eq 0 ]]; then
        continue
    fi

    current_time="$(date +%s)"

    if [[ -v rate_limiting["$username"] ]] &&
        (( current_time - rate_limiting["$username"] <= rate_limit )); then
        continue
    fi

    rate_limiting["$username"]="$current_time"

    selected_file="${matched_files[RANDOM % ${#matched_files[@]}]}"

    paplay --device=virtual_speaker --client-name=soundboard "$selected_file" >/dev/null 2>&1 &
done < <(
    # Continuously read the last line of the log as it is updated
    stdbuf -oL tail -fn 1 "$console_log" |
    # Search for lines containing the command
    #grep --line-buffered "^\(\*DEAD\*\|\*SPEC\* \)\?\((TEAM) \)\?[^:]\+: !play " |
    grep --line-buffered "^\(\*DEAD\*\|\*SPEC\* \)\?\((TEAM) \)\?[^:]\+: " |
    # Remove messages from blacklisted players
    #grep --line-buffered -v "^\(\*DEAD\*\|\*SPEC\* \)\?\((TEAM) \)\?${blacklisted_names:-$^}: !" |
    grep --line-buffered -v "^\(\*DEAD\*\|\*SPEC\* \)\?\((TEAM) \)\?${blacklisted_names:-$^}: " |
    # Keep messages only from whitelisted players
    #grep --line-buffered "^\(\*DEAD\*\|\*SPEC\* \)\?\((TEAM) \)\?${whitelisted_names:-.*}: !" |
    grep --line-buffered "^\(\*DEAD\*\|\*SPEC\* \)\?\((TEAM) \)\?${whitelisted_names:-.*}: " |
    # Remove messages with blacklisted words
    grep --line-buffered -iv "${blacklisted_words:-$^}"
    # Remove duplicate messages
    #| stdbuf -o0 uniq
)
