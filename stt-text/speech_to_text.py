import json
import queue
import random
import re
import signal
import subprocess
import sys
import time
from pathlib import Path
from threading import Thread

import sounddevice as sd
from vosk import KaldiRecognizer, Model

script_dir = Path(__file__).resolve().parent


def exit_cleanup(signum, frame):
    # Clear the old text message
    open(text_message_file, "w").close()

    sys.exit(0)


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, exit_cleanup)
signal.signal(signal.SIGTERM, exit_cleanup)



if len(sys.argv) > 1:
    if sys.argv[1] == "-h":
        print("Usage:")
        print(f"python3 {sys.argv[0]} -h                    # Show this message")
        print(
            f"python3 {sys.argv[0]}                       # Use the default input device"
        )
        print(
            f"python3 {sys.argv[0]} <audio device id>     # Use a specific input device"
        )

        print("Audio device list:")
        print(sd.query_devices())

        sys.exit(0)
    else:
        audio_device = int(sys.argv[1])
else:
    audio_device = None

device_info = sd.query_devices(audio_device, "input")
sample_rate = int(device_info["default_samplerate"])

# Download the speech recognition model here: https://alphacephei.com/vosk/models and extract the archive to 'models/'.
# The 'vosk-model-small-en-us-*' model works the best for fast speech recognition and requires around 0.5 GB of RAM.
# The 'vosk-model-en-us-*-gigaspeech' model is more accurate, but somewhat slower and requires 6+ GB of RAM.
model = Model(str(script_dir / "models" / "vosk-model-en-us-gigaspeech"))
# model = Model(str(script_dir / "models" / "vosk-model-small-en-us"))

# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log = script_dir / "console.log"

# Location of the file for storing generated text chat messages
text_message_file = script_dir / "message.cfg"


open(text_message_file, "w").close()

audio_queue = queue.Queue()
message_queue = queue.Queue()

re_message_sent_signal = re.compile(r"^text_message_sent ?$")
re_allowed_characters = re.compile(r"[^A-Za-z0-9\s!@#$%^&*()\-=+[\]{};:'\",.<>/?\\|`~]")

replacements = [
    (re.compile(r"\""), "'"),
    (re.compile(r"btw", re.IGNORECASE), "by the way"),
    (re.compile(r"wtf", re.IGNORECASE), "what the fuck"),
    (re.compile(r"idk", re.IGNORECASE), "i don't know"),
]


def replace_patterns(text):
    for pattern, replacement in replacements:
        text = pattern.sub(replacement, text)

    return text


def callback(input_data, frames, time, status):
    # Push audio chunks from input stream into the queue for further processing
    if status:
        print(status, file=sys.stderr)
    audio_queue.put(bytes(input_data))


def watch_console_log():
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
            # Search for lines containing the text-message-sent signal
            if re_message_sent_signal.search(line):
                if not message_queue.empty():
                    with open(text_message_file, "w") as file:
                        file.write(f"say \"{message_queue.get()}\";echo \"text_message_sent\"\n")
                else:
                    # Clear the old text message
                    open(text_message_file, "w").close()


# Watch the console log in the background
Thread(
    target=watch_console_log,
    daemon=True,
).start()


with sd.RawInputStream(
    samplerate=sample_rate,
    blocksize=8000,
    device=audio_device,
    dtype="int16",
    channels=1,
    callback=callback,
):

    rec = KaldiRecognizer(model, sample_rate)

    print("Listening...")

    while True:
        data = audio_queue.get()
        if rec.AcceptWaveform(data):
            result = json.loads(rec.Result())
            # Extract the message
            line = result.get("text", "")
            # Replace certain patterns
            line = replace_patterns(line)
            # Keep only letters, digits and spaces
            line = re_allowed_characters.sub("", line)
            # Skip empty messages
            if not line:
                continue

            max_length = 127

            while len(line) > max_length:
                last_space = line.rfind(" ", 0, max_length + 1)

                if last_space == -1:
                    last_space = max_length

                message_queue.put(line[:last_space])
                line = line[last_space:].lstrip()

            if line:
                message_queue.put(line)

            if message_queue.empty():
                with open(text_message_file, "w") as file:
                    file.write(f"say \"{message_queue.get()}\";echo \"text_message_sent\"\n")
