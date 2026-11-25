#!/usr/bin/env python3

import random
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


# Notification sounds directory
sound_dir = script_dir / "sounds"

# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log = script_dir / "console.log"

# User blacklist:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
blacklisted_users = ""

# Alternatively, a whitelist:
whitelisted_users = ""

# Word whitelist:
# Example: "your_username|help|afk"
whitelisted_words = ""


player_process = None
previous_line = None

re_line = re.compile(r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.+)?")
re_blacklisted_users = re.compile(rf"{blacklisted_users or '$^'}")
re_whitelisted_users = re.compile(rf"{whitelisted_users or '.*'}")
re_whitelisted_words = re.compile(rf"{whitelisted_words or '.*'}", re.IGNORECASE)


with open(console_log, "r", encoding="utf-8", errors="ignore") as log:
    # Jump to the end of the file
    log.seek(0, 2)

    # Continuously read the last line of the log as it is updated
    while True:
        line = log.readline()
        if not line:
            time.sleep(0.1)
            continue

        # Skip the incoming notification if there is one playing already
        if player_process and player_process.poll() is None:
            continue

        # Remove the trailing newline
        line = line.rstrip("\n")

        # Search for lines containing a message
        matched_line = re_line.match(line)
        if not matched_line:
            continue

        # Extract the username and the message
        username = matched_line.group(3)
        message = matched_line.group(4)

        # Remove messages from blacklisted players
        if re_blacklisted_users.search(username):
            continue

        # Keep messages only from whitelisted players
        if not re_whitelisted_users.search(username):
            continue

        # Remove duplicate messages
        # if line == previous_line:
        #    continue
        # previous_line = line

        # Keep messages only with whitelisted words
        if not re_whitelisted_words.search(message):
            continue

        matched_files = list(sound_dir.glob("*.*"))

        if matched_files:
            selected_file = str(random.choice(matched_files))

            player_process = subprocess.Popen(
                ["paplay", "--client-name=chat-notification", selected_file],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
