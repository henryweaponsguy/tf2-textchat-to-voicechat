import json
import re
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from threading import Thread

script_dir = Path(__file__).resolve().parent


def exit_cleanup(signum, frame):
    for process in [announcer_process, radio_process]:
        if process and process.poll() is None:
            process.terminate()

    for file in Path(tempfile.gettempdir()).glob("dectalk_voice-*.wav"):
        try:
            file.unlink()
        except FileNotFoundError:
            pass

    sys.exit(0)


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, exit_cleanup)
signal.signal(signal.SIGTERM, exit_cleanup)


# Queue management files
queue_dir = script_dir / "queue"
queue_file = script_dir / "queue.txt"
recently_played_history_file = script_dir / "recently_played_history.txt"

queue_dir.mkdir(parents=True, exist_ok=True)

for file in [queue_file, recently_played_history_file]:
    if not file.exists():
        file.touch()


# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log = f"{script_dir}/console.log"

# User blacklist:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
blacklisted_names = ""

# Alternatively, a whitelist:
whitelisted_names = ""

# Word blacklist:
# Example: "dQw4w9WgXcQ|dwDns8x3Jb4|ZZ5LpwO-An4"
blacklisted_words = ""


previous_line = None

queue_thread = None
announcer_process = None
radio_process = None
skip_voting_open = False

skip_vote_list = {}

re_command = re.compile(
    r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :  !(queue|skip)( .+)?"
)
re_blacklisted_names = re.compile(
    rf"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?({blacklisted_names or '$^'}) :  !"
)
re_whitelisted_names = re.compile(
    rf"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?({whitelisted_names or '.*'}) :  !"
)
re_blacklisted_words = re.compile(rf"{blacklisted_words or '$^'}", re.IGNORECASE)
re_allowed_characters = re.compile(r"[^A-Za-z0-9\s!@#$%^&*()\-=+[\]{};:'\",.<>/?\\|`~]")
re_allowed_filename_characters = re.compile(r"[^A-Za-z0-9\s'-_]")
re_url = re.compile(
    r"(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)([A-Za-z0-9_-]+)"
)

replacements = [
    (re.compile(r"\([A-Za-z0-9_-]+\)$"), ""),
    (
        re.compile(
            r"[\[\(]( *([48]k|hd|hq|music|official|remastered|audio|video)){1,7}[\]\)] *",
            re.IGNORECASE,
        ),
        "",
    ),
    (re.compile(r"[-_]"), ","),
]


