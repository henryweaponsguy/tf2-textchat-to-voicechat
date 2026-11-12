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

appdata_dir="${script_dir}/.appdata"
appdata_dir_sandboxed="/app/.appdata"

if [[ "${1:-}" == "install" ]]; then
    setup_dependencies=(
        "fonts-wine"
        "libwine"
        "libwine:i386"
        "nginx"
        "wine"
        "wine32"
        "wine64"
        "xvfb"
    )

    if ! command -v "dpkg" >/dev/null 2>&1; then
        printf "%s\n" "Required system dependencies: ${setup_dependencies[*]}"

        read -rp "Proceed only if they are installed [y/n] " choice
        if [[ ! "$choice" =~ ^[yY] ]]; then
            printf "%s\n" "Exiting..."

            exit 1
        fi
    else
        missing_dependencies=()
        for dependency in "${setup_dependencies[@]}"; do
            if ! dpkg -s "$dependency" >/dev/null 2>&1; then
                missing_dependencies+=("$dependency")
            fi
        done

        if (( ${#missing_dependencies[@]} )); then
            printf "%s\n" "ERROR: Missing system dependencies: ${missing_dependencies[*]}"

            exit 1
        fi
    fi

    printf "%s\n" "Installing SAPI4..."

    mkdir -p "$appdata_dir"

    if [[ ! -f "${script_dir}/SAPI4/sapi4.exe" ]] || [[ ! -f "${appdata_dir}/SAPI4/sapi4.exe" ]]; then
        printf "%s\n" "ERROR: SAPI4 is missing!"
        printf "%s\n" "$(cat << EOF
SAPI4 needs to be compiled according to https://github.com/TETYYS/SAPI4
Afterwards, place the generated files in the 'SAPI4/' directory
(only 'public/', 'libcrypto-1_1.dll', 'libssl-1_1.dll', 'sapi4.dll',
'sapi4.exe', 'sapi4limits.exe' and 'sapi4out.exe' are required)
EOF
)"

        exit 1
    fi

    if [[ -d "${script_dir}/SAPI4" ]]; then
        cp -r "${script_dir}/SAPI4" "${appdata_dir}/SAPI4"
    fi

    if [[ ! -f "${script_dir}/installers/spchapi.exe" ]] || [[ ! -f "${script_dir}/installers/tv_enua.exe" ]]; then
        printf "%s\n" "Place the 'spchapi.exe' and 'tv_enua.exe' files in the 'installers/' directory"
        printf "%s\n" "The files can be found in https://github.com/TETYYS/SAPI4"
        printf "%s\n" "These installers will install the Lernout & Hauspie TruVoice voices"

        exit 1
    fi

    if [[ ! -f "${script_dir}/installers/msttsl.exe" ]]; then
        printf "%s\n" "'msttsl.exe' file not found. For the Microsoft Mary, Mike and Sam voices 'msttsl.exe' is required too"
        printf "%s\n" "SHA256 for 'msttsl.exe': c87f9a489e53d250cb4ed5574af243c35db1a859e2a266e2d9d0d3b241513d5e"

        read -rp "Proceed anyway? [y/n] " choice
        if [[ ! "$choice" =~ ^[yY] ]]; then
            printf "%s\n" "Exiting..."

            exit 1
        fi
    fi

    if [[ -d "${script_dir}/installers" ]]; then
        cp -r "${script_dir}/installers" "${appdata_dir}/installers"
    fi

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

        --ro-bind "/tmp/.X11-unix" "/tmp/.X11-unix"
        --bind "$appdata_dir" "$appdata_dir_sandboxed"

        --setenv DISPLAY "$DISPLAY"
        --setenv WINEPREFIX "${appdata_dir_sandboxed}/wine"
    )

    bwrap "${setup_options[@]}" "/bin/bash" -c '
        appdata_dir="$1"

        wineboot
        winecfg -v
        winetricks ole32

        wine "${appdata_dir}/installers/spchapi.exe" /Q
        wine "${appdata_dir}/installers/tv_enua.exe" /Q

        if [[ -f "${appdata_dir}/installers/msttsl.exe" ]]; then
            wine "${appdata_dir}/installers/msttsl.exe" /Q
        fi
    ' _ "$appdata_dir_sandboxed"

    printf "%s\n" "SAPI4 server installed!"

    exit
fi

if [[ ! -f "${appdata_dir}/SAPI4/sapi4.exe" ]] || [[ ! -d "${appdata_dir}/wine/drive_c" ]]; then
    printf "%s\n" "ERROR: the SAPI4 server is missing!"
    printf "%s\n" "To install the SAPI4 server run: ${0} install"

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
    --ro-bind "$appdata_dir" "$appdata_dir_sandboxed"
    --ro-bind "${HOME}/.steam/steam/steamapps/common/Team Fortress 2/tf/console.log" "/app/console.log"
    --ro-bind "${script_dir}/text_to_speech.py" "/app/text_to_speech.py"
    --ro-bind "${script_dir}/get_sapi4_voice.py" "/app/get_sapi4_voice.py"
    --ro-bind "${script_dir}/nginx.conf" "/etc/nginx/nginx.conf"

    --setenv PULSE_SERVER "unix:/run/user/${UID}/pulse/native"
    --setenv WINEPREFIX "${appdata_dir_sandboxed}/wine"
)

exec bwrap "${runtime_options[@]}" "/bin/bash" -c '
    appdata_dir="$1"
    export PATH="${appdata_dir}:$PATH"

    cd "${appdata_dir}/SAPI4"

    while true; do xvfb-run -a wine sapi4.exe; sleep 1; done & nginx -g "daemon off;" &
    "/usr/bin/python3" "/app/text_to_speech.py"
' _ "$appdata_dir_sandboxed"
