FROM debian:latest

RUN apt-get update && apt-get install -y \
    pulseaudio \
    python3-pyaudio \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /tts

RUN python3 -m venv venv
RUN venv/bin/pip install \
    piper-tts \
    piper-tts[http] \
    sounddevice \
    vosk
RUN echo 'source /tts/venv/bin/activate' >> /root/.bashrc
ENV PATH="/tts/venv/bin:${PATH}"


CMD ["python3", "-m", "piper.http_server", "--data-dir", "models-tts/", "-m", "en_US-joe-medium"]
