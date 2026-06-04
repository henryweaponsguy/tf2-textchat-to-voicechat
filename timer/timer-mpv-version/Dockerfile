FROM debian:latest

RUN apt-get update && apt-get install -y \
    ffmpeg \
    jq \
    mpv \
    socat \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /tts


CMD ["tail", "-f", "/dev/null"]
