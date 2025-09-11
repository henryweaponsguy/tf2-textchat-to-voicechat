FROM debian:latest

RUN sed -i 's/main/main contrib non-free/' /etc/apt/sources.list.d/debian.sources

RUN dpkg --add-architecture i386

RUN apt-get update && apt-get install -y \
    curl \
    fonts-wine \
    jq \
    libwine \
    libwine:i386 \
    wine \
    wine32 \
    wine64 \
    winetricks \
    && rm -rf /var/lib/apt/lists/*


RUN winetricks ole32
RUN export WINEPREFIX=/root/.wine && wineboot && winecfg -v


COPY spchapi.exe tv_enua.exe msttsl.exe /root

COPY compare_and_move_files.sh /root


CMD ["tail", "-f", "/dev/null"]
