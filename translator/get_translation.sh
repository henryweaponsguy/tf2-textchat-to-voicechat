#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


translation_server="http://localhost:5001/translate"


translate() {
    text="$1"
    [[ -z "$text" ]] && return

    language="$(python3 -c "import sys; from langdetect import detect; print(detect(sys.argv[1]))" "$text")"

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

    echo "$text"
    echo "$language"
    echo "$translation"

    "${script_dir}/get_piper_voice.sh" "$translation"
}


# Determine mode
if [ -n "$1" ]; then
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
