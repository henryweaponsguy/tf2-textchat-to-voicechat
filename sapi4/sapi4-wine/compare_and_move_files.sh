#!/bin/bash

# Declare associative arrays
declare -A before_map
declare -A after_map

# Read the first argument into before_map
while IFS= read -r line; do
    hash="$(cut -d' ' -f1 <<< "$line")"
    path="$(cut -d' ' -f2- <<< "$line" | sed 's/^ *//')"
    before_map["$path"]="$hash"
done < "$2"

# Read the third argument into after_map
while IFS= read -r line; do
    hash="$(cut -d' ' -f1 <<< "$line")"
    path="$(cut -d' ' -f2- <<< "$line" | sed 's/^ *//')"
    after_map["$path"]="$hash"
done < "$3"

# Target directory
mkdir -p "$1"

# Compare and move new or modified files
for path in "${!after_map[@]}"; do
    new_hash="${after_map[$path]}"
    old_hash="${before_map[$path]}"

    # Check if a file is new or modified
    if [[ -z "$old_hash" || "$new_hash" != "$old_hash" ]]; then
        if [[ -f "$path" ]]; then
            cp --parents "$path" "$1"
        else
            echo "Warning: File not found: $path"
        fi
    fi
done
