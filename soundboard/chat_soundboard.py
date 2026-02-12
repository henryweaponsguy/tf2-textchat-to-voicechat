import random
import re
import signal
import subprocess
import sys
import time
from threading import Thread
from pathlib import Path

# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


# Soundboard sounds directory
sound_dir="/tts/sounds"

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
# Example: "nominate|rtv|nextmap"
# Default: "$^"
blacklisted_words = r"$^"


previous_line = None

#re_command = re.compile(r"^(\*DEAD\*)?(\(TEAM\))? ?(.+) :  !(play) (.+)")
re_command = re.compile(r"^(\*DEAD\*)?(\(TEAM\))? ?(.+) :  (.+)")
# re_blacklisted_names = re.compile(rf"^(\*DEAD\*)?(\(TEAM\))? ?({blacklisted_names}) :  !")
re_blacklisted_names = re.compile(rf"^(\*DEAD\*)?(\(TEAM\))? ?({blacklisted_names}) :  ")
# re_whitelisted_names = re.compile(rf"^(\*DEAD\*)?(\(TEAM\))? ?({whitelisted_names}) :  !")
re_whitelisted_names = re.compile(rf"^(\*DEAD\*)?(\(TEAM\))? ?({whitelisted_names}) :  ")
re_blacklisted_words = re.compile(rf"{blacklisted_words}", re.IGNORECASE)
re_allowed_characters = re.compile(r"[^A-Za-z0-9\s!@#$%^&*()\-=+[\]{};:'\",.<>/?\\|`~]")

def play_sound(sound):
    subprocess.run(
        ["paplay", "--client-name=soundboard", sound],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
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
        # Extract the message
        #line = re_command.match(line).group(5)
        line = re_command.match(line).group(4)
        # Convert the message to lowercase
        line = line.lower()
        # Remove messages with blacklisted words
        if re_blacklisted_words.search(line):
            continue
        # Remove non-ASCII and control characters
        line = re_allowed_characters.sub("", line)
        # Trim and normalize whitespace
        line = " ".join(line.split())
        # Remove duplicate messages
        #if line == previous_line:
        #    continue
        #previous_line = line


        # Match files
        matched_files = list(Path(sound_dir).glob(f"{line}.*"))
        matched_files += list(Path(sound_dir).glob(f"{line} [0-9]*.*"))

        if matched_files:
            selected_file = str(random.choice(matched_files))

            Thread(
                target=play_sound,
                args=(selected_file,),
                daemon=True
            ).start()
