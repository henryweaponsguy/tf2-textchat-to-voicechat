#!/usr/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


translation_server="http://127.0.0.1:5001/translate"


translate() {
    text="$1"
    [[ -z "$text" ]] && return

    data="$(
cat <<EOF
{
    "q": "$text",
    "source": "auto",
    "target": "en"
  }
EOF
)"

    IFS=$'\t' read language translated_text < <(
        curl -X POST "$translation_server" -H "Content-Type: application/json" --data "$data" \
            --silent --show-error |
        jq -r '[.detectedLanguage.language, .translatedText] | @tsv'
    )

    [[ "$language" == "en" ]] && return

    printf "%s\n%s\n%s\n%s\n" "$text" "[$language]" "$translated_text" "====================" >&2

    "${script_dir}/get_piper_voice.sh" "$translated_text"
}


# Determine mode
if [[ -n "$1" ]]; then
    # Command-line mode
    translate "$*"
elif ! tty -s; then
    # Streaming mode
    while IFS= read -r line; do
        translate "$line" &
    done
else
    echo "Usage:"
    echo "  $0 \"Your text here\"     # Translate a single line"
    echo "  echo 'text' | $0          # Translate from a pipe"
    exit 1
fi
