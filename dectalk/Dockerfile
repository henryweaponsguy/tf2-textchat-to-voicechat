FROM debian:latest

RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    build-essential \
    git \
    libpulse-dev \
    pulseaudio \
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


CMD ["tail", "-f", "/dev/null"]
