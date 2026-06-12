---
name: download-blob-video
description: >-
  Download a video from a website when the browser only exposes a blob: URL —
  i.e. the page plays video but there's no direct file to save, because it's a
  streamed HLS (.m3u8) or DASH (.mpd) source behind a MediaSource blob. Use this
  whenever the user says things like "download this video from <site>", "the
  video URL is blob: and I can't save it", "rip/grab this stream", "save this
  m3u8 / HLS video", "download the video on this page", or points at a non-YouTube
  page with an embedded player they want saved. Drives a real browser to sniff
  the underlying stream, then downloads and remuxes it to MP4. (For plain
  YouTube audio, use extract-youtube-audio instead.)
compatibility: Windows with winget + PowerShell, the Playwright browser tools (MCP), yt-dlp + ffmpeg (auto-installed).
---

# Download Blob Video

A `blob:` URL is not a real network address — it's an in-memory handle the page
hands to a `<video>` element via MediaSource. The actual bytes arrive as a
manifest plus segments: usually **HLS** (`.m3u8` master/variant playlists +
`.ts`/`.m4s` segments) or **DASH** (`.mpd` + segments). You can't download the
`blob:` directly; you find the manifest the player is fetching, then let
`yt-dlp` pull and mux it into an MP4.

This skill has two phases: **sniff** the manifest with the Playwright browser,
then **download** it with the bundled script.

## Phase 1 — Sniff the real stream URL

Use the Playwright browser tools to load the page and watch what the player
requests. The user gives you the page URL (the one showing the video), not the
`blob:` value — the `blob:` is useless to us.

1. `browser_navigate` to the page URL.
2. The stream often isn't requested until playback starts. Take a
   `browser_snapshot`, find the play button, and `browser_click` it. If a
   cookie/consent wall or "click to play" overlay is in the way, dismiss it
   first. Give it a moment with `browser_wait_for` so segment requests fire.
3. Call `browser_network_requests` and scan the URLs for the manifest. Priority:
   - **`.m3u8`** — HLS. If you see both a master playlist and variant playlists,
     prefer the **master** (yt-dlp will pick the best quality from it). A master
     usually references other `.m3u8` URLs; a variant directly references `.ts`
     segments.
   - **`.mpd`** — DASH manifest.
   - A direct **`.mp4`** (progressive) request — if the player just streams a
     plain mp4, that URL is all you need; you may not even need a remux.
   - Last resort: many `.ts` / `.m4s` segment URLs but no manifest — the
     manifest is usually the same path with `.m3u8`; reconstruct it, or reload
     and look again, since the manifest request can scroll out of the list.
4. Note the **page URL** — many CDNs reject manifest requests without a matching
   `Referer`, so you'll pass it to the downloader as `-Referer`.

If the site requires login, the stream lives behind a session. Two options:
let the script reuse the browser's cookies with `-Cookies edge` (or `chrome`,
`firefox`), or have the user export a `cookies.txt` and pass its path.

## Phase 2 — Download and remux to MP4

Hand the captured manifest/media URL to the script. It ensures yt-dlp + ffmpeg
are installed, downloads all segments, and remuxes them into a single `.mp4`
(no re-encode — fast and lossless):

```powershell
& "<skill-dir>\scripts\download_stream.ps1" `
    -Url "<captured .m3u8 / .mpd / .mp4 URL>" `
    -Referer "<the page URL>" `
    -OutName "<a sensible filename, no extension>"
```

Defaults:
- Output: `G:\Claude\TubeAudio\video\<name>.mp4` (folder created if missing).
- `-OutName` is optional; without it the script lets yt-dlp derive a title, or
  falls back to a timestamped name when the stream has no real title.
- On success the script prints `SAVED: <full path>`.

### Options

| Parameter   | Purpose                                                      |
|-------------|-------------------------------------------------------------|
| `-Url`      | The manifest or media URL you sniffed (required).           |
| `-Referer`  | The page URL — send this whenever the CDN 403s without it.  |
| `-OutName`  | Output filename without extension.                          |
| `-OutDir`   | Override the save folder.                                   |
| `-Cookies`  | A browser name (`edge`/`chrome`/`firefox`) or a cookies.txt path, for auth-gated streams. |
| `-Header`   | Extra request header(s), e.g. `-Header "Origin: https://site"`. Repeatable. |

## When it fails

- **403 / "Forbidden"** → almost always a missing `Referer` (most common) or an
  auth cookie. Add `-Referer` first; if still blocked, add `-Cookies`.
- **yt-dlp can't parse the manifest** → try feeding the *page URL* directly to
  yt-dlp via the script (`-Url <page>`); yt-dlp's generic extractor recognizes
  many players on its own and may find the stream without sniffing.
- **Only segments, no playable result** → you likely grabbed a single variant or
  an init segment; go back and capture the master `.m3u8` / `.mpd` instead.

Relay the real error rather than retrying blindly — a geo-block, DRM (Widevine),
or paywall can't be worked around, and the user should know that's the cause.
DRM-protected streams (e.g. Netflix, most paid services) are encrypted and out
of scope; say so plainly instead of attempting a circumvention.

## Reference

`scripts\download_stream.ps1` is a commented yt-dlp wrapper (HLS/DASH → MP4
remux). Read it if you need a non-standard download — picking a specific
quality, capping resolution (`-f`), or muxing with raw ffmpeg.
