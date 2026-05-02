#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: ${0} <directory>"
    exit 1
fi

input_directory="$1"

directory_name="$(basename "$input_directory")"
file_list="./${directory_name}.txt"

mapfile -t files < <(
    find "$input_directory" -maxdepth 1 -type f ! -name '_*' -printf "%f\n" |
    sed 's/\.[^.]*$//' |
    # Remove numbered variants
    #sed 's/ [0-9]\+$//' |
    LC_ALL=C sort -uV
)

if [ ${#files[@]} -eq 0 ]; then
    echo "Error: No files found!"
    exit 1
fi

printf "%s\n" "${files[@]}" > "$file_list"

(
    cd "$(dirname "$input_directory")" &&
    tar -v --sort=name --owner=0 --group=0 --mtime='UTC 1970-01-01' \
    -cf - "$directory_name"
) | gzip -vn > "./${directory_name}.tar.gz"

echo "$file_list"
