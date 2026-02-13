import json
import re
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from threading import Thread

def exit_cleanup(signum, frame):
    for process in [announcer_process, radio_process]:
        if process and process.poll() is None:
            process.terminate()

    for file in Path("/tmp").glob(f"dectalk_voice-*.wav"):
        try:
            file.unlink()
        except FileNotFoundError:
            pass

    sys.exit(0)

# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, exit_cleanup)
signal.signal(signal.SIGTERM, exit_cleanup)


# Queue management files
queue_dir="/tts/queue"
queue_file="/tts/queue.txt"
recently_played_history_file="/tts/recently_played_history.txt"

Path(queue_dir).mkdir(parents=True, exist_ok=True)

for file in [queue_file, recently_played_history_file]:
    path = Path(file)
    if not path.exists():
        path.touch()

# Add '-condebug' as TF2's launch parameter.
# Alternatively, add "con_logfile <logfile location>" to autoexec.cfg
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log = "/tts/console.log"

# User blacklist:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
# Default: "$^"
blacklisted_names = r"$^"

# Alternatively, a whitelist:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
# Default: ".*"
whitelisted_names = r".*"

# Word blacklist:
# Example: "dQw4w9WgXcQ\|dwDns8x3Jb4\|ZZ5LpwO-An4"
# Default: "$^"
blacklisted_words = r"$^"


previous_line = None

queue_thread = None
announcer_process = None
radio_process = None
skip_voting_open = False

skip_vote_list = {}

re_command = re.compile(r"^(\*DEAD\*)?(\(TEAM\))? ?(.+) :  !(queue|skip)( .+)?")
re_blacklisted_names = re.compile(rf"^(\*DEAD\*)?(\(TEAM\))? ?({blacklisted_names}) :  !")
re_whitelisted_names = re.compile(rf"^(\*DEAD\*)?(\(TEAM\))? ?({whitelisted_names}) :  !")
re_blacklisted_words = re.compile(rf"{blacklisted_words}", re.IGNORECASE)
re_allowed_characters = re.compile(r"[^A-Za-z0-9\s!@#$%^&*()\-=+[\]{};:'\",.<>/?\\|`~]")
re_allowed_filename_characters = re.compile(r"[^A-Za-z0-9\s'-_]")
re_url = re.compile(r"(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)([A-Za-z0-9_-]+)")

replacements = [
    (re.compile(r"\([A-Za-z0-9_-]+\)$"), ""),
    (re.compile(r"[\[\(]( *([48]k|hd|hq|music|official|remastered|audio|video)){1,7}[\]\)] *",
        re.IGNORECASE), ""),
    (re.compile(r"[-_]"), ","),
]

