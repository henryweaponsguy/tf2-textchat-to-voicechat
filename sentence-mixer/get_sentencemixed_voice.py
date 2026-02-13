import random
import re
import signal
import subprocess
import sys
import tempfile
from pathlib import Path
from convert_numbers_to_words import convert_numbers_to_words

# Exit cleanly on CTRL+C and system shutdown
signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))


sound_dir = "/tts/sounds"


word_list_file = "/tts/word_list.txt"

if not Path(word_list_file).exists():
    Path(word_list_file).touch()

word_list = []

re_numbers = re.compile(rf"^-?[0-9]+(st|nd|rd|th)?$", re.IGNORECASE)

suffix_patterns = [
    re.compile(r"^(.*)(ing)$"),
    re.compile(r"^(.*)(e[sd])$"),
    re.compile(r"^(.*)([esd]|'s)$"),
]

default_dictionary = [
    (re.compile(r"_"), " "),
    (re.compile(r"(,|;|=)"), " _comma "),
    (re.compile(r"-([^0-9])"), r" _comma \1"),
    (re.compile(r"[.!?]"), " _period "),
    (re.compile(r"(&|\+)"), " and "),
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

# Import a custom dictionary
custom_dictionary_file = f"{sound_dir}/_dictionary.sed"
custom_dictionary = []

if Path(custom_dictionary_file).exists():
    with open(custom_dictionary_file) as dictionary:
        for line in dictionary:
            line = line.strip()
            if not line or not line.startswith("s/"):
                continue

            # Split the rule into s, pattern, replacement, flags
            _, pattern, replacement, flags = line.split("/")

            custom_dictionary.append((re.compile
                (pattern, re.IGNORECASE if "i" in flags else 0),
                replacement,
            ))

def apply_dictionary(words, dictionary):
    new_words = []

    for word in words:
        for pattern, replacement in dictionary:
            word = pattern.sub(replacement, word)

        new_words.extend(word.split())

    return new_words

def mix_sentences(text, audio_file):
    words = text.split()

    for i, word in enumerate(words):
        # Convert numbers to words
        if re_numbers.match(word):
            words[i] = convert_numbers_to_words(word)

    # Check if a custom dictionary is available
    if custom_dictionary:
        # Replace synonyms and unavailable forms of words with existing words
        words = apply_dictionary(words, custom_dictionary)

        for word in words:
            selected_file=""

            # Check for unnumbered and numbered variants
            matched_files = (
                list(Path(sound_dir).glob(f"{word}.wav")) +
                list(Path(sound_dir).glob(f"{word} [0-9]*.wav"))
            )

            if matched_files:
                selected_file = str(random.choice(matched_files))
            else:
                # If a corresponding file does not exist, use a placeholder file
                selected_file=f"{sound_dir}/_placeholder.wav"

            word_list.append(f"file '{selected_file}'")
    else:
        words = apply_dictionary(words, default_dictionary)

        for word in words:
            selected_file=""

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
                matched_files = (
                    list(Path(sound_dir).glob(f"{variant}.wav")) +
                    list(Path(sound_dir).glob(f"{variant} [0-9]*.wav"))
                )

                if matched_files:
                    selected_file = str(random.choice(matched_files))
                    break

            # If a corresponding file does not exist, use a placeholder file
            if not selected_file:
                selected_file=f"{sound_dir}/_placeholder.wav"

            word_list.append(f"file '{selected_file}'")

    if word_list:
        # Add silence at the end, otherwise the sound may be cut off too early
        #word_list.append(f"file '{sound_dir}/_period.wav'")

        with open(word_list_file, "w") as file:
            file.writelines(f"{line}\n" for line in word_list)

        subprocess.run([
            "ffmpeg",
            "-hide_banner",
            "-loglevel", "error",
            "-f", "concat",
            "-safe", "0",
            "-i", word_list_file,
            "-ar", "22050",
            "-ac", "1",
            "-c", "copy",
            "-y", audio_file,
        ])

def speak_text(text):
    if not text:
        return

    with tempfile.NamedTemporaryFile(prefix="sentencemixed_voice-", suffix=".wav", delete=False) as tmp:
        audio_file = tmp.name

    try:
        mix_sentences(text, audio_file)

        subprocess.run(
            ["paplay", "--client-name=sentence-mixer", audio_file],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    finally:
        try:
            Path(audio_file).unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    if len(sys.argv) > 1:
        speak_text(sys.argv[1])
    else:
        print("Usage:")
        print(f"  {sys.argv[0]} \"Your text here\"     # Speak a single line")
        sys.exit(1)
