import random
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


voices = ["PAUL", "HARRY", "FRANK", "DENNIS", "BETTY", "URSULA", "RITA"]

def speak_text(text):
    if not text:
        return

    with tempfile.NamedTemporaryFile(prefix="dectalk_voice-", suffix=".wav", delete=False) as tmp:
        audio_file = tmp.name

    try:
        #subprocess.run(["say", "-pre", "[:phoneme on]", "-e", "1", "-a", text, "-fo", audio_file])
        subprocess.run(["say", "-pre", f"[:name {random.choice(voices)}][:phoneme on]", "-e", "1",
                        "-a", text, "-fo", audio_file])

        subprocess.run(
            ["paplay", "--client-name=dectalk", audio_file],
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
