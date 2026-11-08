FROM debian:latest

RUN apt-get update && apt-get install -y \
    bc \
    curl \
    ffmpeg \
    inotify-tools \
    jq \
    pulseaudio \
    python3-venv \
    unzip \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /app


RUN python3 -m venv .venv
RUN /app/.venv/bin/pip install \
    piper-tts[http] \
    yt-dlp[default] \
    yt-dlp[deno]
RUN echo 'source /app/.venv/bin/activate' >> /root/.bashrc
ENV PATH="/app/.venv/bin:${PATH}"

CMD ["python3", "-m", "piper.http_server", "--data-dir", "models/", "-m", "en_US-joe-medium"]
