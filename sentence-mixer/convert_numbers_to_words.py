import re
import sys


BASE_NUMBERS = {
    "0":  "zero",
    "1":  "one",
    "2":  "two",
    "3":  "three",
    "4":  "four",
    "5":  "five",
    "6":  "six",
    "7":  "seven",
    "8":  "eight",
    "9":  "nine",
    "10": "ten",
    "11": "eleven",
    "12": "twelve",
    "13": "thirteen",
    "14": "fourteen",
    "15": "fifteen",
    "16": "sixteen",
    "17": "seventeen",
    "18": "eighteen",
    "19": "nineteen",
    "20": "twenty",
    "30": "thirty",
    "40": "forty",
    "50": "fifty",
    "60": "sixty",
    "70": "seventy",
    "80": "eighty",
    "90": "ninety",
    "100": "hundred",
    "1000": "thousand",
}

IRREGULAR_ORDINALS = {
    "one": "first",
    "two": "second",
    "three": "third",
    "five": "fifth",
    "eight": "eighth",
    "nine": "ninth",
    "twelve": "twelfth",
}

re_numbers = re.compile(rf"^-?[0-9]+(st|nd|rd|th)?$", re.IGNORECASE)
re_ordinal_suffixes = re.compile(r"(st|nd|rd|th)$", re.IGNORECASE)

def get_separated_numbers(number):
    # Split a number into phonetic chunks. For example, '345' is converted into '3 100 40 5'
    number = int(number)

    # Loop through the BASE_NUMBERS dictionary in reverse
    for base_number in reversed(list(BASE_NUMBERS)):
        base_number = int(base_number)

        if base_number > number:
            continue

        phonetic_chunks = []

        if number == 0:
            quotient = 1
            remainder = 0
        else:
            quotient = number // base_number
            remainder = number % base_number

        if quotient == 1:
            if base_number >= 100:
                phonetic_chunks.append("1")
        else:
            phonetic_chunks.extend(get_separated_numbers(quotient))

        phonetic_chunks.append(str(base_number))

        if remainder > 0:
            phonetic_chunks.extend(get_separated_numbers(remainder))

        break

    return phonetic_chunks


def convert_numbers_to_words(number):
    number = str(number)
    ordinal = False
    words = []

    # Handle negative numbers
    if number[:1] == "-":
        words.append("negative")
        number = number[1:]

    # Check for ordinal numerals
    if re_ordinal_suffixes.search(number):
        ordinal = True
        number = number[:-2]

    # Handle natural numbers
    if int(number) >= 1000000:
        for digit in number:
            words.append(BASE_NUMBERS[digit])
    else:
        for separated_number in get_separated_numbers(number):
            words.append(BASE_NUMBERS[separated_number])

    # Handle ordinal numerals
    if ordinal:
        last_word = words[-1]

        if last_word in IRREGULAR_ORDINALS:
            last_word = IRREGULAR_ORDINALS[last_word]
        else:
            if last_word.endswith("y"):
                last_word = f"{last_word[:-1]}ie"

            last_word = f"{last_word}th"

        words[-1] = last_word

    return " ".join(words)


if __name__ == "__main__":
    INPUT_VALUE = sys.argv[1]

    if re_numbers.match(INPUT_VALUE):
        print(convert_numbers_to_words(INPUT_VALUE))
    else:
        print("Error: Not a number")
        sys.exit(1)
