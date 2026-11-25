#!/usr/bin/env python3

import json
import random
import signal
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

from langdetect import LangDetectException, detect
from lexilang.detector import detect as dict_detect

from get_piper_voice import speak_text

# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


translation_server = "http://127.0.0.1:5001/translate"


def translate(text):
    if not text:
        return

    data = {"q": text, "source": "auto", "target": "en"}

    post_request = urllib.request.Request(
        translation_server,
        data=json.dumps(data).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    with urllib.request.urlopen(post_request) as response:
        translation = json.load(response)

    language = translation["detectedLanguage"]["language"]
    if language == "en":
        return

    translated_text = translation["translatedText"]

    print(f"{text}\n[{language}]\n{translated_text}\n====================")

    speak_text(translated_text)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        translate(sys.argv[1])
    else:
        print("Usage:")
        print(f'  {sys.argv[0]} "Your text here"     # Translate a single line')
        sys.exit(1)
