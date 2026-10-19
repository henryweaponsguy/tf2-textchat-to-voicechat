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


sound_dir = script_dir / "sounds"


timer_running_state_file = Path(tempfile.gettempdir()) / "timer.running"

word_list_file = script_dir / "word_list.txt"

if not word_list_file.exists():
    word_list_file.touch()

word_list = []

re_numbers = re.compile(rf"^[0-9]+$")


def start_timer(duration):
    if timer_running_state_file.exists():
        return

    timer_running_state_file.touch()

    if not re_numbers.match(duration):
        return

    duration = int(duration)

    if not (0 < duration < 3600):
        return

    with tempfile.NamedTemporaryFile(
        prefix="timer_voice-", suffix=".wav", delete=False
    ) as tmp:
        audio_file = tmp.name

    try:
        word_list.append(f"file '{sound_dir}/intro.wav'")

        for i in range(duration):
            word_list.append(f"file '{sound_dir}/loop.wav'")

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
                "-ar",
                "22050",
                "-ac",
                "1",
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

        word_list.clear()
    finally:
        try:
            Path(audio_file).unlink()
            word_list_file.unlink()
            timer_running_state_file.unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    if len(sys.argv) > 1:
        start_timer(sys.argv[1])
    else:
        print("Usage:")
        print(f'  {sys.argv[0]} "<duration>"     # Start a timer')
        sys.exit(1)
