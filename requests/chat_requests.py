import json
import re
import signal
import subprocess
import sys
from pathlib import Path

script_dir = Path(__file__).resolve().parent


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log = script_dir / "console.log"

# User blacklist:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
blacklisted_names = ""

# Alternatively, a whitelist:
whitelisted_names = ""

# Word blacklist:
# Example: "dQw4w9WgXcQ|dwDns8x3Jb4|ZZ5LpwO-An4"
blacklisted_words = ""


re_command = re.compile(
    r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :  !request (.+)"
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

        # Extract usernames and messages
        matched_command = re_command.match(line)
        username = matched_command.group(3)
        message = matched_command.group(4)
        video_id = re_url.match(message).group(4)

        title=""
        channel=""
        if video_id:
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

        print(f"{username}\t{message}\t{title}\t{channel}")
