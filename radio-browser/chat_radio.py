import http.server
import json
import re
import signal
import socketserver
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path
from threading import Lock, Thread

script_dir = Path(__file__).resolve().parent


def exit_cleanup(signum, frame):
    for process in [announcer_process]:
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


# Queue management files
queue_file = script_dir / "queue.txt"
recently_played_history_file = script_dir / "recently_played_history.txt"

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


piper_server = "http://localhost:5000/synthesize"
webserver_port = 8000
radio_lock = Lock()
sse_client = None
queue_thread = None
announcer_process = None
current_video = None
skip_voting_open = False


skip_vote_list = set()

re_command = re.compile(
    r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :  !(queue|skip) ?(.+)?"
)
re_blacklisted_names = re.compile(
    rf"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?({blacklisted_names or '$^'}) :  !"
)
re_whitelisted_names = re.compile(
    rf"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?({whitelisted_names or '.*'}) :  !"
)
re_blacklisted_words = re.compile(rf"{blacklisted_words or '$^'}", re.IGNORECASE)
re_url = re.compile(
    r"(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)([A-Za-z0-9_-]+)"
)

replacements = [
    (re.compile(r"[-_]"), ","),
    (re.compile(r"[^A-Za-z0-9\s'-_]"), ""),
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


def speak_text(text):
    if not text:
        return

    with tempfile.NamedTemporaryFile(
        prefix="piper_voice-", suffix=".wav", delete=False
    ) as tmp:
        audio_file = tmp.name

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
        global announcer_process
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
        try:
            Path(audio_file).unlink()
        except FileNotFoundError:
            pass


def add_to_queue(video_id):
    # Check if the video is queued already
    with radio_lock:
        queued_files = dict(
            line.split("\t", 1) for line in queue_file.read_text().splitlines()
        )

    recently_played_files = dict(
        line.split("\t", 1)
        for line in recently_played_history_file.read_text().splitlines()
    )

    if video_id in queued_files:
        print(f"\033[32m{'Already in the queue:':<25}{queued_files[video_id]}\033[0m")
    # Check if the video has been recently played
    elif video_id in recently_played_files:
        print(
            f"\033[32m{'File recently played:':<25}{recently_played_files[video_id]}\033[0m"
        )
    else:
        # Get the video's title and channel
        yt_dlp_output = subprocess.run(
            [
                "yt-dlp",
                "--js-runtimes",
                "deno:/root/.deno/bin/deno",
                "--add-headers",
                "User-Agent:Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36",
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

        print(f"{'Queued:':<25}{video_id}")
        print(f"{'Title:':<25}{title}")
        print(f"{'Channel:':<25}{channel}")
        print(f"{'Queued by:':<25}{username}")

        recently_played_history_length = 5

        # Add the video to the recently played files list
        recently_played_files[video_id] = title

        if recently_played_history_length > 0:
            recently_played_files = dict(
                list(recently_played_files.items())[-recently_played_history_length:]
            )

        recently_played_history_file.write_text(
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
            play_next()


def play_next():
    global current_video
    global skip_voting_open
    global sse_client

    with radio_lock:
        client = sse_client

        if client is None:
            return

        if queue_file.stat().st_size == 0:
            skip_voting_open = False
            current_video = None
            return

        # Get the next video from the queue file
        with open(queue_file, "r+") as file:
            video_id, title = file.readline().rstrip("\n").split("\t")

            rest = file.read()
            file.seek(0)
            file.write(rest)
            file.truncate()

    print(f"\033[33m{'Now playing:':<25}{title}\033[0m")

    for pattern, replacement in replacements:
        clean_title = pattern.sub(replacement, title)

    speak_text(f"Now playing: {clean_title}.")

    with radio_lock:
        # Clear skip votes
        skip_vote_list.clear()

        skip_voting_open = True

        current_video = video_id

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
    global skip_voting_open
    global sse_client

    with radio_lock:
        client = sse_client

        if client is None:
            return

    try:
        # Send the skip request to the web client
        client.wfile.write((f"event: skip\n\n").encode("utf-8"))
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
    f"\033[35m{'Web server':<25}Listening at http://localhost:{webserver_port}'\033[0m"
)


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

        # Extract video urls, usernames, commands and command input
        matched_command = re_command.match(line)
        username = matched_command.group(3)
        selected_command = matched_command.group(4)
        video_url = matched_command.group(5)

        if selected_command == "queue" and video_url:
            video_id = re_url.match(video_url).group(4)

            Thread(
                target=add_to_queue,
                args=(video_id,),
                daemon=True,
            ).start()
        # Vote to skip the currently playing file
        elif selected_command == "skip" and skip_voting_open:
            # Check if the user has not voted yet
            if username not in skip_vote_list:
                skip_vote_list.add(username)
                print(f"\033[34m{'Voted to skip:':<25}{username}\033[0m")

                required_vote_count = 5
                remaining_vote_count = required_vote_count - len(skip_vote_list)

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
                # Skip the currently playing video if the required number of skip votes has been reached
                else:
                    Thread(
                        target=speak_text,
                        args=("Skipping the video.",),
                        daemon=True,
                    ).start()

                    print(f"\033[36m{'Queue:':<25}{'Skipping the video'}\033[0m")
                    skip_current()
