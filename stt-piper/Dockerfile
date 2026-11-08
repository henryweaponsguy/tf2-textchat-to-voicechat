FROM debian:latest

RUN apt-get update && apt-get install -y \
    pulseaudio \
    python3-pyaudio \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /app

RUN python3 -m venv .venv
RUN /app/.venv/bin/pip install \
    piper-tts[http] \
    sounddevice \
    vosk
RUN echo 'source /app/.venv/bin/activate' >> /root/.bashrc
ENV PATH="/app/.venv/bin:${PATH}"


CMD ["python3", "-m", "piper.http_server", "--data-dir", "models-tts/", "-m", "en_US-joe-medium"]
