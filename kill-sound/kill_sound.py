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


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


# Target list:
user_directories = {
    # Example: "John": "john",
    # Example: "pablo.gonzales.2007": "pablo",
    # Example: "Engineer Gaming": "engineer gaming",
}

# Kill sounds directory
sound_dir = script_dir / "sounds"

# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log = script_dir / "console.log"


for username in user_directories:
    Path(sound_dir / user_directories[username]).mkdir(parents=True, exist_ok=True)

re_line = re.compile(r"^((.+) (suicided|died)|.+ killed (.+) with .+)\.( \(crit\))?$")


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

        # Search for lines containing the command
        matched_line = re_line.match(line)
        if not matched_line:
            continue

        # Extract usernames
        username = matched_line.group(2) or matched_line.group(4)

        matched_files = list(
            Path(sound_dir / user_directories[username]).glob("*.*")
        ) + list(Path(sound_dir / user_directories[username]).glob("* [0-9]*.*"))

        if matched_files:
            selected_file = str(random.choice(matched_files))

            Thread(
                target=play_sound,
                args=(selected_file,),
                daemon=True,
            ).start()
