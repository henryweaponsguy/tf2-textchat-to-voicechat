import json
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from threading import Thread

script_dir = Path(__file__).resolve().parent


def exit_cleanup(signum, frame):
    for file in [timer_running_state_file, timer_socket]:
        try:
            file.unlink()
        except FileNotFoundError:
            pass

    sys.exit(0)


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, exit_cleanup)
signal.signal(signal.SIGTERM, exit_cleanup)


sound_dir = script_dir / "sounds"
timer_running_state_file = Path(tempfile.gettempdir()) / "timer.running"
timer_socket = Path(tempfile.gettempdir()) / "timer.socket"

ffprobe_output = subprocess.run(
    [
        "ffprobe",
        "-hide_banner",
        "-v",
        "error",
        "-select_streams",
        "a:0",
        "-show_entries",
        "format=duration",
        "-of",
        "json",
        str(sound_dir / "intro.wav"),
    ],
    capture_output=True,
    text=True,
).stdout

file_info = json.loads(ffprobe_output)
intro_duration = float(file_info["format"].get("duration"))

re_numbers = re.compile(rf"^[0-9]+$")


def send_socket_command(command):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(str(timer_socket))
        s.sendall(json.dumps({"command": command}).encode("utf-8") + b"\n")
        return s.recv(4096).decode("utf-8", errors="ignore")


def start_timer(duration):
    if timer_running_state_file.exists():
        return

    timer_running_state_file.touch()

    if not re_numbers.match(duration):
        return

    duration = int(duration)

    if not (0 < duration < 3600):
        return

    mpv_process = subprocess.Popen(
        [
            "mpv",
            "--audio-device=pulse/virtual_speaker",
            "--no-video",
            "--gapless-audio=yes",
            "--idle=yes",
            "--really-quiet",
            f"--input-ipc-server={timer_socket}",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    # Wait for mpv to start
    time.sleep(0.2)

    # Play intro once
    send_socket_command(["loadfile", str(sound_dir / "intro.wav"), "replace"])

    # Queue loop to start immediately after intro
    send_socket_command(["loadfile", str(sound_dir / "loop.wav"), "append-play"])

    time.sleep(intro_duration + 0.1)

    # Enable looping
    send_socket_command(["set_property", "loop-file", "inf"])

    time.sleep(intro_duration - 1)

    # Play outro
    send_socket_command(["loadfile", str(sound_dir / "spin.wav"), "append-play"])

    send_socket_command(["loadfile", str(sound_dir / "explode.wav"), "append-play"])

    # Disable looping
    send_socket_command(["set_property", "loop-file", "no"])

    # Wait until mpv finishes playing the outro
    while True:
        if "data" not in send_socket_command(["get_property", "playback-time"]):
            break
        time.sleep(0.1)

    # Quit mpv
    send_socket_command(["quit"])

    try:
        Path(timer_running_state_file).unlink()
    except FileNotFoundError:
        pass


if __name__ == "__main__":
    if len(sys.argv) > 1:
        start_timer(sys.argv[1])
    else:
        print("Usage:")
        print(f'  {sys.argv[0]} "<duration>"     # Start a timer')
        sys.exit(1)
