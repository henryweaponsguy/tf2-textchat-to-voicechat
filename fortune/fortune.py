#!/usr/bin/env python3

import random
import re
import signal
import sys
import tempfile
import time
from pathlib import Path

script_dir = Path(__file__).resolve().parent


def exit_cleanup(signum, frame):
    open(text_message_file, "w").close()

    sys.exit(0)


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, exit_cleanup)
signal.signal(signal.SIGTERM, exit_cleanup)


# Minimum time between messages (in seconds)
rate_limit = 5

# Fortune list file
fortune_file = script_dir / "fortunes.txt"

# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log = script_dir / "console.log"

# Location of the file storing generated text chat messages.
# This file should be in the same directory as TF2's autoexec.cfg
text_message_file = script_dir / "message.cfg"

# User blacklist:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
blacklisted_users = ""

# Alternatively, a whitelist:
whitelisted_users = ""


open(text_message_file, "w").close()

last_text_message_time = None

re_line = re.compile(r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.+)")
re_command = re.compile(r"^((?i:!fortune))")
re_text_message_signal = re.compile(r"^\[ ?FORTUNE\]")
re_blacklisted_users = re.compile(rf"{blacklisted_users or '$^'}")
re_whitelisted_users = re.compile(rf"{whitelisted_users or '.*'}")


def send_text_message(text):
    global last_text_message_time

    text_message = " ".join(text.split())[:127]

    with open(text_message_file, "w") as file:
        file.write(f'say "{text_message}"\n')

    last_text_message_time = time.time()


def clear_text_message():
    global last_text_message_time

    open(text_message_file, "w").close()
    last_text_message_time = None


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

        # Extract the username and the message
        username = matched_line.group(3)
        message = matched_line.group(4)

        # Remove messages from blacklisted players
        if re_blacklisted_users.search(username):
            continue

        # Keep messages only from whitelisted players
        if not re_whitelisted_users.search(username):
            continue

        # Clear the old text message
        if re_text_message_signal.search(message) or (
            last_text_message_time and (time.time() - last_text_message_time > 5)
        ):
            clear_text_message()
            continue

        # Search for messages containing a command
        matched_command = re_command.match(message)
        if not matched_command:
            continue

        # Apply rate limiting
        if last_text_message_time and (time.time() - last_text_message_time <= rate_limit):
            continue

        with open(fortune_file, "r") as file:
            fortunes = file.readlines()

        selected_fortune = random.choice(
            [fortune.strip() for fortune in fortunes if fortune.strip()]
        )

        send_text_message(f"[FORTUNE] {selected_fortune}")
