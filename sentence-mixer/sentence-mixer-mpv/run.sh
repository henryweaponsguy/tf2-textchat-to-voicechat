#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


system_dependencies=(
    "bwrap"
    "mpv"
    "python3"
)

missing_dependencies=()
for dependency in "${system_dependencies[@]}"; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        missing_dependencies+=("$dependency")
    fi
done

if (( ${#missing_dependencies[@]} )); then
    printf "%s\n" "ERROR: Missing system dependencies: ${missing_dependencies[*]}"

    exit 1
fi


mkdir -p "${script_dir}/voices"

runtime_options=(
    --new-session
    --die-with-parent
    --unshare-user
    --unshare-ipc
    --unshare-pid
    --unshare-uts
    --unshare-cgroup
    --unshare-net

    --proc /proc
    --dev /dev
    --tmpfs /tmp
    --ro-bind /bin /bin
    --ro-bind /lib /lib
    --ro-bind /lib64 /lib64
    --ro-bind /usr /usr
    --ro-bind /etc/alternatives /etc/alternatives

    --dir /app
    --chdir /app

    --ro-bind "/run/user/${UID}/pulse/native" "/run/user/${UID}/pulse/native"
    --ro-bind "${HOME}/.steam/steam/steamapps/common/Team Fortress 2/tf/console.log" "/app/console.log"
    --ro-bind "${script_dir}/sentence_mixer.py" "/app/sentence_mixer.py"
    --ro-bind "${script_dir}/convert_numbers_to_words.py" "/app/convert_numbers_to_words.py"
    --ro-bind "${script_dir}/get_sentencemixed_voice.py" "/app/get_sentencemixed_voice.py"
    --ro-bind "${script_dir}/voices" "/app/voices"

    --setenv PULSE_SERVER "unix:/run/user/${UID}/pulse/native"
)

exec bwrap "${runtime_options[@]}" "/usr/bin/python3" "/app/sentence_mixer.py"
