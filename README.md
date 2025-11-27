# Text chat-parsing tools for Team Fortress 2

This repo contains a couple text chat to voice chat scripts for TF2. These scripts were written with the intention of running them in Docker containers, but it should be possible to simply run the `.sh` files on bare metal (provided all dependencies are met and file paths are altered). It may even be possible to run them on Windows as long as you have [Bash](https://git-scm.com/downloads/win) installed, but this has not been tested

---

### Available scripts

`dectalk` - converts text messages to speech using DECtalk (also known as the Moonbase Alpha voice). The phoneme format works, although the maximum text message length limits it significantly

`espeak` - converts text messages to speech using eSpeak (the easiest TTS engine to setup, no compilation required)

`radio` - allows queuing YouTube videos to be downloaded and played next

`sapi4` - converts text messages to speech using SAPI4 (including the BonziBUDDY and Microsoft Sam voices, requires compiling SAPI4 before running the container - further instructions in the Dockerfile)

`sentence-mixer` - converts text messages to speech using files in the `sounds/` directory. The audio files need to have the same parameters (channel count, codec, sample rate), otherwise the output audio will come out corrupted

`soundboard` - converts valid text messages to sounds if they are available in the `sounds/` directory (also includes `soundbutton` that plays a random sound from the `sounds/` directory)

---

### How to run

Build and run the container: `export UID=$(id -u); docker compose up -d`

Enter the container: `docker exec -it <container name, e.g. tf2-dectalk> bash`

While in the container run: `/tts/<script name, e.g. chat_to_speech.sh>`

Stop the container: `docker compose down`

---

### Extra tips

#### Toggleable voice chat with voice loopback (so you can hear your music)

Add this to your `autoexec.cfg`:

```
alias voice_toggle "voice_on"
alias voice_on "+voicerecord; voice_loopback 1; alias voice_toggle voice_off"
alias voice_off "-voicerecord; voice_loopback 0; alias voice_toggle voice_on"
bind "ALT" "voice_toggle"
```

#### Better music quality

For better playback quality turn off these options as they may introduce distortion to your music:

Go into `Steam > Settings > Voice` and set `Voice Transmission Threshold` to `Off`, then scroll down and open `Advanced Options` and disable all of them (`Echo cancelation`, `Noise cancelation`, `Automatic volume/gain control`)

Additionally, while you are in the Voice Settings, set `Voice Input Device` to your virtual cable as TF2 may not recognize it otherwise

#### Helpful scripts

`scripts/clean_console_log.sh` - truncates the `console.log` file in TF2's directory

`scripts/create_virtual_cable.sh` - creates a virtual cable
