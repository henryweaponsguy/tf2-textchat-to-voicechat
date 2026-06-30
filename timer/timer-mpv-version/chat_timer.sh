#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="${script_dir}/console.log"

# User blacklist:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
blacklisted_names=""

# Alternatively, a whitelist:
whitelisted_names=""


# Continuously read the last line of the log as it is updated
stdbuf -oL tail -fn 1 "$console_log" |
# Search for lines containing the command
grep --line-buffered "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?[^:]\+ :  !timer [0-9]\+" |
# Remove messages from blacklisted players
grep --line-buffered -v "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?${blacklisted_names:-$^} :  !" |
# Keep messages only from whitelisted players
grep --line-buffered "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?${whitelisted_names:-.*} :  !" |
# Extract the duration
stdbuf -o0 sed 's/^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?[^:]\+ :  ![a-zA-Z0-9_]\+ *//' |
# Start the timer
"${script_dir}/get_timer.sh"
