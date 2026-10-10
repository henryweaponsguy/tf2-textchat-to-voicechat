import re
import signal
import sys
import tempfile
import time
from pathlib import Path
from threading import Thread

from get_translation import translate

script_dir = Path(__file__).resolve().parent


def exit_cleanup(signum, frame):
    for file in Path(tempfile.gettempdir()).glob("piper_voice-*.wav"):
        try:
            file.unlink()
        except FileNotFoundError:
            pass

    sys.exit(0)


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, exit_cleanup)
signal.signal(signal.SIGTERM, exit_cleanup)


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
# Example: "nominate|rtv|nextmap"
blacklisted_words = ""


previous_line = None

re_command = re.compile(r"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :  (.+)")
re_blacklisted_names = re.compile(
    rf"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?({blacklisted_names or '$^'}) :  "
)
re_whitelisted_names = re.compile(
    rf"^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?({whitelisted_names or '.*'}) :  "
)
re_blacklisted_words = re.compile(rf"{blacklisted_words or '$^'}", re.IGNORECASE)
re_repetition = re.compile(r"(.{2,})\1{5,}")


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
        # Extract the message
        line = re_command.match(line).group(4)
        # Remove messages with blacklisted words
        if re_blacklisted_words.search(line):
            continue
        # Remove messages with excessive repetition
        if re_repetition.search(line):
            continue
        # Remove duplicate messages
        # if line == previous_line:
        #    continue
        # previous_line = line

        Thread(
            target=translate,
            args=(line,),
            daemon=True,
        ).start()
