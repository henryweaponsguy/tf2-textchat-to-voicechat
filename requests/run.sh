#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


system_dependencies=(
    "bwrap"
    "paplay"
    "python3"
)

python_dependencies=(
    "yt-dlp[default]"
    "yt-dlp[deno]"
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

venv="${script_dir}/.appdata"
venv_sandboxed="/app/.appdata"

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

    printf "%s\n" "Virtual environment created!"
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

    printf "%s\n" "Virtual environment updated!"

    exit
fi


runtime_options=(
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
    --ro-bind /etc/alternatives /etc/alternatives
    --ro-bind /etc/resolv.conf /etc/resolv.conf

    --dir /app
    --chdir /app

    --ro-bind "/run/user/${UID}/pulse/native" "/run/user/${UID}/pulse/native"
    --ro-bind "$venv" "$venv_sandboxed"
    --ro-bind "${HOME}/.steam/steam/steamapps/common/Team Fortress 2/tf/console.log" "/app/console.log"
    --ro-bind "${script_dir}/requests.py" "/app/requests.py"

    --setenv PULSE_SERVER "unix:/run/user/${UID}/pulse/native"
)

exec bwrap "${runtime_options[@]}" "/bin/bash" -c '
    venv="$1"
    export PATH="$venv/bin:$PATH"

    "$venv/bin/python3" "/app/requests.py"
' _ "$venv_sandboxed"
