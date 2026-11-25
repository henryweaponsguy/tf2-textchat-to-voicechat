#!/usr/bin/env python3

import http.server
import json
import random
import re
import signal
import socketserver
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from threading import Lock, Thread

script_dir = Path(__file__).resolve().parent


def exit_cleanup(signum, frame):
    open(text_message_file, "w").close()

    sys.exit(0)


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, exit_cleanup)
signal.signal(signal.SIGTERM, exit_cleanup)


# The length of the recently played list (-1 to make it infinite).
# Videos in the recently played list cannot be queued again
recently_played_length = 5

# Required votes to skip the currently playing video
required_vote_count = 5

# Chance of playing a sound cue between files (0-100)
interlude_chance = 100

# Announcement sounds directory
sound_dir = script_dir / "sounds"

# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log = script_dir / "console.log"

# Location of the file storing generated text chat messages.
# This file should be in the same directory as TF2's autoexec.cfg
text_message_file = script_dir / "message.cfg"

# User blacklist:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
blacklisted_users = ""

# Alternatively, a whitelist:
whitelisted_users = ""

# Word blacklist:
# Example: "dQw4w9WgXcQ|dwDns8x3Jb4|ZZ5LpwO-An4"
blacklisted_words = ""


queue_dir = script_dir / "queue"
queue_file = queue_dir / "queue.txt"
recently_played_file = queue_dir / "recently_played.txt"

queue_dir.mkdir(parents=True, exist_ok=True)

for file in [queue_file, recently_played_file]:
    file.touch()

open(text_message_file, "w").close()

webserver_port = 8000
radio_lock = Lock()
sse_client = None
announcer_process = None
queue_thread = None
current_video = None
voting_open = False
vote_list = set()
last_text_message_time = None

re_line = re.compile(r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.+)")
re_command = re.compile(r"^(?i:(!queue|!skip)) *(.+)?")
re_text_message_signal = re.compile(r"^\[ ?RADIO\]")
re_blacklisted_users = re.compile(rf"{blacklisted_users or '$^'}")
re_whitelisted_users = re.compile(rf"{whitelisted_users or '.*'}")
re_blacklisted_words = re.compile(rf"{blacklisted_words or '$^'}", re.IGNORECASE)
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
]


class ReusableTCPServer(socketserver.ThreadingTCPServer):
    # Allow rebinding the TCP port immediately after restarting
    allow_reuse_address = True
    daemon_threads = True


class RequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=script_dir, **kwargs)

    def do_GET(self):
        if self.path == "/radio":
            self.handle_sse()
        else:
            super().do_GET()

    def do_POST(self):
        if self.path == "/radio":
            self.handle_command()
        else:
            self.send_error(404)

    def handle_sse(self):
        global sse_client

        self.send_response(200)

        # Set SSE headers
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")

        self.end_headers()

        with radio_lock:
            sse_client = self

        try:
            while True:
                self.wfile.write((": keepalive\n\n").encode("utf-8"))
                self.wfile.flush()

                time.sleep(15)
        except (BrokenPipeError, ConnectionResetError, OSError):
            # If the connection is broken, clear the web client and the currently playing video
            with radio_lock:
                if sse_client is self:
                    sse_client = None

    def handle_command(self):
        request_length = int(self.headers.get("Content-Length", 0))
        command = self.rfile.read(request_length).decode("utf-8").strip()

        if command == "next":
            play_next()

            self.send_response(204)
            self.end_headers()
        else:
            self.send_error(400, "Unknown command")

    # Hide access logs
    def log_message(self, format, *args):
        pass


def send_text_message(text):
    global last_text_message_time

    text_message = " ".join(text.split())[:127]

    with open(text_message_file, "w") as file:
        file.write(f'say "{text_message}"\n')

    last_text_message_time = time.time()


def clear_text_message():
    global last_text_message_time

    open(text_message_file, "w").close()
    last_text_message_time = None


