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


WORKDIR /tts


RUN curl -fsSL https://deno.land/install.sh | sh -s -- -y

RUN python3 -m venv venv
RUN venv/bin/pip install \
    piper-tts \
    piper-tts[http] \
    yt-dlp[default]
RUN echo 'source /tts/venv/bin/activate' >> /root/.bashrc
ENV PATH="/tts/venv/bin:${PATH}"

CMD ["python3", "-m", "piper.http_server", "--data-dir", "models/", "-m", "en_US-joe-medium"]
