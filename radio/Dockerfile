FROM debian:latest

RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    build-essential \
    ffmpeg \
    git \
    inotify-tools \
    libpulse-dev \
    pulseaudio \
    python3-venv \
    unzip \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /tmp

RUN git clone --depth 1 https://github.com/dectalk/dectalk.git
WORKDIR /tmp/dectalk/src
RUN autoreconf -i && \
    ./configure && \
    make && \
    make install


WORKDIR /tts

RUN rm -rf /tmp/dectalk

RUN python3 -m venv venv
RUN venv/bin/pip install yt-dlp
RUN echo 'source /tts/venv/bin/activate' >> /root/.bashrc

CMD ["tail", "-f", "/dev/null"]