def speak_text(text):
    if not text:
        return

    with tempfile.NamedTemporaryFile(prefix="dectalk_voice-", suffix=".wav", delete=False) as tmp:
        audio_file = tmp.name

    try:
        subprocess.run(["say", "-pre", "[:name HARRY]", "-e", "1", "-a", text, "-fo", audio_file])

        # Stop the previous announcement
        global announcer_process
        if announcer_process and announcer_process.poll() is None:
            announcer_process.terminate()

        announcer_process = subprocess.Popen(
            ["paplay", "--client-name=radio-announcer", audio_file],
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

def download_and_queue(video_id):
    print(f"Downloading: {video_id}")

    audio_format="opus"

    # Check if a file exists already
    matched_files = list(Path(queue_dir).glob(f"* ({video_id}).{audio_format}"))
    if matched_files:
        audio_file = matched_files[0]
        print(f"Already downloaded: {audio_file}")
    else:
        # Get the filename and video categories
        yt_dlp_output = subprocess.run(
            [
                "yt-dlp",
                "--skip-download",
               "--no-warnings",
                "--print-json",
                video_id,
            ],
            capture_output=True,
            text=True
        )

        info = json.loads(yt_dlp_output.stdout)
        title = info["title"]
        categories = info.get("categories", [])
        audio_file = Path(queue_dir) / f"{title} ({video_id}).{audio_format}"

        print(f"Title: {title}")

        # Check if the file is a music video
        #if "Music" not in categories:
        #    print(f"Not a music video: {title}")
        #    return

        # Download the file
        subprocess.run(
            [
                "yt-dlp",
                "--extract-audio",
                "--audio-format", audio_format,
                "--match-filter", "duration < 1200",
                "--output", f"{queue_dir}/%(title)s ({video_id}).%(ext)s",
                "--no-playlist",
                "--quiet",
                video_id,
            ]
        )

        # Check if the file has been downloaded successfully
        if not audio_file.exists():
            print(f"Video unavailable: {title}")
            return

        print(f"Downloaded: {audio_file}")

        # Normalize audio
        temp_file = Path(f"tmp.{audio_format}")

        subprocess.run([
            "ffmpeg",
            "-hide_banner",
            "-loglevel", "error",
            "-i", str(audio_file),
            "-af", "loudnorm=I=-23:TP=-1.0:LRA=11",
            "-ac", "1",
            "-ar", "24000",
            str(temp_file),
        ])

        temp_file.replace(audio_file)

        print(f"Normalized: {audio_file}")

    # Check if the file is queued already
    queued_files = Path(queue_file).read_text().splitlines()
    recently_played_files = Path(recently_played_history_file).read_text().splitlines()

    if str(audio_file) in queued_files:
        print(f"Already in the queue: {audio_file}")
    # Check if the file has been recently played
    elif str(audio_file) in recently_played_files:
        print(f"File recently played: {audio_file}")
    else:
        # Queue the file
        with Path(queue_file).open("a") as file:
            file.write(f"{audio_file}\n")
        print(f"Queued: {audio_file}")

        recently_played_history_length = 5

        # Add the file to the recently played files list
        recently_played_files.append(str(audio_file))
        recently_played_files = recently_played_files[-recently_played_history_length:]
        Path(recently_played_history_file).write_text(
            "\n".join(str(path) for path in recently_played_files) + "\n"
        )

def play_queue():
    queue_path = Path(queue_file)
    while queue_path.exists() and queue_path.stat().st_size > 0:
        # Clear skip votes
        skip_vote_list.clear()

        queued_files = queue_path.read_text().splitlines()
        if queued_files:
            audio_file = queued_files[0]

            # Remove the current file from the queue file
            queue_path.write_text("\n".join(queued_files[1:]) + ("\n" if len(queued_files) > 1 else ""))

            if not Path(audio_file).exists():
                print(f"File not found: {audio_file}")
            else:
                print(f"Playing: {audio_file}")

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
                    ["paplay", "--client-name=radio", audio_file],
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
        print(f"Stopping current playback.")
        radio_process.terminate()
        radio_process = None
    else:
        print("No active playback to stop.")

def start_queue():
    queue_path = Path(queue_file)
    last_mtime = queue_path.stat().st_mtime

    while True:
        play_queue()

        while True:
            time.sleep(0.1)
            new_mtime = queue_path.stat().st_mtime
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
        #if line == previous_line:
        #    continue
        #previous_line = line

        # Extract video urls, usernames, commands and command input
        matched_command = re_command.match(line)
        video_url = re_url.search(line)

        selected_command = matched_command.group(4)
        if selected_command == "queue" and video_url:
            Thread(
                target=download_and_queue,
                args=(video_url.group(4),),
                daemon=True,
            ).start()
        # Vote to skip the currently playing file
        elif selected_command == "skip" and skip_voting_open:
            username = matched_command.group(3)

            # Check if the user has not voted yet
            if username not in skip_vote_list:
                skip_vote_list[username] = username
                print(f"Voted to skip: {username}")

                required_skip_vote_count = 5
                remaining_skip_vote_count = required_skip_vote_count - len(skip_vote_list)

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

                    print("Skipping the file...")
                    skip_current()
