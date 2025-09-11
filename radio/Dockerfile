FROM debian:latest

RUN apt-get update && apt-get install -y \
    ffmpeg \
    inotify-tools \
    pulseaudio \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /tts

RUN python3 -m venv venv
RUN venv/bin/pip install yt-dlp
RUN echo 'source /tts/venv/bin/activate' >> /root/.bashrc

CMD ["tail", "-f", "/dev/null"]
