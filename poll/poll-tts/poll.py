#!/usr/bin/env python3

import json
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


# Required votes for the poll to close automatically
required_vote_count = 24

# The time after which the poll closes
time_limit = 30

# Poll sounds directory
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

# Whitelist for starting a poll:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
whitelisted_poll_users = ""


piper_server = "http://127.0.0.1:5000/synthesize"
poll_thread = None
poll_open = False
vote_list = {}

re_line = re.compile(r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.+)")
re_command = re.compile(r"^((?i:!poll|yes|no)) *(.+)?")
re_vote=re.compile(r"^yes|no$")
re_blacklisted_users = re.compile(rf"{blacklisted_users or '$^'}")
re_whitelisted_users = re.compile(rf"{whitelisted_users or '.*'}")
re_whitelisted_poll_users = re.compile(rf"{whitelisted_poll_users or '.*'}")
re_blacklisted_words = re.compile(rf"{blacklisted_words or '$^'}", re.IGNORECASE)
re_repetition = re.compile(r"(.{2,})\1{5,}")
re_allowed_characters = re.compile(r"[^A-Za-z0-9\s!@#$%^&*()\-_=+[\]{};:'\",.<>/?\\|`~]")

replacements = [
    (re.compile(r"btw", re.IGNORECASE), "by the way"),
    (re.compile(r"wtf", re.IGNORECASE), "what the fuck"),
    (re.compile(r"idk", re.IGNORECASE), "i don't know"),
]


def play_sound(sound):
    subprocess.run(
        [
            "paplay",
            "--device=virtual_speaker",
            "--client-name=poll",
            str(sound_dir / f"{sound}.wav"),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def speak_text(text):
    if not text:
        return

    with tempfile.NamedTemporaryFile(
        prefix="piper_voice-", suffix=".wav", delete=False
    ) as file:
        audio_file = file.name

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
        Path(audio_file).unlink(missing_ok=True)


def start_poll(question):
    global poll_open

    play_sound("start")
    speak_text(f"A poll has started: {question}")

    poll_open = True

    start_time = time.time()
    while time.time() - start_time < time_limit:
        time.sleep(1)

        if len(vote_list) >= required_vote_count:
            break

    poll_open = False

    yes_count = sum(vote == "yes" for vote in vote_list.values())
    total_count = len(vote_list)

    suffix = ""
    if total_count > 1:
        suffix = "s"

    if total_count == 0:
        play_sound("failure")
        speak_text("The poll has ended: nobody has voted.")
    elif yes_count * 2 > total_count:
        play_sound("success")
        speak_text(f"The poll has ended: the majority has voted 'yes' ({yes_count} out of {total_count} vote{suffix}).")
    elif yes_count * 2 == total_count:
        play_sound("failure")
        speak_text(f"The poll has ended in a draw ({yes_count} out of {total_count} vote{suffix}).")
    else:
        play_sound("failure")
        speak_text(f"The poll has ended: the majority has voted 'no' ({yes_count} out of {total_count} vote{suffix}).")

    vote_list.clear()


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

        # Remove messages with blacklisted words
        if re_blacklisted_words.search(message):
            continue

        # Search for messages containing a command
        matched_command = re_command.match(message)
        if not matched_command:
            continue

        # Extract the command and its argument
        command_name = matched_command.group(1).lower()
        command_text = matched_command.group(2)
        matched_vote = re_vote.match(command_name)

        if command_name == "!poll" and re_whitelisted_poll_users.search(line):
            # Check if the poll is running
            if poll_thread is None or not poll_thread.is_alive():
                # Replace certain patterns
                for pattern, replacement in replacements:
                    command_text = pattern.sub(replacement, command_text)

                # Remove messages with excessive repetition
                if re_repetition.search(command_text):
                    continue

                # Remove non-ASCII and control characters
                command_text = re_allowed_characters.sub("", command_text)

                # Trim and normalize whitespace
                command_text = " ".join(command_text.split())

                if not command_text:
                    continue

                poll_thread = Thread(
                    target=start_poll, args=(command_text,), daemon=True
                )
                poll_thread.start()
        elif matched_vote:
            vote = matched_vote.group(0)

            # Check if the poll is open
            if poll_thread is not None and poll_thread.is_alive() and poll_open:
                # Check if the user has not voted yet
                if username not in vote_list:
                    vote_list[username] = command_name
                    Thread(
                        target=play_sound,
                        args=(command_name,),
                        daemon=True,
                    ).start()