def speak_text(text):
    if not text:
        return

    with tempfile.NamedTemporaryFile(
        prefix="dectalk_voice-", suffix=".wav", delete=False
    ) as tmp:
        audio_file = tmp.name

    try:
        subprocess.run(
            ["say", "-pre", "[:name HARRY]", "-e", "1", "-a", text, "-fo", audio_file]
        )

        # Stop the previous announcement
        global announcer_process
        if announcer_process and announcer_process.poll() is None:
            announcer_process.terminate()

        announcer_process = subprocess.Popen(
            [
                "paplay",
                "--device=virtual_speaker",
                "--client-name=radio-announcer",
                audio_file,
            ],
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


def download_and_queue(video_id, username):
    print(f"{'Downloading:':<25}{video_id:<25}{'Queued by:':<25}{username}")

    audio_format = "opus"

    # Check if the file has been downloaded already
    matched_files = list(queue_dir.glob(f"* ({video_id}).{audio_format}"))
    if matched_files:
        audio_file = matched_files[0]
        print(f"{'Already downloaded:':<25}{audio_file}")
    else:
        # Get the filename and video categories
        yt_dlp_output = subprocess.run(
            [
                "yt-dlp",
                "--add-headers",
                "User-Agent:Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36",
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
        categories = video_info.get("categories", [])
        audio_file = queue_dir / f"{title} ({video_id}).{audio_format}"

        print(f"{'Title:':<25}{title}")

        # Check if the file is a music video
        # if "Music" not in categories:
        #    print(f"{'Not a music video:':<25}{title}")
        #    return

        # Download the file
        subprocess.run(
            [
                "yt-dlp",
                "--add-headers",
                "User-Agent:Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36",
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

        print(f"{'Downloaded:':<25}{audio_file}")

        # Normalization parameters
        lufs = -23
        tolerance = -1.0
        loudness_range = 9
        target_peak = -9
        peak_tolerance = 0.3

        temp_file = Path(f"tmp.{audio_format}")

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
                    sample_rate,
                    "-ac",
                    channels,
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
                        "silenceremove="
                        "start_periods=1:"
                        "start_threshold=-50dB:"
                        "start_silence=1:"
                        "stop_periods=1:"
                        "stop_threshold=-50dB:"
                        "stop_silence=1,"
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
                # Remove silence from the beginning and the end of the file and normalize it
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
                            "silenceremove="
                            "start_periods=1:"
                            "start_threshold=-50dB:"
                            "start_silence=1:"
                            "stop_periods=1:"
                            "stop_threshold=-50dB:"
                            "stop_silence=1,"
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
                        sample_rate,
                        "-ac",
                        channels,
                        str(temp_file),
                    ]
                )

                temp_file.replace(audio_file)

        print(f"{'Normalized:':<25}{audio_file}")

    # Check if the file is queued already
    queued_files = queue_file.read_text().splitlines()
    recently_played_files = recently_played_history_file.read_text().splitlines()

    if str(audio_file) in queued_files:
        print(f"{'Already in the queue:':<25}{audio_file}")
    # Check if the file has been recently played
    elif str(audio_file) in recently_played_files:
        print(f"{'File recently played:':<25}{audio_file}")
    else:
        # Queue the file
        with queue_file.open("a") as file:
            file.write(f"{audio_file}\n")
        print(f"{'Queued:':<25}{audio_file}")

        recently_played_history_length = 5

        # Add the file to the recently played files list
        recently_played_files.append(str(audio_file))
        recently_played_files = recently_played_files[-recently_played_history_length:]
        recently_played_history_file.write_text(
            "\n".join(str(path) for path in recently_played_files) + "\n"
        )


def play_queue():
    while queue_file.exists() and queue_file.stat().st_size > 0:
        # Clear skip votes
        skip_vote_list.clear()

        queued_files = queue_file.read_text().splitlines()
        if queued_files:
            audio_file = queued_files[0]

            # Remove the current file from the queue file
            queue_file.write_text(
                "\n".join(queued_files[1:]) + ("\n" if len(queued_files) > 1 else "")
            )

            if not Path(audio_file).exists():
                print(f"{'File not found:':<25}{audio_file}")
            else:
                print(f"{'Now playing:':<25}{audio_file}")

                file_title = Path(audio_file).stem
                for pattern, replacement in replacements:
                    file_title = pattern.sub(replacement, file_title)
                file_title = re_allowed_filename_characters.sub("", file_title)

                speak_text(f"Now playing: {file_title}.")

                # Play the file
                global radio_process

                global skip_voting_open
                skip_voting_open = True

                radio_process = subprocess.Popen(
                    [
                        "paplay",
                        "--device=virtual_speaker",
                        "--client-name=radio",
                        audio_file,
                    ],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                radio_process.wait()

                skip_voting_open = False

                radio_process = None


def skip_current():
    # Clear skip votes
    skip_vote_list.clear()

    global radio_process
    if radio_process and radio_process.poll() is None:
        print(f"{'Queue:':<25}{'Stopping current playback.'}")
        radio_process.terminate()
        radio_process = None
    else:
        print(f"{'Queue:':<25}{'No active playback to stop.'}")


def start_queue():
    last_mtime = queue_file.stat().st_mtime

    while True:
        play_queue()

        while True:
            time.sleep(0.1)
            new_mtime = queue_file.stat().st_mtime
            if new_mtime != last_mtime:
                last_mtime = new_mtime
                break


queue_thread = Thread(
    target=start_queue,
    daemon=True,
)
queue_thread.start()


with open(console_log, "r") as log:
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
        # Search for lines containing the command
        if not re_command.search(line):
            continue
        # Remove messages from blacklisted players
        if re_blacklisted_names.search(line):
            continue
        # Keep messages only from whitelisted players
        if not re_whitelisted_names.search(line):
            continue
        # Remove messages with blacklisted words
        if re_blacklisted_words.search(line):
            continue
        # Remove non-ASCII and control characters
        line = re_allowed_characters.sub("", line)
        # Remove duplicate messages
        # if line == previous_line:
        #    continue
        # previous_line = line

        # Extract video urls, usernames, commands and command input
        matched_command = re_command.match(line)
        video_url = re_url.search(line)
        username = matched_command.group(3)

        selected_command = matched_command.group(4)
        if selected_command == "queue" and video_url:
            Thread(
                target=download_and_queue,
                args=(
                    video_url.group(4),
                    username,
                ),
                daemon=True,
            ).start()
        # Vote to skip the currently playing file
        elif selected_command == "skip" and skip_voting_open:
            # Check if the user has not voted yet
            if username not in skip_vote_list:
                skip_vote_list[username] = username
                print(f"{'Voted to skip:':<25}{username}")

                required_skip_vote_count = 5
                remaining_skip_vote_count = required_skip_vote_count - len(
                    skip_vote_list
                )

                if remaining_skip_vote_count > 1:
                    Thread(
                        target=speak_text,
                        args=(f"{remaining_skip_vote_count} votes remaining.",),
                        daemon=True,
                    ).start()
                elif remaining_skip_vote_count == 1:
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

                    print(f"{'Queue:':<25}{'Skipping the file.'}")
                    skip_current()
