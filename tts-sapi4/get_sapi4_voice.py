import random
import signal
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


sapi4_server="http://127.0.0.1:5491"

voices=[
    "Adult Female #1, American English (TruVoice)",
    "Adult Female #2, American English (TruVoice)",
    "Adult Male #1, American English (TruVoice)",
    "Adult Male #2, American English (TruVoice)",
    "Adult Male #3, American English (TruVoice)",
    "Mary",
    "Mike",
    "Sam",
]

def speak_text(text):
    if not text:
        return

    with tempfile.NamedTemporaryFile(prefix="sapi4_voice-", suffix=".wav", delete=False) as tmp:
        audio_file = tmp.name

    try:
        # BonziBUDDY voice
        #voice = "Adult Male #2, American English (TruVoice)"
        #pitch = "140"
        #speed = "157"

        # Microsoft Sam voice
        #voice = "Sam"
        #pitch = "100"
        #speed = "150"

        # A random voice (with a random pitch and speed) from the 'voices' list
        voice = random.choice(voices)

        match voice:
            case "Mary":
                min_pitch = 90
            case "Mike":
                min_pitch = 60
            case _:
                min_pitch = 50

        pitch = (random.randint(0, 15) * 10) + min_pitch
        speed = (random.randint(0, 5) * 10) + 130


        params = {
           "text": text,
           "voice": voice,
           "pitch": pitch,
           "speed": speed,
        }

        query_string = urllib.parse.urlencode(params, quote_via=urllib.parse.quote)
        full_url = f"{sapi4_server}/SAPI4/SAPI4?{query_string}"

        with urllib.request.urlopen(full_url) as response:
            response_content = response.read()

        Path(audio_file).write_bytes(response_content)

        subprocess.run(
            ["paplay", "--client-name=sapi4", audio_file],
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
        print(f"  {sys.argv[0]} \"Your text here\"     # Speak a single line")
        sys.exit(1)
