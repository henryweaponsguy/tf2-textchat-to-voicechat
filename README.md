# Text chat scripts for Team Fortress 2

Text chat/voice chat scripts for TF2 available in Python and Bash. Run the scripts in a Bubblewrap sandbox, use (rootless) Docker containers or check `Dockerfile` and `docker-compose.yml` files for dependencies and manual environment setup

---

## Available scripts

`fortune` - reads a random fortune cookie fortune (from the `fortunes.txt` file) aloud[^2]

`kill-announcer` - reads a custom message aloud when a target player dies[^2]

`kill-sound` - plays a sound when a target player dies[^1]

`narrator` - reads text messages aloud. Assigns voices to usernames so each user always sounds the same[^2]

`notifications` - plays a notification sound when a player sends a text message[^1]

`poll` - allows creating simple 'yes/no' polls[^1] [^2]

`radio` - allows queuing YouTube videos to be downloaded and played next. Allows voting to skip the currently playing video (uses [yt-dlp](https://github.com/yt-dlp/yt-dlp) for downloading videos and [ffmpeg](https://ffmpeg.org) for audio normalization)[^1] [^4]

`radio-browser` - `radio` modified to play videos directly in a web browser instead of downloading them (dedicated software for audio normalization is recommended, e.g. [master_me](https://github.com/trummerschlunk/master_me) or [LSP Autogain](https://lsp-plug.in/?page=manuals&section=autogain_stereo); config files for [Carla](https://kx.studio/Applications:Carla) are provided)[^1] [^4]

`requests` - logs requests to console for easier tracking (e.g. for music requests). Converts YouTube URLs to titles automatically

`sentence-mixer` - converts text messages to speech using files from the `voices/` directory. The audio files need to have the same parameters (channel count, codec, sample rate), otherwise the output audio will come out corrupted[^1]

`soundboard` - converts valid text messages to sounds from the `sounds/` directory[^1]

`soundboard-classified` - `soundboard` modified to work with Team Fortress 2 Classified[^1]

`soundboard-windows` - `soundboard` modified to work on Windows (requires [Python](https://www.python.org) and [mpv](https://mpv.io) to be installed. Other media players, like [VLC](https://www.videolan.org/vlc) or [ffplay](https://ffmpeg.org), can be used instead of mpv)[^1]

`stt-piper` - converts speech to text-to-speech (Piper). Allows stopping playback early using a keyword (e.g. 'stop')[^2] [^3]

`stt-soundboard` - converts valid voice commands to sounds from the the `sounds/` directory[^1] [^3]

`stt-text` - converts speech to text chat messages[^3] [^4]

`timer` - starts a countdown timer[^1]

`translator` - translates text messages to English (requires downloading a translation model before running)[^2]

`tts-dectalk` - converts text messages to speech using [DECtalk](https://github.com/dectalk/dectalk) (also known as the Moonbase Alpha voice). The phoneme format works, although the maximum text message length limits it significantly

`tts-espeak` - converts text messages to speech using [eSpeak](https://github.com/espeak-ng/espeak-ng) (low quality, but lightweight and requires no setup)

`tts-piper` - converts text messages to speech using [Piper](https://github.com/OHF-Voice/piper1-gpl) (realistic voices)[^2]

`tts-sapi4` - converts text messages to speech using [SAPI4](https://github.com/TETYYS/SAPI4) (including the BonziBUDDY and Microsoft Sam voices) (if using Docker containers, check the instructions in the `Dockerfile`)

[^1]: Plays sound cues from the `sounds/` directory. Get the sounds [here](https://github.com/henryweaponsguy/tf2-soundpacks)

[^2]: Uses a TTS engine, [Piper](https://github.com/OHF-Voice/piper1-gpl); requires downloading a voice model before running

[^3]: Uses a speech recognition engine, [Vosk](https://alphacephei.com/vosk); requires downloading a speech recognition model before running

[^4]: Requires setting up [text chat logging](#toggleable-text-chat-logging)

---

## How to run

Add `-condebug` to TF2's launch parameters. Alternatively, add `con_logfile <logfile location, e.g. console.log>` to TF2's `autoexec.cfg`

Run TF2 at least once before starting a script/container so the `console.log` file is created

#### Bubblewrap sandbox

Start a script: `./run.sh`

Update Python dependencies: `./run.sh update`

#### Docker containers

Start a container: `export UID=$(id -u); docker compose up -d`

Run a script in the container: `docker exec -it <container name, e.g. tf2-soundboard> python '/app/<script name, e.g. soundboard.py>'`

Or to run a Bash script: `docker exec -it <container name, e.g. tf2-soundboard> '/app/<script name, e.g. soundboard.sh>'`

Stop the container: `docker compose down`

Rebuild a container to update dependencies: `export UID=$(id -u); docker compose build`

### Toggleable text chat logging

Create a `message.cfg` file next to TF2's `autoexec.cfg` file and add this to TF2's `autoexec.cfg`:

```
alias message_loop_key start_message_loop
alias start_message_loop "echo ==================== MESSAGES ENABLED ====================;echo text_message_sent;alias message_loop_key stop_message_loop;alias redirect_message_loop run_message_loop;run_message_loop"
alias stop_message_loop "echo ==================== MESSAGES DISABLED ====================;alias redirect_message_loop;alias message_loop_key start_message_loop"
alias message_loop_command "exec overrides/message.cfg"
alias run_message_loop "message_loop_command;wait 500;redirect_message_loop"
bind "p" message_loop_key
```

If `message.cfg` is not in `tf/cfg/overrides/`, adjust the script above and the paths in `run.sh`/`docker-compose.yml` to the file's actual location

The actual duration of the `wait` command depends on the server's tickrate and the client's framerate. Check [this](https://wiki.teamfortress.com/wiki/Scripting#wait) for the formula

---

## Extra tips

### Toggleable voice chat with voice loopback (so you can hear your music)

Add this to TF2's `autoexec.cfg`:

```
alias voice_toggle "voice_on"
alias voice_on "+voicerecord; voice_loopback 1; alias voice_toggle voice_off"
alias voice_off "-voicerecord; voice_loopback 0; alias voice_toggle voice_on"
bind "ALT" "voice_toggle"
```

### Better music quality

For better playback quality turn off these options as they may introduce distortion to your music:

Go into `Steam > Settings > Voice` and set `Voice Transmission Threshold` to `Off`, then scroll down and open `Advanced Options` and disable all of them (`Echo cancelation`, `Noise cancelation`, `Automatic volume/gain control`)

Additionally, while you are in the Voice Settings, set `Voice Input Device` to your virtual cable as TF2 may not recognize it otherwise

### Helpful scripts

`scripts/clear_console_log.sh` - truncates the `console.log` file in TF2's directory

`scripts/compress_soundpack.sh` - compresses a specified directory and creates a text file with its contents

`scripts/normalize_audio_files.sh` - normalizes the loudness of all audio files in a specified directory

`scripts/toggle_virtual_cable.sh` - creates/removes a virtual cable
