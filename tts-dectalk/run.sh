#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


system_dependencies=(
    "bwrap"
    "paplay"
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

dectalk_dir="${script_dir}/.appdata"
dectalk_dir_sandboxed="/app/.appdata"

if [[ "${1:-}" == "install" ]]; then
    setup_dependencies=(
        "autoconf"
        "automake"
        "build-essential"
        "git"
        "libpulse-dev"
        "unzip"
    )

    missing_dependencies=()
    for dependency in "${setup_dependencies[@]}"; do
        if ! dpkg -s "$dependency" >/dev/null 2>&1; then
            missing_dependencies+=("$dependency")
        fi
    done

    if (( ${#missing_dependencies[@]} )); then
        printf "%s\n" "ERROR: Missing system dependencies: ${missing_dependencies[*]}"
        printf "%s\n" "These dependencies may be removed after DECtalk is installed"

        exit 1
    fi

    printf "%s\n" "Installing DECtalk..."

    mkdir -p "$dectalk_dir"

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

        --bind "$dectalk_dir" "$dectalk_dir_sandboxed"
    )

    bwrap "${setup_options[@]}" "/bin/bash" -c '
        dectalk_dir="$1"

        cd /tmp
        git clone --depth 1 https://github.com/dectalk/dectalk.git
        cd /tmp/dectalk/src

        autoreconf -i && \
            ./configure --prefix="$dectalk_dir" && \
            make -j && \
            make install
    ' _ "$dectalk_dir_sandboxed"

    printf "%s\n" "DECtalk installed!"

    exit
fi

if ! command -v "say" >/dev/null 2>&1 && [[ ! -x "$dectalk_dir/say" ]]; then
    printf "%s\n" "ERROR: DECtalk is missing!"
    printf "%s\n" "To install DECtalk run: ${0} install"

    exit 1
fi


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
    --ro-bind "$dectalk_dir" "$dectalk_dir_sandboxed"
    --ro-bind "${HOME}/.steam/steam/steamapps/common/Team Fortress 2/tf/console.log" "/app/console.log"
    --ro-bind "${script_dir}/text_to_speech.py" "/app/text_to_speech.py"
    --ro-bind "${script_dir}/get_dectalk_voice.py" "/app/get_dectalk_voice.py"

    --setenv PULSE_SERVER "unix:/run/user/${UID}/pulse/native"
)

exec bwrap "${runtime_options[@]}" "/bin/bash" -c '
    dectalk_dir="$1"
    export PATH="$dectalk_dir:$PATH"

    "/usr/bin/python3" "/app/text_to_speech.py"
' _ "$dectalk_dir_sandboxed"