def play_sound(sound):
    # Match files
    matched_files = (
        list(Path(sound_dir).glob(f"{sound}.*"))
        + list(Path(sound_dir).glob(f"{sound} [0-9]*.*"))
        + list(Path(sound_dir).glob(f"{sound}/*.*"))
        + list(Path(sound_dir).glob(f"{sound}/* [0-9]*.*"))
    )

    if not matched_files:
        return

    selected_file = str(random.choice(matched_files))

    subprocess.run(
        [
            "paplay",
            "--device=virtual_speaker",
            "--client-name=soundboard",
            selected_file,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def add_to_queue(video_id):
    global current_video
    global sse_client

    print(f"{'Queuing:':<25}{video_id}")
    print(f"{'Queued by:':<25}{username}")

    # Check if the video is queued already
    with radio_lock:
        queued_files = dict(
            line.split("\t", 1) for line in queue_file.read_text().splitlines()
        )

    recently_played_files = dict(
        line.split("\t", 1) for line in recently_played_file.read_text().splitlines()
    )

    if video_id in queued_files:
        print(f"\033[32m{'Already in the queue:':<25}{queued_files[video_id]}\033[0m")
    # Check if the video has been recently played
    elif video_id in recently_played_files:
        print(
            f"\033[32m{'File recently played:':<25}{recently_played_files[video_id]}\033[0m"
        )
    else:
        try:
            # Get the video's title and channel
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
            title = video_info["title"]
            channel = video_info["channel"]
        except json.JSONDecodeError:
            print(f"\033[31m{'yt-dlp error:':<25}{yt_dlp_output.stderr}\033[0m")
            return

        print(f"{'Title:':<25}{title}")
        print(f"{'Channel:':<25}{channel}")
        print()

        # Add the video to the recently played files list
        recently_played_files[video_id] = title

        if recently_played_length == 0:
            recently_played_files = {}
        elif recently_played_length > 0:
            recently_played_files = dict(
                list(recently_played_files.items())[-recently_played_length:]
            )

        recently_played_file.write_text(
            "".join(
                f"{video_id}\t{title}\n"
                for video_id, title in recently_played_files.items()
            )
        )

        # Queue the video
        with radio_lock:
            with open(queue_file, "a") as file:
                file.write(f"{video_id}\t{title}\n")

            radio_idle = current_video is None

        if radio_idle:
            with radio_lock:
                client = sse_client

                if client is None:
                    return

            try:
                # Notify the web client the queue is populated
                client.wfile.write(
                    (f"event: ensure_playback\ndata:\n\n").encode("utf-8")
                )
                client.wfile.flush()
            except (BrokenPipeError, ConnectionResetError, OSError):
                # If the connection is broken, clear the web client
                with radio_lock:
                    if sse_client is client:
                        sse_client = None


def play_next():
    global current_video
    global voting_open
    global sse_client

    with radio_lock:
        client = sse_client

        if client is None:
            return

        if queue_file.stat().st_size == 0:
            voting_open = False
            current_video = None
            return

        # Get the next video from the queue file
        with open(queue_file, "r+") as file:
            video_id, title = file.readline().rstrip("\n").split("\t")

            rest = file.read()
            file.seek(0)
            file.write(rest)
            file.truncate()

        current_video = video_id

    print(f"\033[33m{'Now playing:':<25}{title}\033[0m")

    clean_title = title
    for pattern, replacement in replacements:
        clean_title = pattern.sub(replacement, clean_title)

    if random.randint(0, 99) < interlude_chance:
        play_sound("interlude")

    text_message_prefix = "[RADIO] "
    text_message_suffix = f" ({video_id})"
    truncated_title_length = 127 - len(text_message_prefix) - len(text_message_suffix)
    truncated_title = " ".join(clean_title.split())[:truncated_title_length]

    send_text_message(f"{text_message_prefix}{truncated_title}{text_message_suffix}")

    with radio_lock:
        # Clear votes
        vote_list.clear()

        voting_open = True

    try:
        # Send the video ID to the web client
        client.wfile.write((f"event: play\ndata: {video_id}\n\n").encode("utf-8"))
        client.wfile.flush()
    except (BrokenPipeError, ConnectionResetError, OSError):
        # If the connection is broken, clear the web client and the currently playing video
        with radio_lock:
            if sse_client is client:
                sse_client = None

            current_video = None


def skip_current():
    global current_video
    global voting_open
    global sse_client

    with radio_lock:
        client = sse_client

        if client is None:
            return

    try:
        # Send the skip request to the web client
        client.wfile.write((f"event: skip\ndata:\n\n").encode("utf-8"))
        client.wfile.flush()
    except (BrokenPipeError, ConnectionResetError, OSError):
        # If the connection is broken, clear the web client
        with radio_lock:
            if sse_client is client:
                sse_client = None

    play_next()


def start_webserver():
    with ReusableTCPServer(("", webserver_port), RequestHandler) as server:
        server.serve_forever()


# Start the web server in the background
Thread(
    target=start_webserver,
    daemon=True,
).start()

print(
    f"\033[35m{'Web server:':<25}Listening at http://127.0.0.1:{webserver_port}'\033[0m"
)


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

        # Clear the old text message
        if re_text_message_signal.search(message) or (
            last_text_message_time and (time.time() - last_text_message_time > 5)
        ):
            clear_text_message()
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

        if command_name == "!queue" and command_text:
            # Check if the video ID is valid
            matched_video_url = re_url.match(command_text)
            if not matched_video_url:
                continue

            video_id = matched_video_url.group(4)

            Thread(
                target=add_to_queue,
                args=(video_id,),
                daemon=True,
            ).start()
        # Vote to skip the currently playing video
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

                send_text_message(f"[RADIO] Remaining votes: {remaining_vote_count}")

                if remaining_vote_count > 0:
                    Thread(
                        target=play_sound,
                        args=(remaining_vote_count,),
                        daemon=True,
                    ).start()
                # Skip the currently playing file if the required number of skip votes has been reached
                else:
                    print(f"\033[36m{'Queue:':<25}{'Skipping the video'}\033[0m")

                    clear_text_message()

                    skip_current()
