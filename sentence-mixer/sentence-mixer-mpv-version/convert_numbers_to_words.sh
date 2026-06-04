#!/bin/bash

readonly INPUT_VALUE="$1"

declare -A BASE_NUMBERS=(
    ["0"]="zero"
    ["1"]="one"
    ["2"]="two"
    ["3"]="three"
    ["4"]="four"
    ["5"]="five"
    ["6"]="six"
    ["7"]="seven"
    ["8"]="eight"
    ["9"]="nine"
    ["10"]="ten"
    ["11"]="eleven"
    ["12"]="twelve"
    ["13"]="thirteen"
    ["14"]="fourteen"
    ["15"]="fifteen"
    ["16"]="sixteen"
    ["17"]="seventeen"
    ["18"]="eighteen"
    ["19"]="nineteen"
    ["20"]="twenty"
    ["30"]="thirty"
    ["40"]="forty"
    ["50"]="fifty"
    ["60"]="sixty"
    ["70"]="seventy"
    ["80"]="eighty"
    ["90"]="ninety"
    ["100"]="hundred"
    ["1000"]="thousand"
)
readonly BASE_NUMBERS

declare -A IRREGULAR_ORDINALS=(
    ["one"]="first"
    ["two"]="second"
    ["three"]="third"
    ["five"]="fifth"
    ["eight"]="eighth"
    ["nine"]="ninth"
    ["twelve"]="twelfth"
)
readonly IRREGULAR_ORDINALS


get_separated_numbers() {
    # Split a number into phonetic chunks. For example, '345' is converted into '3 100 40 5'
    local number="$1"

    # Loop through the BASE_NUMBERS array in reverse
    for base_number in $(printf "%s\n" "${!BASE_NUMBERS[@]}" | sort -nr); do
        if [[ "$base_number" -gt "$number" ]]; then
            continue
        fi

        phonetic_chunks=()

        if [[ "$number" -eq 0 ]]; then
            quotient=1
            remainder=0
        else
            quotient=$(("$number" / "$base_number"))
            remainder=$(("$number" % "$base_number"))
        fi

        if [[ "$quotient" -eq 1 ]]; then
            if [[ "$base_number" -ge 100 ]]; then
                phonetic_chunks+=( 1 )
            fi
        else
            phonetic_chunks+=( $(get_separated_numbers "$quotient") )
        fi

        phonetic_chunks+=( "$base_number" )

        if [[ "$remainder" -gt 0 ]]; then
            phonetic_chunks+=( $(get_separated_numbers "$remainder") )
        fi

        break
    done

    echo "${phonetic_chunks[*]}"
}

convert_numbers_to_words() {
    local number="$1"
    local words=( )

    # Handle negative numbers
    if [ "${number:0:1}" == "-" ]; then
        words+=( "negative" )
        number="${number:1}"
    fi

    # Check for ordinal numerals
    if [[ "$number" =~ (st|nd|rd|th)$ ]]; then
        local ordinal="true"
        number="${number::-2}"
    fi

    # Handle natural numbers
    if [[ "$number" -ge 1000000 ]]; then
        for digit in $(echo "$number" | grep -o .); do
            words+=( "${BASE_NUMBERS[$digit]}" )
        done
    else
        for separated_number in $( ( get_separated_numbers "$number" ) ); do
            words+=( "${BASE_NUMBERS[$separated_number]}" )
        done
    fi

    # Handle ordinal numerals
    if [ -n "$ordinal" ]; then
        last_word="${words[-1]}"

        if [ -n "${IRREGULAR_ORDINALS[$last_word]}" ]; then
            last_word="${IRREGULAR_ORDINALS["$last_word"]}"
        else
            if [ "${last_word: -1}" == "y" ]; then
                last_word="${last_word::-1}ie"
            fi

            last_word="${last_word}th"
        fi

        words[-1]="$last_word"
    fi

    echo "${words[*]}"
}


if [[ "$INPUT_VALUE" =~ ^-?[0-9]+(st|nd|rd|th)?$ ]]; then
    convert_numbers_to_words "$INPUT_VALUE"
else
    echo "Error: Not a number"
fi
