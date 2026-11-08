FROM debian:latest

RUN apt-get update && apt-get install -y \
    bc \
    curl \
    jq \
    pulseaudio \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /app

RUN python3 -m venv .venv
RUN /app/.venv/bin/pip install \
    libretranslate
RUN echo 'source /app/.venv/bin/activate' >> /root/.bashrc
ENV PATH="/app/.venv/bin:${PATH}"

ENV ARGOS_CHUNK_TYPE=MINISBD


EXPOSE 5001

CMD ["libretranslate", "--host", "0.0.0.0", "--port", "5001", "--load-only", "cs,da,de,en,es,fi,fr,hu,it,ja,ko,nl,nb,pl,pt,ro,ru,sv,tr,uk,zh"]
