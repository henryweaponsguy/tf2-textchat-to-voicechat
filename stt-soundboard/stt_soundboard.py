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

# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


# Soundboard sounds directory
sound_dir=f"{script_dir}/sounds"


if len(sys.argv) > 1:
    if sys.argv[1] == "-h":
        print("Usage:")
        print(f"python3 {sys.argv[0]} -h                    # Show this message")
        print(f"python3 {sys.argv[0]}                       # Use the default input device")
        print(f"python3 {sys.argv[0]} <audio device id>     # Use a specific input device")

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
model = Model(f"{script_dir}/models/vosk-model-en-us-gigaspeech")
#model = Model(f"{script_dir}/models/vosk-model-small-en-us")

audio_queue = queue.Queue()

re_allowed_characters = re.compile(r"[^A-Za-z0-9\s]")

def callback(input_data, frames, time, status):
    # Push audio chunks from input stream into the queue for further processing
    if status:
        print(status, file=sys.stderr)
    audio_queue.put(bytes(input_data))

def play_sound(sound):
    subprocess.run(
        ["paplay", "--client-name=soundboard", sound],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


with sd.RawInputStream(samplerate=sample_rate, blocksize=8000, device=audio_device,
        dtype="int16", channels=1, callback=callback):
    rec = KaldiRecognizer(model, sample_rate)

    print("Listening...")
    while True:
        data = audio_queue.get()
        if rec.AcceptWaveform(data):
            result = json.loads(rec.Result())
            # Extract the message
            line = result.get("text", "")
            # Keep only letters, digits and spaces
            line = re_allowed_characters.sub("", line)
            # Skip empty messages
            if not line:
                continue

            # Match files
            matched_files = (
                list(Path(sound_dir).glob(f"{line}.*")) +
                list(Path(sound_dir).glob(f"{line} [0-9]*.*"))
            )

            if matched_files:
                selected_file = str(random.choice(matched_files))

                Thread(
                    target=play_sound,
                    args=(selected_file,),
                    daemon=True,
                ).start()

