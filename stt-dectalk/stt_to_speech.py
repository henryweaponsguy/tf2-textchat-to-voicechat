import json
import queue
import re
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from threading import Thread
import sounddevice as sd
from vosk import KaldiRecognizer, Model

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

announcer_process = None

re_allowed_characters = re.compile(r"[^A-Za-z0-9\s!@#$%^&*()\-=+[\]{};:'\",.<>/?\\|`~]")

replacements = [
    (re.compile(r"b t w", re.IGNORECASE), "by the way"),
    (re.compile(r"w t f", re.IGNORECASE), "what the fuck"),
    (re.compile(r"i d k", re.IGNORECASE), "i don't know"),
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

def speak_text(text):
    if not text:
        return

    with tempfile.NamedTemporaryFile(prefix="dectalk_voice-", suffix=".wav", delete=False) as tmp:
        audio_file = tmp.name

    try:
        subprocess.run(["say", "-pre", "[:name PAUL]", "-e", "1", "-a", text, "-fo", audio_file])

        # Stop the previous announcement
        global announcer_process
        if announcer_process and announcer_process.poll() is None:
            announcer_process.terminate()

        announcer_process = subprocess.Popen(
            ["paplay", "--client-name=dectalk", audio_file],
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
            # Replace certain patterns
            line = replace_patterns(line)
            # Keep only letters, digits and spaces
            line = re_allowed_characters.sub("", line)
            # Skip empty messages
            if not line:
                continue

            print(line) # TODO remove this

            # Stop the announcement early using a keyword
            if line == "stop" and announcer_process and announcer_process.poll() is None:
                announcer_process.terminate()
                continue

            Thread(
                target=speak_text,
                args=(line,),
                daemon=True,
            ).start()
