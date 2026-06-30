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
    for file in Path(tempfile.gettempdir()).glob("dectalk_voice-*.wav"):
        try:
            file.unlink()
        except FileNotFoundError:
            pass

    sys.exit(0)


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, exit_cleanup)
signal.signal(signal.SIGTERM, exit_cleanup)


# Poll sounds directory
sound_dir = script_dir / "sounds"

# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log = script_dir / "console.log"

# User blacklist:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
blacklisted_names = ""

# Alternatively, a whitelist:
whitelisted_names = ""

# Word blacklist:
# Example: "nominate|rtv|nextmap"
blacklisted_words = ""

# Whitelist for starting a poll:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
whitelisted_poll_names = ""


piper_server = "http://localhost:5000"
poll_thread = None
poll_open = False

vote_list = {}

re_command = re.compile(
    r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :  !(startpoll|poll) (.+)"
)
re_blacklisted_names = re.compile(
    rf"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?({blacklisted_names or '$^'}) :  !"
)
re_whitelisted_names = re.compile(
    rf"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?({whitelisted_names or '.*'}) :  !"
)
re_whitelisted_poll_names = re.compile(rf"{whitelisted_poll_names or '.*'}")
re_blacklisted_words = re.compile(rf"{blacklisted_words or '$^'}", re.IGNORECASE)
re_repetition = re.compile(r"(.{2,})\1{5,}")
re_vote = re.compile(r"^[yn][a-z0-9_-]*", re.IGNORECASE)

replacements = [
    (re.compile(r"btw", re.IGNORECASE), "by the way"),
    (re.compile(r"wtf", re.IGNORECASE), "what the fuck"),
    (re.compile(r"idk", re.IGNORECASE), "i don't know"),
]


def replace_patterns(text):
    for pattern, replacement in replacements:
        text = pattern.sub(replacement, text)

    return text


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


def start_poll(question):
    global poll_open

    required_vote_count = 24
    time_limit = 30

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
    no_count = sum(vote == "no" for vote in vote_list.values())

    if len(vote_list) == 0:
        play_sound("failure")
        speak_text("The poll has ended: nobody has voted.")
    elif yes_count > no_count:
        play_sound("success")
        speak_text("The poll has ended: the majority has voted 'yes'.")
    elif yes_count == no_count:
        play_sound("failure")
        speak_text("The poll has ended in a draw.")
    else:
        play_sound("failure")
        speak_text("The poll has ended: the majority has voted 'no'.")

    vote_list.clear()


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
        # Replace certain patterns
        line = replace_patterns(line)
        # Remove messages with blacklisted words
        if re_blacklisted_words.search(line):
            continue
        # Remove messages with excessive repetition
        if re_repetition.search(line):
            continue

        # Extract usernames, commands and command input
        matched_command = re_command.match(line)
        command_input = matched_command.group(5)

        selected_command = matched_command.group(4)
        if selected_command == "startpoll" and re_whitelisted_poll_names.search(line):
            # Check if the poll is running
            if poll_thread is None or not poll_thread.is_alive():
                poll_thread = Thread(
                    target=start_poll, args=(command_input,), daemon=True
                )
                poll_thread.start()
        elif selected_command == "poll":
            # Check if the poll is open
            if poll_thread is not None and poll_thread.is_alive() and poll_open:
                username = matched_command.group(3)

                # Check if the user has not voted yet
                if username not in vote_list:
                    if re_vote.match(command_input):
                        if command_input.lower().startswith("y"):
                            vote = "yes"
                        elif command_input.lower().startswith("n"):
                            vote = "no"

                        vote_list[username] = vote
                        Thread(
                            target=play_sound,
                            args=(vote,),
                            daemon=True,
                        ).start()
