# FFmpeg CLI in this prototype

The Godot playback extension in `addons/ffmpeg` and the standalone FFmpeg CLI are intentionally separate layers.

- `EIRTeam.FFmpeg` decodes video for `VideoStreamPlayer`.
- `ffprobe.exe` reads metadata for the Resource Library.
- `ffmpeg.exe` performs background transcoding/optimization.

## Windows development setup

Run from PowerShell in the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\install_ffmpeg_windows.ps1
```

The script downloads a pinned **FFmpeg 8.1.2 Essentials** static x64 build from Gyan.dev, verifies SHA-256, and copies only `ffmpeg.exe` and `ffprobe.exe` into:

```text
tools/ffmpeg/windows/bin/
```

Pinned SHA-256 for `ffmpeg-8.1.2-essentials_build.zip`:

```text
db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec
```

## Export

Do not execute FFmpeg from inside the `.pck`. The provided `tools/build_windows.ps1` exports Godot and copies the executable tools next to the exported application:

```text
NotLightMediaPrototype.exe
NotLightMediaPrototype.pck
tools/ffmpeg/windows/bin/ffmpeg.exe
tools/ffmpeg/windows/bin/ffprobe.exe
```

`FFmpegTools` searches the project folder while running from the editor, the application folder in exported builds, and finally the system `PATH`.
