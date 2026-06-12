---
name: extract-youtube-audio
description: >-
  Extract or download the audio track from a YouTube video and save it as an MP3
  (or M4A/WAV/original). Use this whenever the user wants to rip, extract,
  download, save, or convert the audio/sound/music/soundtrack from a YouTube
  link or video — including phrasings like "get the audio from this video",
  "turn this YouTube video into an MP3", "download just the song", "grab the
  audio only", or pasting a youtube.com / youtu.be URL and asking for sound.
  Handles installing yt-dlp and ffmpeg via winget if they are missing.
compatibility: Windows with winget and PowerShell. Uses yt-dlp + ffmpeg (auto-installed if absent).
---

# Extract YouTube Audio

Pull the audio track out of a YouTube video and save it as an audio file. The
heavy lifting is done by `yt-dlp` (for downloading) and `ffmpeg` (for
converting/embedding), driven by the bundled `scripts/extract_audio.ps1`.

## When the user gives you a video

The user will identify the video in one of a few ways. Resolve it to a single
URL before running:

- A full URL (`https://www.youtube.com/watch?v=...` or `https://youtu.be/...`) —
  use it directly.
- A bare video ID (11 characters) — turn it into `https://youtu.be/<id>`.
- A URL with extra playlist/index params (`&list=...&index=...`) — keep the URL
  as-is; the script passes `--no-playlist` so only the one selected video is
  grabbed, not the whole playlist.

If the user genuinely hasn't given you a video (no URL, no ID, nothing in the
recent conversation), ask which video they want before doing anything else.

## Running the extraction

Invoke the script from PowerShell. It checks for the tools, installs them if
needed, then extracts the audio:

```powershell
& "<skill-dir>\scripts\extract_audio.ps1" -Url "<youtube-url>"
```

Default behavior:
- Output format: **MP3** at best quality (`--audio-quality 0`).
- Output location: an `audio\` subfolder inside the current project
  (`G:\Claude\TubeAudio\audio` by default), created if missing.
- Filename: the video's title, e.g. `audio\Rick Astley - Never Gonna Give You Up.mp3`.
- Metadata (title/artist) and the video thumbnail are embedded into the file.

### Options

Pass these to override defaults — only when the user asks for something specific:

| Parameter   | Purpose                                              | Example                         |
|-------------|------------------------------------------------------|---------------------------------|
| `-Format`   | `mp3` (default), `m4a`, `wav`, or `best` (no re-encode) | `-Format m4a`                |
| `-OutDir`   | Where to save the file                               | `-OutDir "C:\Users\chei\Music"` |
| `-Url`      | The YouTube video URL (required)                     | `-Url "https://youtu.be/abc"`   |

`best` keeps YouTube's native audio stream (usually opus or m4a) without
re-encoding — fastest and lossless relative to the source, but the container
format varies, so only use it when the user explicitly wants the original.

## Tool installation

The script auto-installs missing tools via winget (`yt-dlp.yt-dlp` and
`Gyan.FFmpeg`), then refreshes the PATH in-process so the freshly installed
binaries are usable immediately without restarting the shell. This is why a
first run on a clean machine takes longer — that's expected, not a hang. If
winget itself is unavailable or an install fails, surface the error and point
the user at https://github.com/yt-dlp/yt-dlp#installation rather than guessing.

## After it runs

Report the actual saved file path (the script prints `SAVED: <path>` on
success) so the user can find it. If yt-dlp reports the video is unavailable,
age-restricted, region-blocked, or private, relay that plainly — those are
limitations of the source video, not something to retry blindly.

## Reference

`yt-dlp` does the downloading and `ffmpeg` does the conversion. The script is a
thin, well-commented wrapper; read `scripts/extract_audio.ps1` if you need to
diagnose a failure or build a non-standard command (e.g. a time range, a
playlist, or a different quality).
