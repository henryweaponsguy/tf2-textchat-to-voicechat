FROM debian:latest

RUN apt-get update && apt-get install -y \
    mpv \
    python3 \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /app


CMD ["tail", "-f", "/dev/null"]
