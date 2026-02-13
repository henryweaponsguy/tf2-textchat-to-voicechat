import re
import signal
import sys
import tempfile
import time
from pathlib import Path
from threading import Thread
from get_sapi4_voice import speak_text

def exit_cleanup(signum, frame):
    for file in Path(tempfile.gettempdir()).glob("sapi4_voice-*.wav"):
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
console_log = "/tts/console.log"

# User blacklist:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
# Empty: "$^"
blacklisted_names = r"$^"

# Alternatively, a whitelist:
# Example: "John|pablo.gonzales.2007|Engineer Gaming"
# Empty: ".*"
whitelisted_names = r".*"

# Word blacklist:
# Example: "nominate|rtv|nextmap"
# Empty: "$^"
blacklisted_words = r"$^"


previous_line = None

re_command = re.compile(r"^(\*DEAD\*)?(\(TEAM\))? ?(.+) :  !(tts) (.+)")
re_blacklisted_names = re.compile(rf"^(\*DEAD\*)?(\(TEAM\))? ?({blacklisted_names}) :  !")
re_whitelisted_names = re.compile(rf"^(\*DEAD\*)?(\(TEAM\))? ?({whitelisted_names}) :  !")
re_blacklisted_words = re.compile(rf"{blacklisted_words}", re.IGNORECASE)
re_repetition = re.compile(r"(.{2,})\1{5,}")
re_allowed_characters = re.compile(r"[^A-Za-z0-9\s!@#$%^&*()\-=+[\]{};:'\",.<>/?\\|`~]")

replacements = [
    (re.compile(r"btw", re.IGNORECASE), "by the way"),
    (re.compile(r"wtf", re.IGNORECASE), "what the fuck"),
    (re.compile(r"idk", re.IGNORECASE), "i don't know"),
]

def replace_patterns(text):
    for pattern, replacement in replacements:
        text = pattern.sub(replacement, text)

    return text


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
        line = re_command.match(line).group(5)
        # Replace certain patterns
        line = replace_patterns(line)
        # Remove messages with blacklisted words
        if re_blacklisted_words.search(line):
            continue
        # Remove messages with excessive repetition
        if re_repetition.search(line):
            continue
        # Remove non-ASCII and control characters
        line = re_allowed_characters.sub("", line)
        # Trim and normalize whitespace
        line = " ".join(line.split())
        # Remove duplicate messages
        #if line == previous_line:
        #    continue
        #previous_line = line


        Thread(
            target=speak_text,
            args=(line,),
            daemon=True,
        ).start()
