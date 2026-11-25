#!/usr/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="${script_dir}/console.log"

# User blacklist:
# Example: "John|pablo\.gonzales\.2007|Engineer Gaming"
blacklisted_users=""

# Alternatively, a whitelist:
whitelisted_users=""

# Word blacklist:
# Example: "dQw4w9WgXcQ|dwDns8x3Jb4|ZZ5LpwO-An4"
blacklisted_words=""


re_line="^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *![rR][eE][qQ][uU][eE][sS][tT] +(.+)"
re_url="(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)([A-Za-z0-9_-]+)"
re_blacklisted_users="${blacklisted_users:-$^}"
re_whitelisted_users="${whitelisted_users:-.*}"
re_blacklisted_words="${blacklisted_words:-$^}"


while IFS= read -r line; do
    # Search for lines containing a command
    if [[ "$line" =~ $re_line ]]; then
        # Extract the username and the video URL
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

    # Remove messages with blacklisted words
    shopt -s nocasematch
    if [[ "$message" =~ $re_blacklisted_words ]]; then
        continue
    fi
    shopt -u nocasematch

    title=""
    channel=""
    # Check if the video URL is valid
    if [[ "$message" =~ $re_url ]]; then
        video_id="${BASH_REMATCH[4]}"

        metadata=$(
            yt-dlp \
                --js-runtimes "deno" \
                --add-headers "User-Agent:Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/157.0.0.0 Safari/537.36" \
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
# Continuously read the last line of the log as it is updated
done < <(tail -fn 1 "$console_log")

