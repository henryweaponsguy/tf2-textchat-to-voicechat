#!/usr/bin/env python3

import json
import re
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path
from threading import Thread

script_dir = Path(__file__).resolve().parent


def exit_cleanup(signum, frame):
    for process in [announcer_process, radio_process]:
        if process and process.poll() is None:
            process.terminate()

    for file in Path(tempfile.gettempdir()).glob("piper_voice-*.wav"):
        try:
            file.unlink()
        except FileNotFoundError:
            pass

    sys.exit(0)


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, exit_cleanup)
signal.signal(signal.SIGTERM, exit_cleanup)


# The length of the recently played list (-1 to make it infinite).
# Files in the recently played list cannot be queued again
recently_played_length = 5

# Required votes to skip the currently playing file
required_vote_count = 5

# The level of announcements:
# 2 - all announcements, 1 - disables voting announcements, 0 - no announcements
announcements_level = 2

# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log = script_dir / "console.log"

# User blacklist:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
blacklisted_users = ""

# Alternatively, a whitelist:
whitelisted_users = ""

# Word blacklist:
# Example: "dQw4w9WgXcQ|dwDns8x3Jb4|ZZ5LpwO-An4"
blacklisted_words = ""


piper_server = "http://127.0.0.1:5000/synthesize"
queue_dir = script_dir / "queue"
queue_file = queue_dir / "queue.txt"
download_queue_file = queue_dir / "download_queue.txt"
recently_played_file = queue_dir / "recently_played.txt"

queue_dir.mkdir(parents=True, exist_ok=True)

for file in [queue_dir, download_queue_file, recently_played_file]:
    file.touch()

announcer_process = None
radio_process = None
queue_thread = None
download_queue_thread = None
voting_open = False
vote_list = set()

re_line = re.compile(r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.+)")
re_command = re.compile(r"^(?i:(!queue|!skip)) *(.+)?")
re_blacklisted_users = re.compile(rf"{blacklisted_users or '$^'}")
re_whitelisted_users = re.compile(rf"{whitelisted_users or '.*'}")
re_blacklisted_words = re.compile(rf"{blacklisted_words or '$^'}", re.IGNORECASE)
re_url = re.compile(
    r"(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)([A-Za-z0-9_-]+)"
)
re_video_id = re.compile(r"\(([A-Za-z0-9_-]+)\)$")

replacements = [
    (re.compile(r"\([A-Za-z0-9_-]+\)$"), ""),
    (
        re.compile(
            r"[\[\(]( *([48]k|hd|hq|music|official|remastered|audio|video)){1,7}[\]\)] *",
            re.IGNORECASE,
        ),
        "",
    ),
]

replacements_tts = [
    (re.compile(r"[-_]"), ","),
    (re.compile(r"[^A-Za-z0-9\s'-_,\.]"), ""),
]


