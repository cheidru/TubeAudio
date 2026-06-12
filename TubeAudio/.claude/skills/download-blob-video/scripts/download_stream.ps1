<#
.SYNOPSIS
    Download a streamed web video (HLS .m3u8 / DASH .mpd / progressive .mp4) and
    remux it into a single MP4. Built for "blob:" videos whose real source was
    sniffed from the page's network traffic.

.DESCRIPTION
    Thin wrapper around yt-dlp (which uses ffmpeg for muxing). Ensures both tools
    are installed (via winget if missing), downloads the stream, and remuxes to
    an .mp4 container without re-encoding. On success prints:
        SAVED: <full path to the .mp4>

.PARAMETER Url
    The manifest or media URL captured from the page (.m3u8, .mpd, or .mp4).
    A page URL also works — yt-dlp's generic extractor will try to find the
    stream itself. Required.

.PARAMETER Referer
    The page the video plays on. Many CDNs reject the manifest request without a
    matching Referer header (HTTP 403), so pass it when in doubt.

.PARAMETER OutName
    Output filename without extension. If omitted, yt-dlp derives a title, with a
    timestamped fallback when the stream has none.

.PARAMETER OutDir
    Save directory. Defaults to <project>\video.

.PARAMETER Cookies
    For auth-gated streams: a browser name (edge/chrome/firefox/brave) to pull
    cookies from, or a path to a cookies.txt file.

.PARAMETER Header
    Extra request header(s), e.g. "Origin: https://site.com". Repeatable.

.EXAMPLE
    .\download_stream.ps1 -Url "https://cdn.site/master.m3u8" -Referer "https://site.com/watch/123" -OutName "lecture-3"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [string]$Referer,
    [string]$OutName,
    [string]$OutDir,
    [string]$Cookies,
    [string[]]$Header
)

$ErrorActionPreference = 'Stop'

# yt-dlp prints UTF-8; align the console so captured paths with non-ASCII
# characters (titles, etc.) aren't mangled and stay testable.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# --- Default output directory: <project>\video --------------------------------
# This script lives at <project>\.claude\skills\download-blob-video\scripts\,
# so walk up four levels to reach the project root.
if (-not $OutDir) {
    $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $OutDir = Join-Path $projectRoot 'video'
}
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

# --- Refresh PATH from registry (so freshly winget-installed tools are seen) ---
function Update-PathFromRegistry {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

# --- Ensure a tool exists, installing via winget if necessary -----------------
function Ensure-Tool {
    param([string]$Command, [string]$WingetId, [string]$FriendlyName)

    if (Get-Command $Command -ErrorAction SilentlyContinue) { return }

    Write-Host "$FriendlyName not found. Installing via winget ($WingetId)..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget is unavailable, so $FriendlyName cannot be auto-installed. Install it manually (see https://github.com/yt-dlp/yt-dlp#installation)."
    }

    winget install --id $WingetId --exact --silent `
        --accept-source-agreements --accept-package-agreements `
        --disable-interactivity | Out-Host

    Update-PathFromRegistry

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "Installed $FriendlyName but '$Command' is still not on PATH. A new terminal may be required, or the install failed."
    }
    Write-Host "$FriendlyName installed."
}

Ensure-Tool -Command 'yt-dlp' -WingetId 'yt-dlp.yt-dlp' -FriendlyName 'yt-dlp'
# ffmpeg does the actual muxing of segments into the MP4 container.
Ensure-Tool -Command 'ffmpeg' -WingetId 'Gyan.FFmpeg' -FriendlyName 'ffmpeg'

# --- Build the yt-dlp command -------------------------------------------------
if ($OutName) {
    # Strip any extension the caller accidentally included.
    $OutName = [System.IO.Path]::GetFileNameWithoutExtension($OutName)
    $outTemplate = Join-Path $OutDir "$OutName.%(ext)s"
}
else {
    # Title when available; otherwise a stable timestamped name so we never
    # clobber a previous download or end up with a blank filename.
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outTemplate = Join-Path $OutDir "%(title)s [$stamp].%(ext)s"
}

$ytArgs = @(
    '--no-playlist'
    '--no-progress'
    '-o', $outTemplate
    '--remux-video', 'mp4'       # mux/remux into an .mp4 container, no re-encode
)

if ($Referer) { $ytArgs += @('--referer', $Referer) }

if ($Cookies) {
    if (Test-Path -LiteralPath $Cookies) {
        $ytArgs += @('--cookies', $Cookies)                 # cookies.txt file
    }
    else {
        $ytArgs += @('--cookies-from-browser', $Cookies)    # browser name
    }
}

foreach ($h in $Header) {
    if ($h) { $ytArgs += @('--add-header', $h) }
}

$ytArgs += $Url

Write-Host "Running: yt-dlp $($ytArgs -join ' ')"
$startTime = Get-Date

# Capture the resolved output path via --print; fall back to newest-file below.
$printArgs = $ytArgs + @('--print', 'after_move:filepath')
$savedPath = & yt-dlp @printArgs

if ($LASTEXITCODE -ne 0) {
    throw "yt-dlp exited with code $LASTEXITCODE. See output above (common causes: missing -Referer, auth cookies needed, or DRM)."
}

$savedPath = ($savedPath | Where-Object { $_ -and $_.Trim() } | Select-Object -Last 1)

if (-not ($savedPath -and (Test-Path -LiteralPath $savedPath))) {
    # --print can come back empty on some manifests; the download still
    # succeeded, so report the newest file dropped into OutDir during this run.
    $savedPath = Get-ChildItem -LiteralPath $OutDir -File |
        Where-Object { $_.LastWriteTime -ge $startTime.AddSeconds(-2) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

Write-Host ""
if ($savedPath -and (Test-Path -LiteralPath $savedPath)) {
    Write-Host "SAVED: $savedPath"
}
else {
    Write-Host "SAVED: (in folder) $OutDir"
}
