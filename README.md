# Text chat-parsing tools for Team Fortress 2

Text chat to voice chat scripts for TF2 available in Bash and Python. Use Docker containers or check `Dockerfile` and `docker-compose.yml` files for dependencies and environment setup

---

### Available scripts

`chat-narrator` - reads text messages aloud using [Piper](https://github.com/OHF-Voice/piper1-gpl). Assigns voices to usernames so each user always sounds the same (requires downloading a voice model before running)

`chat-notifications` - plays a notification sound (from the `sounds/` directory) when a player sends a text message

`poll` - allows creating simple 'yes/no' polls (plays sound cues from the `sounds/` directory)

`radio` - allows queuing YouTube videos to be downloaded and played next. Allows voting to skip the currently playing file

`sentence-mixer` - converts text messages to speech using files from the `voices/` directory. The audio files need to have the same parameters (channel count, codec, sample rate), otherwise the output audio will come out corrupted

`soundboard` - converts valid text messages to sounds if they are available in the `sounds/` directory

`soundboard-classified` - `soundboard` modified to work with Team Fortress 2 Classified

`soundboard-windows` - `soundboard` modified to work on Windows (requires [Python](https://www.python.org) and [mpv](https://mpv.io) to be installed. Other media players, like [VLC](https://www.videolan.org/vlc) or [ffplay](https://ffmpeg.org), can be used instead of mpv)

`stt-dectalk` - converts speech to text-to-speech using [Vosk](https://alphacephei.com/vosk) and [DECtalk](https://github.com/dectalk/dectalk). Allows stopping playback early using a keyword (e.g. 'stop') (requires downloading a speech recognition model before running)

`stt-soundboard` - converts valid voice commands to sounds if they are available in the `sounds/` directory using [Vosk](https://alphacephei.com/vosk) (requires downloading a speech recognition model before running)

`timer` - starts a countdown timer (plays sound cues from the `sounds/` directory)

`tts-dectalk` - converts text messages to speech using [DECtalk](https://github.com/dectalk/dectalk) (also known as the Moonbase Alpha voice). The phoneme format works, although the maximum text message length limits it significantly

`tts-espeak` - converts text messages to speech using [eSpeak](https://github.com/espeak-ng/espeak-ng) (low quality, but lightweight and requires no setup)

`tts-piper` - converts text messages to speech using [Piper](https://github.com/OHF-Voice/piper1-gpl) (realistic voices) (requires downloading a voice model before running)

`tts-sapi4` - converts text messages to speech using [SAPI4](https://github.com/TETYYS/SAPI4) (including the BonziBUDDY and Microsoft Sam voices) (requires compiling SAPI4 before running - further instructions in the `Dockerfile`)

---

#### Get the sounds [here](https://github.com/henryweaponsguy/tf2-soundpacks)

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

`scripts/clear_console_log.sh` - truncates the `console.log` file in TF2's directory

`scripts/compress_soundpack.sh` - compresses a specified directory and creates a text file with its contents

`scripts/normalize_audio_files.sh` - normalizes the loudness of all audio files in a specified directory

`scripts/toggle_virtual_cable.sh` - creates/removes a virtual cable
