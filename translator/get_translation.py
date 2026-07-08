import json
import random
import signal
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

from langdetect import detect

from get_piper_voice import speak_text

# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


translation_server = "http://localhost:5001/translate"


def translate(text):
    if not text:
        return

    language = detect(text)

    if language != "en":
        return

    if language == "zh-cn":
        language = "zh"

    data = {"q": text, "source": language, "target": "en"}

    post_request = urllib.request.Request(
        translation_server,
        data=json.dumps(data).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    with urllib.request.urlopen(post_request) as response:
        translation = json.load(response)["translatedText"]

    speak_text(translation)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        translate(sys.argv[1])
    else:
        print("Usage:")
        print(f'  {sys.argv[0]} "Your text here"     # Translate a single line')
        sys.exit(1)
