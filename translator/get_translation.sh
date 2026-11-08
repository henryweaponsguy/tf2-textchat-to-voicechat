#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


translation_server="http://127.0.0.1:5001/translate"


translate() {
    text="$1"
    [[ -z "$text" ]] && return

    language="$(python3 -c '
import sys
from lexilang.detector import detect as dict_detect
from langdetect import detect
from langdetect import LangDetectException

if len(text) <= 20:
    print(dict_detect(text)[0])
else:
    try:
        print(detect(sys.argv[1]))
    except LangDetectException:
        print("en")
    ' "$text")"

    [[ "$language" == "en" ]] && return

    [[ "$language" == "zh-cn" ]] && language="zh"


    data="$(
cat <<EOF
{
    "q": "$text",
    "source": "$language",
    "target": "en"
  }
EOF
)"

    translation="$(
        curl -X POST "$translation_server" -H "Content-Type: application/json" --data "$data" \
            --silent --show-error |
        jq -r '.translatedText'
    )"

    [[ "$translation" == "null" ]] && return

    printf "%s\n%s\n%s\n%s\n" "$text" "[$language]" "$translation" "====================" >&2

    "${script_dir}/get_piper_voice.sh" "$translation"
}


# Determine mode
if [[ -n "$1" ]]; then
    # Command-line mode
    translate "$*"
elif ! tty -s; then
    # Streaming mode
    while IFS= read -r line; do
        translate "$line"
    done
else
    echo "Usage:"
    echo "  $0 \"Your text here\"     # Translate a single line"
    echo "  echo 'text' | $0          # Translate from a pipe"
    exit 1
fi
