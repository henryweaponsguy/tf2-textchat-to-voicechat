import random
import re
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

from convert_numbers_to_words import convert_numbers_to_words

script_dir = Path(__file__).resolve().parent


# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


word_list_file = Path(tempfile.gettempdir(), "word_list.m3u")
voices_dir = script_dir / "voices"

if not word_list_file.exists():
    word_list_file.touch()

word_list = []

re_numbers = re.compile(rf"^-?[0-9]+(st|nd|rd|th)?$", re.IGNORECASE)

suffix_patterns = [
    re.compile(r"^(.*)(ing)$"),
    re.compile(r"^(.*)(e[sd])$"),
    re.compile(r"^(.*)([esd]|'s)$"),
]

default_dictionary = [
    (re.compile(r"_"), " "),
    (re.compile(r"[,;]"), " _comma "),
    (re.compile(r"-([^0-9])"), r" _comma \1"),
    (re.compile(r"[\.!\?]"), " _period "),
    (re.compile(r"[&\+]"), " and "),
    (re.compile(r"="), " equals "),
    (re.compile(r"@"), " at "),
    (re.compile(r"#"), " number "),
    (re.compile(r"%"), " percent "),
    (re.compile(r"0"), " zero "),
    (re.compile(r"1"), " one "),
    (re.compile(r"2"), " two "),
    (re.compile(r"3"), " three "),
    (re.compile(r"4"), " four "),
    (re.compile(r"5"), " five "),
    (re.compile(r"6"), " six "),
    (re.compile(r"7"), " seven "),
    (re.compile(r"8"), " eight "),
    (re.compile(r"9"), " nine "),
]

# Import custom dictionaries
custom_dictionaries = {}

for voice_dir in voices_dir.iterdir():
    voice = voice_dir.name
    custom_dictionary_file = voice_dir / "_dictionary.sed"

    if custom_dictionary_file.exists():
        custom_dictionary = []

        with open(custom_dictionary_file) as dictionary:
            for line in dictionary:
                line = line.strip()
                if not line or not line.startswith("s/"):
                    continue

                # Split the rule into s, pattern, replacement, flags
                _, pattern, replacement, flags = line.split("/")

                custom_dictionary.append(
                    (
                        re.compile(pattern, re.IGNORECASE if "i" in flags else 0),
                        replacement,
                    )
                )

        custom_dictionaries[voice] = custom_dictionary


def apply_dictionary(words, dictionary):
    converted_words = []

    for word in words:
        for pattern, replacement in dictionary:
            word = pattern.sub(replacement, word)

        converted_words.extend(word.split())

    return converted_words


def mix_sentences(sound_dir, voice, text):
    words = text.split()

    for i, word in enumerate(words):
        # Convert numbers to words
        if re_numbers.match(word):
            words[i] = convert_numbers_to_words(word)

    # Check if a custom dictionary is available
    if voice in custom_dictionaries:
        # Replace synonyms and unavailable forms of words with existing words
        words = apply_dictionary(words, custom_dictionaries[voice])

        for word in words:
            selected_file = ""

            # Check for unnumbered and numbered variants
            matched_files = list(sound_dir.glob(f"{word}.wav")) + list(
                sound_dir.glob(f"{word} [0-9]*.wav")
            )

            if matched_files:
                selected_file = str(random.choice(matched_files))
            else:
                # If a corresponding file does not exist, use a placeholder file
                matched_files = list(sound_dir.glob("_placeholder.wav")) + list(
                    sound_dir.glob("_placeholder [0-9]*.wav")
                )

                if matched_files:
                    selected_file = str(random.choice(matched_files))

            word_list.append(selected_file)
    else:
        words = apply_dictionary(words, default_dictionary)

        for word in words:
            selected_file = ""

            # If the exact corresponding file exists.
            # Variants array is used so variant-matching goes through the variants
            # in a specific order instead of randomly selecting an existing variant.
            # This prevents returning 'apples' when 'apple' is requested
            variants = [word]
            base_words = [word]

            # If a corresponding file exists, but only in the infinitive form.
            # Infinitive is handled separately, only for words with specific suffixes.
            # This prevents returning 'app' when 'apple' is requested
            base = ""

            # Checking each suffix separately as suffixes need to be checked in a specific order.
            # This prevents returning 'cooke' instead of 'cook' when 'cooked' is requested
            for suffix_pattern in suffix_patterns:
                matched_suffixes = suffix_pattern.match(word)

                if matched_suffixes:
                    base = matched_suffixes.group(1)
                    break

            if base:
                variants.append(base)
                base_words.append(base)

            # If a corresponding file exists, but only in a different form
            suffixes = ["'s", "e", "s", "es", "d", "ed", "ing"]

            # Create the variants in a specifc order
            for base_word in base_words:
                for suffix in suffixes:
                    variants.append(f"{base_word}{suffix}")

            for variant in variants:
                # Check for unnumbered and numbered variants
                matched_files = list(sound_dir.glob(f"{variant}.wav")) + list(
                    sound_dir.glob(f"{variant} [0-9]*.wav")
                )

                if matched_files:
                    selected_file = str(random.choice(matched_files))
                    break

            # If a corresponding file does not exist, use a placeholder file
            if not selected_file:
                matched_files = list(sound_dir.glob("_placeholder.wav")) + list(
                    sound_dir.glob("_placeholder [0-9]*.wav")
                )

                if matched_files:
                    selected_file = str(random.choice(matched_files))

            word_list.append(selected_file)

    if word_list:
        with open(word_list_file, "w") as file:
            file.writelines(f"{line}\n" for line in word_list)


def speak_text(line):
    voice, text = (line.split(" ", 1) + [""])[:2]

    sound_dir = voices_dir / voice
    if not sound_dir.is_dir() or not text:
        return

    mix_sentences(sound_dir, voice, text)

    subprocess.run(
        [
            "mpv",
            "--audio-device=pulse/virtual_speaker",
            "--no-video",
            "--gapless-audio=yes",
            "--really-quiet",
            word_list_file,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


if __name__ == "__main__":
    if len(sys.argv) > 1:
        speak_text(sys.argv[1])
    else:
        print("Usage:")
        print(f'  {sys.argv[0]} "Your text here"     # Speak a single line')
        sys.exit(1)
