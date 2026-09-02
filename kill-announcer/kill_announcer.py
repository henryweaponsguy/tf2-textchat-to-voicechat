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
kill_messages = {
    # Example: "John": ["John is gone!", "John died. Shit happens."],
    # Example: "pablo.gonzales.2007": ["pablo is down!", "pablo got owned!"],
    # Example: "Engineer Gaming": ["the grease monkey bites the dust!"],
}

piper_server = "http://localhost:5000/synthesize"


# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log = script_dir / "console.log"


re_command = re.compile(
    r"^((.+) (suicided|died)|.+ killed (.+) with .+)\.( \(crit\))?$"
)


def speak_text(text):
    if not text:
        return

    with tempfile.NamedTemporaryFile(
        prefix="piper_voice-", suffix=".wav", delete=False
    ) as tmp:
        audio_file = tmp.name

    try:
        data = {"text": text, "voice": "en_US-joe-medium", "length_scale": "1"}

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

        subprocess.run(
            [
                "paplay",
                "--device=virtual_speaker",
                "--client-name=piper",
                audio_file,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    finally:
        try:
            Path(audio_file).unlink()
        except FileNotFoundError:
            pass


with open(console_log, "r") as log:
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
        if not re_command.search(line):
            continue

        # Extract the username
        matched_command = re_command.match(line)
        username = matched_command.group(2) or matched_command.group(4)

        if username in kill_messages:
            kill_message = random.choice(kill_messages[username])

            Thread(
                target=speak_text,
                args=(kill_message,),
                daemon=True,
            ).start()
