#!/usr/bin/env python3

import json
import random
import re
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path
from threading import Thread

script_dir = Path(__file__).resolve().parent


def exit_cleanup(signum, frame):
    for file in Path(tempfile.gettempdir()).glob("piper_voice-*.wav"):
        try:
            file.unlink()
        except FileNotFoundError:
            pass

    sys.exit(0)


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, exit_cleanup)
signal.signal(signal.SIGTERM, exit_cleanup)


# Minimum time between messages (in seconds)
rate_limit = 0

# Fortune list file
fortune_file = script_dir / "fortunes.txt"

# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log = script_dir / "console.log"

# User blacklist:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
blacklisted_users = ""

# Alternatively, a whitelist:
whitelisted_users = ""


piper_server = "http://127.0.0.1:5000/synthesize"
announcer_process = None
rate_limiting = {}

re_line = re.compile(r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.+)")
re_command = re.compile(r"^((?i:!fortune))")
re_blacklisted_users = re.compile(rf"{blacklisted_users or '$^'}")
re_whitelisted_users = re.compile(rf"{whitelisted_users or '.*'}")


def speak_text(text):
    global announcer_process

    if not text:
        return

    with tempfile.NamedTemporaryFile(
        prefix="piper_voice-", suffix=".wav", delete=False
    ) as file:
        audio_file = file.name

    try:
        data = {"text": text, "voice": "en_US-joe-medium", "length_scale": 1}

        post_request = urllib.request.Request(
            piper_server,
            data=json.dumps(data).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        with urllib.request.urlopen(post_request) as response, open(
            audio_file, "wb"
        ) as file:
            file.write(response.read())

        announcer_process = subprocess.Popen(
            [
                "paplay",
                "--device=virtual_speaker",
                "--client-name=piper",
                audio_file,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        announcer_process.wait()
    finally:
        Path(audio_file).unlink(missing_ok=True)


with open(console_log, "r", encoding="utf-8", errors="ignore") as log:
    # Jump to the end of the file
    log.seek(0, 2)

    # Continuously read the last line of the log as it is updated
    while True:
        line = log.readline()
        if not line:
            time.sleep(0.1)
            continue

        # Skip the incoming announcement if there is one playing already
        if announcer_process and announcer_process.poll() is None:
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

        # Search for messages containing a command
        matched_command = re_command.match(message)
        if not matched_command:
            continue

        current_time = int(time.time())

        if username in rate_limiting and (
            current_time - rate_limiting[username] <= rate_limit
        ):
            continue

        rate_limiting[username] = current_time

        with open(fortune_file, "r") as file:
            fortunes = file.readlines()

        selected_fortune = random.choice(
            [fortune.strip() for fortune in fortunes if fortune.strip()]
        )

        Thread(
            target=speak_text,
            args=(selected_fortune,),
            daemon=True,
        ).start()
