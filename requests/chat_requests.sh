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

# Word blacklist:
# Example: "dQw4w9WgXcQ\|dwDns8x3Jb4\|ZZ5LpwO-An4"
blacklisted_words=""


while IFS= read -r line; do
    username=$(sed -n 's/^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?\([^:]\+\) :  .\+/\3/p' <<< "$line")
    message=$(sed -n 's/^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?[^:]\+ :  ![a-zA-Z0-9_]\+ \(.\+\)/\3/p' <<< "$line")

    title=""
    channel=""
    if [[ "$line" =~ (https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)([A-Za-z0-9_-]+) ]]; then
        video_id="${BASH_REMATCH[-1]}"

        metadata=$(
            yt-dlp \
                --js-runtimes "deno:/root/.deno/bin/deno" \
                --add-headers "User-Agent:Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36" \
                --limit-rate 500K \
                --skip-download \
                --no-warnings \
                -o "%(title)s" \
                --print "%(filename)s--SEP--%(channel)s" \
                -- "$video_id"
        )
        title="${metadata%%--SEP--*}"
        channel="${metadata#*--SEP--}"
    fi

    printf "%s\t%s\t%s\t%s\n" "$username" "$message" "$title" "$channel"
done < <(
    # Continuously read the last line of the log as it is updated
    stdbuf -oL tail -fn 1 "$console_log" |
    # Search for lines containing the command
    grep --line-buffered "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?[^:]\+ :  !request " |
    # Remove messages from blacklisted players
    grep --line-buffered -v "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?${blacklisted_names:-$^} :  !" |
    # Keep messages only from whitelisted players
    grep --line-buffered "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?${whitelisted_names:-.*} :  !" |
    # Remove messages with blacklisted words
    grep --line-buffered -v "${blacklisted_words:-$^}"
)
