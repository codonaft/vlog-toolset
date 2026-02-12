# vlog-toolset
Video and audio recording toolset for vloggers🎙️📹🎬

Designed to record vlogs with classical jump cuts
using camera of Android-based device and microphone of GNU/Linux machine.
I [use it](https://alopatindev.github.io/2019/02/05/video-recording-with-automatic-jump-cuts-using-open-source-and-coding/) with Kdenlive for my [YouTube channel](https://www.youtube.com/@codonaft).

Currently can keep functioning well even if you experience temporary [USB phone connection failure](https://android.stackexchange.com/questions/193637/how-can-i-adb-pull-a-large-file-when-the-usb-connection-breaks-continuously).

Two possible workflows:
- record with `vlog-record`, apply `vlog-render`
- record normally, without any additional software, apply `vlog-add` and `vlog-render`

## Installation

### GNU/Linux
1. Install dependencies
- ruby (tested with 3.1.4)
- python3 (tested with 3.11.8)
- pip (tested with 24)
- ffmpeg (tested with 6.1.1)
- sox (tested with 14.4.2)
- mediainfo (tested with 23.04)
- [sync-audio-tracks](https://github.com/alopatindev/sync-audio-tracks) (should be in your PATH environment variable)
- alsa-utils (tested with 1.2.10)
- xdotool (tested with 3.20211022.1)
- socat (tested with 1.7.4.4)
- mpv (tested with 0.37.0)
- whisper.cpp (tested with `641f2f4`)
    - build for
        - [NVIDIA proprietary](https://github.com/ggerganov/whisper.cpp/tree/641f2f42823affb6e5c471b63317deefb0b6e3e9#nvidia-gpu-support) driver
        - or [other GPUs](https://github.com/ggerganov/whisper.cpp/tree/641f2f42823affb6e5c471b63317deefb0b6e3e9#opencl-gpu-support-via-clblast)
        - or [CPU](https://github.com/ggerganov/whisper.cpp/tree/641f2f42823affb6e5c471b63317deefb0b6e3e9#blas-cpu-support-via-openblas)
    - download [model(s)](https://github.com/ggerganov/whisper.cpp/tree/641f2f42823affb6e5c471b63317deefb0b6e3e9#quick-start) (`base` and/or `medium` are recommended)
- android-tools (tested with 34.0.1, adb version is 1.0.41)
    - USB Debugging should be [enabled](https://github.com/alopatindev/qdevicemonitor/blob/master/TROUBLESHOOTING.md#android-devices-are-not-recognized)

2. `git clone git@github.com:alopatindev/vlog-toolset.git && cd vlog-toolset && ./configure`

3. Recommended configuration
```ini
# ~/.config/mpv/mpv.conf

af=scaletempo2
volume=90
volume-max=300
```

```ini
# ~/.config/mpv/input.conf

RIGHT seek 1 exact
LEFT seek -1 exact

n playlist-next                        # skip to next file
ENTER playlist-next                    # skip to next file
b playlist-prev                        # skip to previous file

х multiply speed 1/1.1                 # scale playback speed
ъ multiply speed 1.1
ALT+z multiply speed 1/1.1
ALT+x multiply speed 1.1
ALT+c set speed 1.0

Ю playlist-next                        # skip to next file
Б playlist-prev                        # skip to previous file

CTRL+SHIFT+< add chapter -1 ; script-message osc-chapterlist 6
CTRL+SHIFT+> add chapter 1 ; script-message osc-chapterlist 6
CTRL+SHIFT+Б add chapter -1 ; script-message osc-chapterlist 6
CTRL+SHIFT+Ю add chapter 1 ; script-message osc-chapterlist 6
CTRL+SHIFT+/ script-message osc-chapterlist 6
CTRL+SHIFT+p script-message osc-chapterlist 6

ESC cycle pause
```

### Android device
- Open Camera (from [F-Droid](https://f-droid.org/en/packages/net.sourceforge.opencamera/) or [Google Play](https://play.google.com/store/apps/details?id=net.sourceforge.opencamera)) (tested with 1.51.1)

## vlog-record
- records video
    - using camera of Android-based device
- records audio
    - using microphone, connected to GNU/Linux machine
- detects voice (to trim silence)
    - if you save clip without auto trimming — it will just remove beginning and ending of each clip
        - which typically contain the button click sound
- synchronizes audio
- combines stuff together to produce MP4 video clips
    - which contain
        - H.265/HVEC video taken from camera
        - FLAC audio recorded with GNU/Linux machine
- plays lastly recorded video clips
    - with optional mirror effect

```
cd vlog-toolset

./bin/vlog-record -h
Usage: vlog-record -p project_dir/ [other options]
  -p, --project <dir>              Project directory
  -t, --trim <duration>            Trim duration of beginning and ending of each clip (default: 0.2)
  -s <arecord-args>,               Additional arecord arguments (default: "--device=default --format=dat")
      --sound-settings
  -A, --android-device <device-id> Android device id
  -o, --opencamera-dir <dir>       Open Camera directory path on Android device (default: "/storage/emulated/0/DCIM/OpenCamera")
  -b <true|false>,                 Set lowest brightness to save device power (default: false)
      --change-brightness
  -m, --mpv-args <mpv-args>        Additional mpv arguments (default: "--vf=hflip --volume-max=300 --volume=130 --speed=1.2)"
  -P <seconds>,                    Minimum pause between shots for auto trimming (default: 2.0)
      --pause-between-shots
  -a, --aggressiveness <0..1>      How aggressively to filter out non-speech (default: 0.4)
  -d, --debug <true|false>         Show debug messages (default: false)

./bin/vlog-record -p ~/video/new-cool-video-project
...
----------------------------------------------------------------------
        R - (RE)START clip recording (loses unsaved clip)
        S - STOP and SAVE current clip
Shift + S - STOP and SAVE current clip, DON'T use auto silence removal
        D - STOP and DELETE current clip
        P - PLAY last saved clip
        F - FOCUS camera on center
----------------------------------------------------------------------
Shift + R - (RE)START SILENCE recording attempt
----------------------------------------------------------------------
        H - show HELP
        Q - QUIT

[ ⬜ ] [ 💻 | 💾 466G ] [ 📞 | 🔋100% / 41°C | 💾 18G ]
```

## vlog-render
- applies some effects to video clips
    - speed/tempo change
    - forced constant frame rate
        - which is useful for video editors that don't support variable frame rate (like Blender)
    - video denoiser, mirror, vignette and/or whatever you [specify](https://ffmpeg.org/ffmpeg-filters.html#Video-Filters)
- renders video clips to a final video
    - also H.265/HVEC, with hardware acceleration if available
- plays a video from a given position

```
Usage: vlog-render -p project_dir/ -w path/to/whisper.cpp/ [other options]
  -p, --project <dir>              Project directory
  -P, --preview <true|false>       Preview mode. It will also start a video player by a given position (default: true)
  -n, --tmux-nvim <true|false>     Plain text video editing: open render.conf (during preview mode or when render.conf was just generated) in Neovim via Tmux if they are available (default: true)
  -f, --fps <num>                  Constant frame rate (default: 30)
  -S, --speed <num>                Speed factor (default: 1.2)
  -V, --video-filters <filters>    ffmpeg video filters (default: "hqdn3d,hflip,vignette")
  -c, --cleanup <true|false>       Remove temporary files, instead of reusing them in future (default: false)
  -w, --whisper-cpp-dir <dir>      whisper.cpp directory
  -W, --whisper-cpp-args <dir>     Additional whisper.cpp arguments (default: "--model models/ggml-base.bin --language auto")
  -y, --youtube <true|false>       Additionally optimize for YouTube (default: false)
  -I, --ios <true|false>           Additionally optimize for iOS video editors (default: false)

./bin/vlog-render -p ~/video/new-cool-video-project --preview false --whisper-cpp-dir path/to/whisper-cpp-dir
```

- it also runs voice recognition in a selected language
- makes more precise clips segmentation
- produces media output
    - clips are located in `project_dir/output/`
    - concatenation of all clips is located at `project_dir/output.mp4`
- produces a configuration file
    - the columns in the config are:
        - clip filename
        - speed multiplier
        - start position (in seconds)
        - end position (in seconds)
        - recognized text (to figure out which clips can be removed / reordered)
    - you can edit the config
        - put `#` in the beginning of line you want to ignore (or just remove the entire line)
        - change speed of individual clips

```
vi ~/video/new-cool-video-project/render.conf
```

## vlog-add
```
Usage: vlog-add -p project_dir/ [other options]
Project directory must contain inputvoice_000001.mp4, inputother_000002.mp4 ... as input files (also optionally inputvoice_000001.wav, inputother_000002.wav ... with highest audio quality)
  -p, --project <dir>              Project directory
  -P <seconds>,                    Minimum pause between shots for auto trimming (default: 2.0)
      --pause-between-shots
  -a, --aggressiveness <0..1>      How aggressively to filter out non-speech (default: 0.4)
```

## Known issues/limitations
- it's just a dumb dirty PoC/prototype, it's **not necessarily gonna work on your hardware**
    - I use Xiaomi Mi 8
        - front camera faces at me
        - microphone and camera are allowed
- paths with spaces and weird characters are unsupported

## Recommended Open Camera Settings
- ⋮
    - Grid - Phi 3x3
- ⚙️
    - Video settings…
        - Video resolution - FullHD 1920x1080 (16:9 2.07 MP)
        - Video format - **MPEG4 HEVC**
        - Video frame rate (approx) - 30
    - Camera API - Camera2 API

## Troubleshooting
- auto-rotation fails
    - reboot your phone
- flickering when recording with artificial lighting
    - Open Camera - ⚙️ - Processing settings - Anti-banding - Auto (or precisely 50 Hz in my case)

## TODO: Rewrite this prototype in Rust?
- support other sources (webcams, screencasting)
    - support multiple sources (cams, mics) at the same time
- support other operating systems
- [adb](https://github.com/kpcyrd/forensic-adb/blob/736f7c43d116b6334af3c1d8c4a41f9ae06ff812/src/lib.rs#L754)
    - `pull` performance comparing `android-tools`? for USB 2 and 3

## Support
I'm currently investing [all my time](https://codonaft.com/why) in FOSS projects.

If you found this repo useful and you want to support me, please
- ⭐ it
- check ⚡ [here](https://codonaft.com/sponsor)

Your support keeps me going ❤️ (◕‿◕)

## License
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

This program comes with ABSOLUTELY NO WARRANTY.
This is free software, and you are welcome to redistribute it
under certain conditions; read LICENSE.txt for details.

Copyright (C) 2018—∞  Alexander Lopatin <alopatindev ät codonaft dot com>
