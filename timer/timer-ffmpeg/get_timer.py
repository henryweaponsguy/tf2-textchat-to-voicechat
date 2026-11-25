#!/usr/bin/env python3

import re
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

script_dir = Path(__file__).resolve().parent


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


# The audio files need to have the same parameters (channel count, codec, sample rate),
# otherwise the output audio will come out corrupted
sound_dir = script_dir / "sounds"


word_list = []

re_numbers = re.compile(rf"^[0-9]+$")


def start_timer(duration):
    if not re_numbers.match(duration):
        return

    duration = int(duration)

    if not (0 < duration < 3600):
        return

    with tempfile.NamedTemporaryFile(
        prefix="timer_voice-", suffix=".wav", delete=False
    ) as tmp:
        audio_file = tmp.name

    with tempfile.NamedTemporaryFile(
        prefix="timer_word_list-", suffix=".txt", delete=False
    ) as file:
        word_list_file = file.name

    word_list.clear()

    try:
        word_list.append(f"file '{sound_dir}/intro.wav'")

        word_list.append("\n".join([f"{sound_dir}/loop.wav"] * duration))

        word_list.append(f"file '{sound_dir}/spin.wav'")
        word_list.append(f"file '{sound_dir}/explode.wav'")

        with open(word_list_file, "w") as file:
            file.writelines(f"{line}\n" for line in word_list)

        subprocess.run(
            [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                "-f",
                "concat",
                "-safe",
                "0",
                "-i",
                str(word_list_file),
                "-c",
                "copy",
                "-y",
                audio_file,
            ]
        )

        subprocess.run(
            ["paplay", "--device=virtual_speaker", "--client-name=timer", audio_file],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    finally:
        try:
            Path(audio_file).unlink(missing_ok=True)
            Path(word_list_file).unlink(missing_ok=True)
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    if len(sys.argv) > 1:
        start_timer(sys.argv[1])
    else:
        print("Usage:")
        print(f'  {sys.argv[0]} "<duration>"     # Start a timer')
        sys.exit(1)
