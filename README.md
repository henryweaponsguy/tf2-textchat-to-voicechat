# Text chat-parsing tools for Team Fortress 2

Text chat to voice chat scripts for TF2 available in Bash and Python. Use Docker containers or check `Dockerfile` and `docker-compose.yml` files for dependencies and environment setup

---

### Available scripts

`chat-notifications` - plays a notification sound (from the `sounds/` directory) when a player sends a text message. Get the sounds [here](https://github.com/henryweaponsguy/tf2-soundpacks)

`poll` - allows creating simple 'yes/no' polls

`radio` - allows queuing YouTube videos to be downloaded and played next. Allows voting to skip the currently playing file

`sentence-mixer` - converts text messages to speech using files in the `sounds/` directory. The audio files need to have the same parameters (channel count, codec, sample rate), otherwise the output audio will come out corrupted. Get the sounds [here](https://github.com/henryweaponsguy/tf2-soundpacks)

`soundboard` - converts valid text messages to sounds if they are available in the `sounds/` directory (also includes `soundbutton` that plays a random sound from the `sounds/` directory). Get the sounds [here](https://github.com/henryweaponsguy/tf2-soundpacks)

`soundboard-classified` - `soundboard` modified to work with Team Fortress 2 Classified

`soundboard-windows` - `soundboard` modified to work on Windows (requires Python to be installed and [ffplay](https://ffmpeg.org) to be added to `PATH`. Other media players, like [mpv](https://mpv.io) or [VLC](https://www.videolan.org/vlc), can be used instead of ffplay)

`stt-dectalk` - converts speech to text-to-speech using DECtalk. Allows stopping playback early using a keyword (e.g. 'stop') (requires downloading a speech recognition model before running the container - further instructions in the script file)

`stt-soundboard` - converts valid voice commands to sounds if they are available in the `sounds/` directory (requires downloading a speech recognition model before running the container - further instructions in the script file). Get the sounds [here](https://github.com/henryweaponsguy/tf2-soundpacks)

`tts-dectalk` - converts text messages to speech using DECtalk (also known as the Moonbase Alpha voice). The phoneme format works, although the maximum text message length limits it significantly

`tts-espeak` - converts text messages to speech using eSpeak

`tts-sapi4` - converts text messages to speech using SAPI4 (including the BonziBUDDY and Microsoft Sam voices) (requires compiling SAPI4 before running the container - further instructions in the `Dockerfile`)

---

### How to run

Add `-condebug` to TF2's launch parameters. Alternatively, add `con_logfile <logfile location>` to TF2's `autoexec.cfg`, e.g. `con_logfile console.log`

Run TF2 at least once before starting a container so the `console.log` file is created

Build and run the container: `export UID=$(id -u); docker compose up -d`

Run the script in the container: `docker exec -it <container name, e.g. tf2-dectalk> '/tts/<script name, e.g. chat_to_speech.sh>'`

Stop the container: `docker compose down`

---

### Extra tips

#### Toggleable voice chat with voice loopback (so you can hear your music)

Add this to TF2's `autoexec.cfg`:

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

`scripts/compress_soundpack.sh` - compresses a specified directory and creates a text file with its contents

`scripts/normalize_audio_files.sh` - normalizes the loudness of all audio files in a specified directory

`scripts/toggle_virtual_cable.sh` - creates/removes a virtual cable
