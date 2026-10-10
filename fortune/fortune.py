import random
import re
import signal
import subprocess
import sys
import time
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
blacklisted_names = ""

# Alternatively, a whitelist:
whitelisted_names = ""


with open(fortune_file, "r") as file:
    fortunes = file.readlines()

piper_server = "http://localhost:5000/synthesize"
announcer_process = None
rate_limiting = {}

previous_line = None

re_command = re.compile(r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :  !fortune")
re_blacklisted_names = re.compile(
    rf"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?({blacklisted_names or '$^'}) :  !"
)
re_whitelisted_names = re.compile(
    rf"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?({whitelisted_names or '.*'}) :  !"
)


def speak_text(text):
    global announcer_process

    if not text:
        return

    with tempfile.NamedTemporaryFile(
        prefix="piper_voice-", suffix=".wav", delete=False
    ) as tmp:
        audio_file = tmp.name

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
        announcer_process = None
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
        # Remove messages from blacklisted players
        if re_blacklisted_names.search(line):
            continue
        # Keep messages only from whitelisted players
        if not re_whitelisted_names.search(line):
            continue
        # Remove duplicate messages
        # if line == previous_line:
        #    continue
        # previous_line = line

        # Skip the current announcement if there is one playing already
        if announcer_process and announcer_process.poll() is None:
            continue

        # Extract usernames
        matched_command = re_command.match(line)
        username = matched_command.group(3)

        current_time = int(time.time())

        if username in rate_limiting and (
            current_time - rate_limiting[username] <= rate_limit
        ):
            continue

        rate_limiting[username] = current_time

        selected_fortune = random.choice(fortunes).strip()

        Thread(
            target=speak_text,
            args=(selected_fortune,),
            daemon=True,
        ).start()
