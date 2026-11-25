#!/usr/bin/env python3

import re
import signal
import sys
import tempfile
import time
from pathlib import Path
from threading import Thread

from get_sapi4_voice import speak_text

script_dir = Path(__file__).resolve().parent


def exit_cleanup(signum, frame):
    for file in Path(tempfile.gettempdir()).glob("sapi4_voice-*.wav"):
        try:
            file.unlink()
        except FileNotFoundError:
            pass

    sys.exit(0)


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, exit_cleanup)
signal.signal(signal.SIGTERM, exit_cleanup)


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


previous_line = None

re_line = re.compile(r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(?i:!tts) +(.+)")
# re_line = re.compile(r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.+)")
re_blacklisted_users = re.compile(rf"{blacklisted_users or '$^'}")
re_whitelisted_users = re.compile(rf"{whitelisted_users or '.*'}")
re_blacklisted_words = re.compile(rf"{blacklisted_words or '$^'}", re.IGNORECASE)
re_repetition = re.compile(r"(.{2,})\1{5,}")
re_allowed_characters = re.compile(r"[^A-Za-z0-9\s!@#$%^&*()\-_=+[\]{};:'\",.<>/?\\|`~]")

replacements = [
    (re.compile(r"btw", re.IGNORECASE), "by the way"),
    (re.compile(r"wtf", re.IGNORECASE), "what the fuck"),
    (re.compile(r"idk", re.IGNORECASE), "i don't know"),
]


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

        # Remove messages with blacklisted words
        if re_blacklisted_words.search(message):
            continue

        # Replace certain patterns
        for pattern, replacement in replacements:
            message = pattern.sub(replacement, message)

        # Remove messages with excessive repetition
        if re_repetition.search(message):
            continue

        # Remove non-ASCII and control characters
        message = re_allowed_characters.sub("", message)

        # Trim and normalize whitespace
        message = " ".join(message.split())

        if not message:
            continue

        Thread(
            target=speak_text,
            args=(message,),
            daemon=True,
        ).start()
