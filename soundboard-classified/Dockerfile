FROM debian:latest

RUN apt-get update && apt-get install -y \
    pulseaudio \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /tts


CMD ["tail", "-f", "/dev/null"]