def speak_text(text):
    global announcer_process

    if not text:
        return

    with tempfile.NamedTemporaryFile(
        prefix="piper_voice-", suffix=".wav", delete=False
    ) as file:
        audio_file = file.name

    try:
        data = {"text": text, "voice": "en_US-joe-medium", "length_scale": 1}

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

        # Stop the previous announcement
        if announcer_process and announcer_process.poll() is None:
            announcer_process.terminate()

        announcer_process = subprocess.Popen(
            [
                "paplay",
                "--device=virtual_speaker",
                "--client-name=piper",
                audio_file,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        announcer_process.wait()
        announcer_process = None
    finally:
        Path(audio_file).unlink(missing_ok=True)


def download_file(video_id, username):
    print(f"{'Downloading:':<25}{video_id}")
    print(f"{'Queued by:':<25}{username}")

    audio_format = "opus"

    # Check if the file has been downloaded already
    matched_files = list(queue_dir.glob(f"* ({video_id}).{audio_format}"))
    if matched_files:
        audio_file = matched_files[0]
        print(f"{'Already downloaded:':<25}{audio_file.stem}")
    else:
        try:
            # Get the video's filename, title and channel
            yt_dlp_output = subprocess.run(
                [
                    "yt-dlp",
                    "--js-runtimes",
                    "deno",
                    "--add-headers",
                    "User-Agent:Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/157.0.0.0 Safari/537.36",
                    "--limit-rate",
                    "500K",
                    "--skip-download",
                    "--no-warnings",
                    "-o",
                    "%(title)s",
                    "--print-json",
                    video_id,
                ],
                capture_output=True,
                text=True,
            )

            video_info = json.loads(yt_dlp_output.stdout)
            title = video_info["filename"]
            channel = video_info["channel"]
            audio_file = queue_dir / f"{title} ({video_id}).{audio_format}"
        except json.JSONDecodeError:
            print(f"\033[31m{'yt-dlp error:':<25}{yt_dlp_output.stderr}\033[0m")
            return

        print(f"{'Title:':<25}{title}")
        print(f"{'Channel:':<25}{channel}")

        # Download the file
        subprocess.run(
            [
                "yt-dlp",
                "--js-runtimes",
                "deno",
                "--add-headers",
                "User-Agent:Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36",
                "--limit-rate",
                "500K",
                "--extract-audio",
                "--audio-format",
                audio_format,
                "--match-filter",
                "duration < 1200",
                "--output",
                f"{queue_dir}/%(title)s ({video_id}).%(ext)s",
                "--no-playlist",
                "--quiet",
                video_id,
            ]
        )

        # Check if the file has been downloaded successfully
        if not audio_file.exists():
            print(f"{'Video unavailable:':<25}{title}")
            return

        # Normalization parameters
        lufs = -23
        tolerance = -1.0
        loudness_range = 9
        target_peak = -9
        peak_tolerance = 0.3

        temp_file = audio_file.parent / f"{audio_file.name}-tmp{audio_file.suffix}"

        # Get codec, sample rate, channel count and duration
        ffprobe_output = subprocess.run(
            [
                "ffprobe",
                "-hide_banner",
                "-v",
                "error",
                "-select_streams",
                "a:0",
                "-show_entries",
                "stream=codec_name,sample_rate,channels",
                "-show_entries",
                "format=duration",
                "-of",
                "json",
                str(audio_file),
            ],
            capture_output=True,
            text=True,
        ).stdout

        file_info = json.loads(ffprobe_output)
        codec = file_info["streams"][0].get("codec_name")
        sample_rate = file_info["streams"][0].get("sample_rate")
        channels = file_info["streams"][0].get("channels")
        duration = float(file_info["format"].get("duration"))

        if codec == "opus":
            codec = "libopus"
        if codec == "vorbis":
            codec = "libvorbis"

        # LUFS normalization cannot be calculated for very short files, use peak normalization instead
        if duration < 0.4:
            # Analyze the file
            analysis_output = subprocess.run(
                [
                    "ffmpeg",
                    "-hide_banner",
                    "-loglevel",
                    "info",
                    "-i",
                    str(audio_file),
                    "-filter:a",
                    "volumedetect",
                    "-f",
                    "null",
                    "-",
                ],
                capture_output=True,
                text=True,
            ).stderr

            current_peak = float(
                re.search(r"max_volume: +(.+) +dB", analysis_output).group(1)
            )
            gain = target_peak - current_peak

            # Normalize the file
            subprocess.run(
                [
                    "ffmpeg",
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-i",
                    str(audio_file),
                    "-filter:a",
                    f"volume={gain}dB",
                    "-acodec",
                    codec,
                    "-ar",
                    str(sample_rate),
                    "-ac",
                    str(channels),
                    "-y",
                    str(temp_file),
                ]
            )

            temp_file.replace(audio_file)
        else:
            # Analyze the file
            analysis_output = subprocess.run(
                [
                    "ffmpeg",
                    "-hide_banner",
                    "-loglevel",
                    "info",
                    "-i",
                    str(audio_file),
                    "-filter:a",
                    (
                        "loudnorm="
                        f"I={lufs}:"
                        f"TP={tolerance}:"
                        f"LRA={loudness_range}:"
                        "print_format=json"
                    ),
                    "-f",
                    "null",
                    "-",
                ],
                capture_output=True,
                text=True,
            ).stderr

            file_parameters = json.loads(
                re.search(r"\{[\s\S]*\}", analysis_output).group(0)
            )
            input_i = file_parameters["input_i"]
            input_tp = file_parameters["input_tp"]
            input_lra = file_parameters["input_lra"]
            input_thresh = file_parameters["input_thresh"]

            # Skip silent files
            if input_i != "-inf":
                # Normalize the file
                subprocess.run(
                    [
                        "ffmpeg",
                        "-hide_banner",
                        "-loglevel",
                        "error",
                        "-i",
                        str(audio_file),
                        "-filter:a",
                        (
                            "loudnorm="
                            f"I={lufs}:"
                            f"TP={tolerance}:"
                            f"LRA={loudness_range}:"
                            "linear=true:"
                            f"measured_I={input_i}:"
                            f"measured_LRA={input_lra}:"
                            f"measured_tp={input_tp}:"
                            f"measured_thresh={input_thresh}"
                        ),
                        "-acodec",
                        codec,
                        "-ar",
                        str(sample_rate),
                        "-ac",
                        str(channels),
                        "-y",
                        str(temp_file),
                    ]
                )

                temp_file.replace(audio_file)

        print(f"{'Downloaded:':<25}{audio_file.stem}")

    return audio_file


def download_queue():
    while download_queue_file.exists() and download_queue_file.stat().st_size > 0:
        with open(download_queue_file, "r+") as file:
            video_id, username = file.readline().rstrip("\n").split("\t")

            rest = file.read()
            file.seek(0)
            file.write(rest)
            file.truncate()

        audio_file = download_file(video_id, username)

        # Check if the file is queued already
        queued_files = queue_file.read_text().splitlines()
        recently_played_files = recently_played_file.read_text().splitlines()

        # Check if the file has been downloaded
        if not audio_file:
            print(f"\033[32m{'Failed to download:':<25}{video_id}\033[0m")
        elif str(audio_file) in queued_files:
            print(f"\033[32m{'Already in the queue:':<25}{audio_file.stem}\033[0m")
        # Check if the file has been recently played
        elif str(audio_file) in recently_played_files:
            print(f"\033[32m{'File recently played:':<25}{audio_file.stem}\033[0m")
        else:
            # Queue the file
            with open(queue_file, "a") as file:
                file.write(f"{audio_file}\n")
            print(f"\033[32m{'Queued:':<25}{audio_file.stem}\033[0m")

            # Add the file to the recently played files list
            recently_played_files.append(str(audio_file))

            if recently_played_length == 0:
                recently_played_files = []
            elif recently_played_length > 0:
                recently_played_files = recently_played_files[-recently_played_length:]

            recently_played_file.write_text(
                "\n".join(str(path) for path in recently_played_files) + "\n"
            )


def play_queue():
    global radio_process
    global voting_open

    while queue_file.exists() and queue_file.stat().st_size > 0:
        with open(queue_file, "r+") as file:
            audio_file = Path(file.readline().rstrip("\n"))

            rest = file.read()
            file.seek(0)
            file.write(rest)
            file.truncate()

        if audio_file.exists():
            print(f"\033[33m{'Now playing:':<25}{audio_file.stem}\033[0m")

            clean_title = audio_file.stem

            video_id_match = re_video_id.search(clean_title)
            video_id = video_id_match.group(1) if video_id_match else None

            for pattern, replacement in replacements:
                clean_title = pattern.sub(replacement, clean_title)

            if announcements_level >= 1:
                announcement_title = clean_title
                for pattern, replacement in replacements_tts:
                    announcement_title = pattern.sub(replacement, announcement_title)

                speak_text(f"Now playing: {announcement_title}.")

            # Clear votes
            vote_list.clear()

            # Play the file
            voting_open = True

            radio_process = subprocess.Popen(
                [
                    "paplay",
                    "--device=virtual_speaker",
                    "--client-name=radio",
                    str(audio_file),
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            radio_process.wait()

            voting_open = False

            radio_process = None
        else:
            print(f"\033[36m{'File not found:':<25}{audio_file}\033[0m")


def skip_current():
    global radio_process

    if radio_process and radio_process.poll() is None:
        radio_process.terminate()
        radio_process = None


def start_download_queue():
    last_mtime = download_queue_file.stat().st_mtime

    while True:
        download_queue()

        while True:
            time.sleep(0.1)
            new_mtime = download_queue_file.stat().st_mtime
            if new_mtime != last_mtime:
                last_mtime = new_mtime
                break


def start_queue():
    last_mtime = queue_file.stat().st_mtime

    while True:
        play_queue()

        print(f"\033[36m{'Queue:':<25}{'No more files in the queue'}\033[0m")

        while True:
            time.sleep(0.1)
            new_mtime = queue_file.stat().st_mtime
            if new_mtime != last_mtime:
                last_mtime = new_mtime
                break


# Start the downloader in the background
download_queue_thread = Thread(
    target=start_download_queue,
    daemon=True,
)
download_queue_thread.start()

# Start the audio player in the background
queue_thread = Thread(
    target=start_queue,
    daemon=True,
)
queue_thread.start()


with open(console_log, "r", encoding="utf-8", errors="ignore") as log:
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

        # Search for lines containing a message
        matched_line = re_line.match(line)
        if not matched_line:
            continue

        # Extract the username and the message
        username = matched_line.group(3)
        message = matched_line.group(4)

        # Remove messages from blacklisted players
        if re_blacklisted_users.search(username):
            continue

        # Keep messages only from whitelisted players
        if not re_whitelisted_users.search(username):
            continue

        # Remove messages with blacklisted words
        if re_blacklisted_words.search(message):
            continue

        # Search for messages containing a command
        matched_command = re_command.match(message)
        if not matched_command:
            continue

        # Extract the command and its argument
        command_name = matched_command.group(1).lower()
        command_text = matched_command.group(2)
        matched_vote = re_vote.match(command_name)

        if command_name == "!queue" and command_text:
            # Check if the video ID is valid
            matched_video_url = re_url.match(command_text)
            if not matched_video_url:
                continue

            video_id = matched_video_url.group(4)

            with open(download_queue_file, "a") as file:
                file.write(f"{video_id}\t{username}\n")
        # Vote to skip the currently playing file
        elif command_name == "!skip" and voting_open:
            # Check if the user has not voted yet
            if username not in vote_list:
                vote_list.add(username)

                remaining_vote_count = required_vote_count - len(vote_list)

                print(
                    f"\033[34m{'Voted to skip:':<25}"
                    f"{f'{required_vote_count - remaining_vote_count}/{required_vote_count}':<10}"
                    f"{username}\033[0m"
                )

                if announcements_level == 2:
                    if remaining_vote_count > 1:
                        Thread(
                            target=speak_text,
                            args=(f"{remaining_vote_count} votes remaining.",),
                            daemon=True,
                        ).start()
                    elif remaining_vote_count == 1:
                        Thread(
                            target=speak_text,
                            args=("1 vote remaining.",),
                            daemon=True,
                        ).start()
                    # Skip the currently playing file if the required number of skip votes has been reached
                    else:
                        Thread(
                            target=speak_text,
                            args=("Skipping the file.",),
                            daemon=True,
                        ).start()

                        print(f"\033[36m{'Queue:':<25}{'Skipping the file'}\033[0m")

                        skip_current()
                elif remaining_vote_count == 0:
                    print(f"\033[36m{'Queue:':<25}{'Skipping the file'}\033[0m")

                    skip_current()
