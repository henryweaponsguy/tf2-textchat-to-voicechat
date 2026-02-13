#!/bin/bash

sound_dir="/tts/sounds"
word_list="/tts/word_list.txt"
custom_dictionary="$sound_dir/_dictionary.sed"

mix_sentences() {
    read -r -a words <<< "$input_text"

    for i in "${!words[@]}"; do
        # Convert numbers to words
        if [[ "${words[i]}" =~ ^-?[0-9]+(st|nd|rd|th)?$ ]]; then
            words[i]=$(/tts/convert_numbers_to_words.sh "${words[i]}")
        fi
    done

    # Check if a custom dictionary is available
    if [ -e "$custom_dictionary" ]; then
        # Replace synonyms and unavailable forms of words with existing words
        read -r -a words <<< "$(sed -Ef "$custom_dictionary" <<< "${words[*]}")"

        for word in "${words[@]}"; do
            selected_file=""

            shopt -s nullglob
            matched_files=(
                # Check for unnumbered and numbered variants
                "$sound_dir/${word}".wav*
                "$sound_dir/${word} "[0-9]*.wav
            )
            shopt -u nullglob

            if [[ ${#matched_files[@]} -gt 0 ]]; then
                selected_file="${matched_files[RANDOM % ${#matched_files[@]}]}"
            else
                # If a corresponding file does not exist, use a placeholder file
                selected_file="$sound_dir/_placeholder.wav"
            fi

            echo "file '$selected_file'"
        done > "$word_list"
    else
        read -r -a words <<< "$(sed -E \
            -e "s/_/ /g" \
            -e "s/(,|;|=)/ _comma /g" \
            -e "s/-([^0-9])/ _comma \1/g" \
            -e "s/\.|!|\?/ _period /g" \
            -e "s/(&|\+)/ and /g" \
            -e "s/\=/ equals /g" \
            -e "s/@/ at /g" \
            -e "s/#/ number /g" \
            -e "s/%/ percent /g" \
            -e "s/0/ zero /g" \
            -e "s/1/ one /g" \
            -e "s/2/ two /g" \
            -e "s/3/ three /g" \
            -e "s/4/ four /g" \
            -e "s/5/ five /g" \
            -e "s/6/ six /g" \
            -e "s/7/ seven /g" \
            -e "s/8/ eight /g" \
            -e "s/9/ nine /g" \
        <<< "${words[*]}")"

        for word in "${words[@]}"; do
            selected_file=""

            # If the exact corresponding file exists.
            # Variants array is used so variant-matching goes through the variants
            # in a specific order instead of randomly selecting an existing variant.
            # This prevents returning 'apples' when 'apple' is requested
            variants=( "$word" )
            base_words=( "$word" )

            # If a corresponding file exists, but only in the infinitive form.
            # Infinitive is handled separately, only for words with specific suffixes.
            # This prevents returning 'app' when 'apple' is requested
            base=""

            # Checking each suffix separately as suffixes need to be checked in a specific order.
            # This prevents returning 'cooke' instead of 'cook' when 'cooked' is requested
            if [[ "$word" =~ (.*)(ing)$ ]]; then
                base="${BASH_REMATCH[1]}"
            elif [[ "$word" =~ (.*)(e[sd])$ ]]; then
                base="${BASH_REMATCH[1]}"
            elif [[ "$word" =~ (.*)([esd]|\'s)$ ]]; then
                base="${BASH_REMATCH[1]}"
            fi

            if [ -n "$base" ]; then
                variants+=( "$base" )
                base_words+=( "$base" )
            fi

            # If a corresponding file exists, but only in a different form
            suffixes=( "'s" "e" "s" "es" "d" "ed" "ing" )

            # Create the variants in a specifc order
            for base_word in "${base_words[@]}"; do
                for suffix in "${suffixes[@]}"; do
                    variants+=( "${base_word}${suffix}" )
                done
            done

            for variant in "${variants[@]}"; do
                shopt -s nullglob
                matched_files=(
                    # Check for unnumbered and numbered variants
                    "$sound_dir/${variant}".wav*
                    "$sound_dir/${variant} "[0-9]*.wav
                )
                shopt -u nullglob

                if [[ ${#matched_files[@]} -gt 0 ]]; then
                    selected_file="${matched_files[RANDOM % ${#matched_files[@]}]}"
                    break
                fi
            done

            # If a corresponding file does not exist, use a placeholder file
            if [[ -z "$selected_file" ]]; then
                selected_file="$sound_dir/_placeholder.wav"
            fi

            echo "file '$selected_file'"
        done > "$word_list"
    fi

    if [ -s "$word_list" ]; then
        # Add silence at the end, otherwise the sound may be cut off too early
        #echo "file '${sound_dir}/_period.wav'" >> "$word_list"

        ffmpeg -hide_banner -loglevel error -f concat -safe 0 -i "$word_list" \
        -ar 22050 -ac 1 -c copy -y "$audio_file"
    fi
}


speak_text() {
    input_text="$1"
    [[ -z "$input_text" ]] && return

    audio_file="$(mktemp /tmp/sentencemixed_voice-XXXXXXXXXX.wav)"

    mix_sentences "$input_text" "$audio_file"

    (
        paplay --client-name=sentence-mixer "$audio_file" >/dev/null 2>&1
        rm -f "$audio_file"
    ) &
}


# Determine mode
if [ -n "$1" ]; then
    # Command-line mode
    speak_text "$*"
elif ! tty -s; then
    # Streaming mode
    while IFS= read -r line; do
        speak_text "$line"
    done
else
    echo "Usage:"
    echo "  $0 \"Your text here\"     # Speak a single line"
    echo "  echo 'text' | $0           # Stream from a pipe"
    exit 1
fi
