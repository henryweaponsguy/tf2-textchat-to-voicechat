#!/usr/bin/env python3

import random
import re
import signal
import subprocess
import sys
import time
from pathlib import Path
from threading import Thread

script_dir = Path(__file__).resolve().parent


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


# Minimum time between messages (in seconds)
rate_limit = 0

# Soundboard sounds directory
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

# Word blacklist:
# Example: "nominate|rtv|nextmap"
blacklisted_words = ""


rate_limiting = {}
previous_line = None

re_line = re.compile(r"^(\*DEAD\*|\*SPEC\* )?(\(TEAM\) )?(.+):  *(.+)")
re_blacklisted_users = re.compile(rf"{blacklisted_users or '$^'}")
re_whitelisted_users = re.compile(rf"{whitelisted_users or '.*'}")
re_blacklisted_words = re.compile(rf"{blacklisted_words or '$^'}", re.IGNORECASE)
re_allowed_characters = re.compile(r"[^A-Za-z0-9\s!@#$%^&*()\-_=+[\]{};:'\",.<>/?\\|`~]")


def play_sound(sound):
    subprocess.run(
        ["paplay", "--device=virtual_speaker", "--client-name=soundboard", sound],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
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

        # Search for lines containing a message
        matched_line = re_line.match(line)
        if not matched_line:
            continue

        # Extract usernames and messages
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

        # Remove messages with blacklisted words
        if re_blacklisted_words.search(message):
            continue

        # Remove non-ASCII and control characters
        message = re_allowed_characters.sub("", message)

        # Convert the message to lowercase
        message = message.lower()

        # Trim and normalize whitespace
        message = " ".join(message.split())

        matched_files = list(Path(sound_dir).glob(f"{message}.*")) + list(
            Path(sound_dir).glob(f"{message} [0-9]*.*")
        )

        if not matched_files:
            continue

        # Apply rate limiting
        current_time = time.time()

        if username in rate_limiting and (
            current_time - rate_limiting[username] <= rate_limit
        ):
            continue

        rate_limiting[username] = current_time

        selected_file = str(random.choice(matched_files))

        Thread(
            target=play_sound,
            args=(selected_file,),
            daemon=True,
        ).start()
