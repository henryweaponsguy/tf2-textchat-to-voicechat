FROM debian:latest

RUN dpkg --add-architecture i386

RUN apt-get update && apt-get install -y \
    curl \
    fonts-wine \
    jq \
    libwine \
    libwine:i386 \
    nginx \
    pulseaudio \
    wine \
    wine32 \
    wine64 \
    xvfb \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /tts
# SAPI4 needs to be compiled according to https://github.com/TETYYS/SAPI4
# Afterwards, the generated files need to be copied to a separate 'SAPI4/' directory
# (only 'public/', 'libcrypto-1_1.dll', 'libssl-1_1.dll', 'sapi4.dll',
# 'sapi4.exe', 'sapi4limits.exe', 'sapi4out.exe' are required)
COPY SAPI4.tar.gz .
RUN tar --no-same-permissions -xzf SAPI4.tar.gz && rm SAPI4.tar.gz

WORKDIR /root
RUN winecfg -v

# Put the following installers in the 'sapi4-wine/' directory:
# 'spchapi.exe' and 'tv_enua.exe' can be found in https://github.com/TETYYS/SAPI4
# These installers will install the Lernout & Hauspie TruVoice voices.
# For the Microsoft Mary, Mike and Sam voices 'msttsl.exe' needs to be run.
# SHA256 for 'msttsl.exe': c87f9a489e53d250cb4ed5574af243c35db1a859e2a266e2d9d0d3b241513d5e
# Afterwards, go to 'sapi4-wine/', run 'create_archive.sh' and copy 'wine.tar.gz' from 'sapi4-wine/out/'.
# It is safe to delete the 'sapi4-wine' container image if 'wine.tar.gz' contains these files:
# 'system.reg'
# 'drive_c/windows/Fonts/andmoipa.ttf'
# 'drive_c/windows/inf/spchapi.inf',
# 'drive_c/windows/inf/tv_enua.inf'
# 'drive_c/windows/lhsp/'
# 'drive_c/windows/speech/',
# 'drive_c/windows/syswow64/msvcirt.dll'
# 'drive_c/windows/syswow64/msvcp50.dll',
# 'drive_c/windows/syswow64/msvcrt.dll'
# 'msttsl.exe' specific files:
# 'drive_c/windows/inf/msTTS.inf'
# 'drive_c/windows/delttsul.exe'
# 'drive_c/Program Files (x86)/Common Files/microsoft shared'
COPY wine.tar.gz .
RUN tar --no-same-permissions -xzf wine.tar.gz && rm wine.tar.gz


COPY nginx.conf /etc/nginx/nginx.conf

WORKDIR /tts/SAPI4


EXPOSE 5491

CMD bash -c "while true; do xvfb-run -a wine sapi4.exe; sleep 1; done & nginx -g 'daemon off;'"
