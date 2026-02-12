import random
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


voices = ["m1", "m2", "m3", "m4", "m5", "m6", "m7", "f1", "f2", "f3", "f4"]

def speak_text(text):
    if not text:
        return

    with tempfile.NamedTemporaryFile(prefix="espeak_voice-", suffix=".wav", delete=False) as tmp:
        audio_file = tmp.name

    try:
        #subprocess.run(["espeak", "-v", "en+m5", "-w", audio_file, text])
        subprocess.run(["espeak", "-v", f"en+{random.choice(voices)}", "-w", audio_file, text])

        subprocess.run(
            ["paplay", "--client-name=espeak", audio_file],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
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
