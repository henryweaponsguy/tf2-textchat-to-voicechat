#!/usr/bin/env python3

import json
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

script_dir = Path(__file__).resolve().parent


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log = script_dir / "console.log"

# User blacklist:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
blacklisted_users = ""

# Alternatively, a whitelist:
whitelisted_users = ""

# Word blacklist:
# Example: "dQw4w9WgXcQ|dwDns8x3Jb4|ZZ5LpwO-An4"
blacklisted_words = ""


re_line = re.compile(r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(?i:!request) +(.+)")
re_blacklisted_users = re.compile(rf"{blacklisted_users or '$^'}")
re_whitelisted_users = re.compile(rf"{whitelisted_users or '.*'}")
re_blacklisted_words = re.compile(rf"{blacklisted_words or '$^'}", re.IGNORECASE)
re_url = re.compile(
    r"(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)([A-Za-z0-9_-]+)"
)


with open(console_log, "r", encoding="utf-8", errors="ignore") as log:
    # Jump to the end of the file
    log.seek(0, 2)

    # Continuously read the last line of the log as it is updated
    while True:
        line = log.readline()
        if not line:
            time.sleep(0.1)
            continue

        # Remove the trailing newline
        line = line.rstrip("\n")

        # Search for lines containing a command
        matched_line = re_line.match(line)
        if not matched_line:
            continue

        # Extract the username and the video URL
        username = matched_line.group(3)
        message = matched_line.group(4)

        # Remove messages from blacklisted players
        if re_blacklisted_users.search(username):
            continue

        # Keep messages only from whitelisted players
        if not re_whitelisted_users.search(username):
            continue

        # Remove messages with blacklisted words
        if re_blacklisted_words.search(message):
            continue

        title = ""
        channel = ""
        # Check if the video URL is valid
        matched_video_url = re_url.match(message)
        if matched_video_url:
            video_id = matched_video_url.group(4)

            yt_dlp_output = subprocess.run(
                [
                    "yt-dlp",
                    "--js-runtimes",
                    "deno",
                    "--add-headers",
                    "User-Agent:Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/157.0.0.0 Safari/537.36",
                    "--limit-rate",
                    "500K",
                    "--skip-download",
                    "--no-warnings",
                    "-o",
                    "%(title)s",
                    "--print-json",
                    video_id,
                ],
                capture_output=True,
                text=True,
            )

            video_info = json.loads(yt_dlp_output.stdout)
            title = video_info["filename"]
            channel = video_info["channel"]

        print(f"{username}\t{message}\t{title}\t{channel}")
