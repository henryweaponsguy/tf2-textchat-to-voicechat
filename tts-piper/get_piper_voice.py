import json
import random
import signal
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


piper_server = "http://localhost:5000"

# Download voices by running: python3 -m piper.download_voices --data-dir "models/" <model name, e.g. en_US-alan-medium>
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


def speak_text(text):
    if not text:
        return

    with tempfile.NamedTemporaryFile(
        prefix="piper_voice-", suffix=".wav", delete=False
    ) as tmp:
        audio_file = tmp.name

    try:
        # Default voice
        # voice="en_GB-alan-medium"
        # length_scale=1

        # A random voice (with a random speed) from the 'voices' array
        voice = random.choice(voices)

        length_scale = round(0.7 + (random.randint(0, 7) * 0.1), 1)

        # Some models support multiple voices
        speakers = ""
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

        data = {"text": text, "voice": voice, "length_scale": length_scale}

        if speakers:
            data["speaker"] = random.choice(speakers)

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
            ["paplay", "--device=virtual_speaker", "--client-name=piper", audio_file],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    finally:
        try:
            Path(audio_file).unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    if len(sys.argv) > 1:
        speak_text(sys.argv[1])
    else:
        print("Usage:")
        print(f'  {sys.argv[0]} "Your text here"     # Speak a single line')
        sys.exit(1)
