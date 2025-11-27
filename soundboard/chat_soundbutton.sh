#!/bin/bash

sound_dir="/tts/sounds"


play_audio() {
    while IFS= read -r line; do
        shopt -s nullglob
        matches=( "$sound_dir/"*.* )
        shopt -u nullglob

        if [[ ${#matches[@]} -gt 0 ]]; then
            selected="${matches[RANDOM % ${#matches[@]}]}"

            paplay --client-name=soundbutton "$selected" >/dev/null 2>&1 &
        fi
    done
}


# Add '-condebug' as TF2's launch parameter.
# Alternatively add "con_logfile <logfile location>" to autoexec.cfg
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="/tts/console.log"

# User blacklist:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
# Default: "$^"
blacklisted_names="$^"

# Alternatively, a whitelist:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
# Default: ".*"
whitelisted_names=".*"


# Continuously read the last line of the log as it is updated
stdbuf -oL tail -fn 1 "$console_log" |
# Search for lines containing the command
grep --line-buffered ' :  !play' |
# Remove messages from blacklisted players
grep --line-buffered -v "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${blacklisted_names} :  !" |
# Keep messages only from whitelisted players
grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${whitelisted_names} :  !" |
# Remove duplicate messages
#stdbuf -o0 uniq |
# Play the audio file
play_audio
