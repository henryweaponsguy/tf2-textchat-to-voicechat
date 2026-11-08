#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


system_dependencies=(
    "bwrap"
    "paplay"
    "python3"
)

python_dependencies=(
    "libretranslate"
)

missing_dependencies=()
for dependency in "${system_dependencies[@]}"; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        missing_dependencies+=("$dependency")
    fi
done

if ! python3 -m venv --help >/dev/null 2>&1; then
    missing_dependencies+=("python3-venv")
fi

if (( ${#missing_dependencies[@]} )); then
    printf "%s\n" "ERROR: Missing dependencies: ${missing_dependencies[*]}"

    exit 1
fi

appdata_dir=".appdata"
venv="${script_dir}/${appdata_dir}/venv"
venv_sandboxed="/tts/${appdata_dir}/venv"

setup_options=(
    --new-session
    --die-with-parent
    --unshare-user
    --unshare-ipc
    --unshare-pid
    --unshare-uts
    --unshare-cgroup

    --proc /proc
    --dev /dev
    --tmpfs /tmp
    --ro-bind /bin /bin
    --ro-bind /lib /lib
    --ro-bind /lib64 /lib64
    --ro-bind /usr /usr
    --ro-bind /etc /etc

    --dir /app
    --chdir /app

    --bind "${HOME}/.cache/pip" "/pip-cache"
    --bind "$venv" "$venv_sandboxed"

    --setenv PIP_CACHE_DIR "/pip-cache"
)

if [[ ! -x "$venv/bin/python3" ]]; then
    printf "%s\n" "Creating a virtual environment..."

    [[ -d "$venv" ]] && rm -rf "$venv"

    mkdir -p "$venv"

    bwrap "${setup_options[@]}" "/bin/bash" -c '
        venv="$1"
        venv_pip="$venv/bin/pip"
        python_dependencies=("${@:2}")

        python3 -m venv "$venv"

        for dependency in "${python_dependencies[@]}"; do
            "$venv_pip" install "$dependency"
        done
    ' _ "$venv_sandboxed" "${python_dependencies[@]}"
fi

if [[ "${1:-}" == "update" ]]; then
    printf "%s\n" "Updating the virtual environment..."

    bwrap "${setup_options[@]}" "/bin/bash" -c '
        venv="$1"
        venv_pip="$venv/bin/pip"
        python_dependencies=("${@:2}")

        for dependency in "${python_dependencies[@]}"; do
            "$venv_pip" install --upgrade "$dependency"
        done
    ' _ "$venv_sandboxed" "${python_dependencies[@]}"
fi


tts_dependencies=(
    "piper-tts[http]"
)

venv_tts="${venv}-tts"
venv_tts_sandboxed="${venv_sandboxed}-tts"

setup_options=(
    --new-session
    --die-with-parent
    --unshare-user
    --unshare-ipc
    --unshare-pid
    --unshare-uts
    --unshare-cgroup

    --proc /proc
    --dev /dev
    --tmpfs /tmp
    --ro-bind /bin /bin
    --ro-bind /lib /lib
    --ro-bind /lib64 /lib64
    --ro-bind /usr /usr
    --ro-bind /etc /etc

    --dir /app
    --chdir /app

    --bind "${HOME}/.cache/pip" "/pip-cache"
    --bind "$venv_tts" "$venv_tts_sandboxed"

    --setenv PIP_CACHE_DIR "/pip-cache"
)

if [[ ! -x "$venv_tts/bin/python3" ]]; then
    [[ -d "$venv_tts" ]] && rm -rf "$venv_tts"

    mkdir -p "$venv_tts"

    bwrap "${setup_options[@]}" "/bin/bash" -c '
        venv="$1"
        venv_pip="$venv/bin/pip"
        python_dependencies=("${@:2}")

        python3 -m venv "$venv"

        for dependency in "${python_dependencies[@]}"; do
            "$venv_pip" install "$dependency"
        done
    ' _ "$venv_tts_sandboxed" "${tts_dependencies[@]}"

    printf "%s\n" "Virtual environment created!"
fi

if [[ "${1:-}" == "update" ]]; then
    bwrap "${setup_options[@]}" "/bin/bash" -c '
        venv="$1"
        venv_pip="$venv/bin/pip"
        python_dependencies=("${@:2}")

        for dependency in "${python_dependencies[@]}"; do
            "$venv_pip" install --upgrade "$dependency"
        done
    ' _ "$venv_tts_sandboxed" "${tts_dependencies[@]}"

    printf "%s\n" "Virtual environment updated!"

    exit
fi


mkdir -p "${script_dir}/models-translator"
mkdir -p "${script_dir}/models-tts"

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
    --ro-bind /etc/resolv.conf /etc/resolv.conf

    --dir /app
    --chdir /app

    --ro-bind "/run/user/${UID}/pulse/native" "/run/user/${UID}/pulse/native"
    --ro-bind "$venv" "$venv_sandboxed"
    --ro-bind "$venv_tts" "$venv_tts_sandboxed"
    --ro-bind "${HOME}/.steam/steam/steamapps/common/Team Fortress 2/tf/console.log" "/app/console.log"
    --ro-bind "${script_dir}/translator.py" "/app/translator.py"
    --ro-bind "${script_dir}/get_piper_voice.py" "/app/get_piper_voice.py"
    --ro-bind "${script_dir}/get_translation.py" "/app/get_translation.py"
    --bind "${script_dir}/models-translator" "/root/.local/share/argos-translate"
    --ro-bind "${script_dir}/models-tts" "/app/models-tts"

    --setenv PULSE_SERVER "unix:/run/user/${UID}/pulse/native"
    --setenv HOME "/root"
    --setenv ARGOS_CHUNK_TYPE "MINISBD"
)

exec bwrap "${runtime_options[@]}" "/bin/bash" -c '
    venv="$1"
    venv_tts="$2"
    export PATH="$venv/bin:$PATH"
bash
    libretranslate --port 5001 --load-only cs,da,de,en,es,fi,fr,hu,it,ja,ko,nl,nb,pl,pt,ro,ru,sv,tr,uk,zh >/dev/null 2>&1 &
    "$venv_tts/bin/python3" -m piper.http_server --data-dir models-tts/ -m "en_US-joe-medium" >/dev/null 2>&1 &
    "$venv/bin/python3" "/app/translator.py"
' _ "$venv_sandboxed" "$venv_tts_sandboxed"
