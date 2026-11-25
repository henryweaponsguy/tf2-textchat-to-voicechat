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


# Download voices by running: python3 -m piper.download_voices --data-dir "models/" <model name, e.g. en_US-joe-medium>
# Or download them here: https://rhasspy.github.io/piper-samples
voices = [
    "en_GB-alan-medium",
    "en_GB-alba-medium",
    "en_GB-northern_english_male-medium",
    "en_US-amy-medium",
    "en_US-hfc_female-medium",
    "en_US-hfc_male-medium",
    # Lower quality voices:
    "en_GB-aru-medium",  # multi speaker
    "en_GB-semaine-medium",  # multi speaker
    "en_US-joe-medium",
    "en_US-lessac-high",  # female
]

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


username_voices_file = script_dir / "username_voices.txt"

username_voices_file.touch()

sound_dir = script_dir / "sounds"
piper_server = "http://127.0.0.1:5000/synthesize"
previous_line = None

re_line = re.compile(r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.+)")
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

        if not message:
            continue

        # Convert the message to lowercase
        sound_file = message.lower()

        # Trim and normalize whitespace
        sound_file = " ".join(sound_file.split())

        matched_files = list(Path(sound_dir).glob(f"{sound_file}.*")) + list(
            Path(sound_dir).glob(f"{sound_file} [0-9]*.*")
        )

        # Skip the message if a soundboard sound exists
        if matched_files:
            continue

        with tempfile.NamedTemporaryFile(
            prefix="piper_voice-", suffix=".wav", delete=False
        ) as file:
            audio_file = file.name

        try:
            username_voices = username_voices_file.read_text().splitlines()
            if not any(
                username_voice.split("\t")[0] == username
                for username_voice in username_voices
            ):
                # A random voice (with a random speed) from the 'voices' array
                voice = random.choice(voices)

                length_scale = round(0.7 + (random.randint(0, 7) * 0.1), 1)

                # Some models support multiple voices
                speakers = ""
                speaker = ""
                if voice == "en_GB-aru-medium":
                    speakers = [
                        "03",  # female
                        "04",  # female
                        "07",  # female
                        "08",  # female
                        "10",  # male
                    ]
                elif voice == "en_GB-semaine-medium":
                    speakers = [
                        "poppy",  # female
                        "prudence",
                        "spike",  # male
                    ]

                if speakers:
                    speaker = random.choice(speakers)

                with username_voices_file.open("a") as file:
                    file.write(
                        f"{username}\t{voice}\t{length_scale}\t{speaker or ''}\n"
                    )
            else:
                username_voice = next(
                    (
                        fields
                        for fields in username_voices
                        if fields.split("\t")[0] == username
                    ),
                    None,
                )

                username, voice, length_scale, speaker = username_voice.split("\t")

            data = {"text": message, "voice": voice, "length_scale": length_scale}

            if speaker:
                data["speaker"] = speaker

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
                # ["paplay", "--device=virtual_speaker", "--client-name=piper", audio_file],
                ["paplay", "--client-name=piper", audio_file],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        finally:
            try:
                Path(audio_file).unlink()
            except FileNotFoundError:
                pass
