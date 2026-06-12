<#
.SYNOPSIS
    Extract the audio track from a single YouTube video using yt-dlp + ffmpeg.

.DESCRIPTION
    Thin wrapper around yt-dlp. Ensures yt-dlp and ffmpeg are installed (via
    winget if missing), then downloads audio-only and converts it to the
    requested format, embedding metadata and the thumbnail.

    On success it prints a line:  SAVED: <full path to the audio file>

.PARAMETER Url
    The YouTube video URL (or youtu.be short link). Required.

.PARAMETER Format
    Output audio format: mp3 (default), m4a, wav, or best (keep the native
    stream, no re-encode).

.PARAMETER OutDir
    Directory to save into. Defaults to an "audio" subfolder of the project
    root (the parent of this skill's directory tree), i.e. G:\Claude\TubeAudio\audio.

.EXAMPLE
    .\extract_audio.ps1 -Url "https://youtu.be/dQw4w9WgXcQ"

.EXAMPLE
    .\extract_audio.ps1 -Url "https://youtu.be/dQw4w9WgXcQ" -Format m4a -OutDir "C:\Users\chei\Music"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [ValidateSet('mp3', 'm4a', 'wav', 'best')]
    [string]$Format = 'mp3',

    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

# yt-dlp prints UTF-8. Without this, titles containing emoji or full-width
# characters (e.g. ✈️ or ｜) get mangled when PowerShell captures stdout, which
# breaks the Test-Path check on the reported filename.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# --- Default output directory: <project>\audio --------------------------------
# This script lives at <project>\.claude\skills\extract-youtube-audio\scripts\,
# so walk up four levels to reach the project root.
if (-not $OutDir) {
    $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $OutDir = Join-Path $projectRoot 'audio'
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
    param(
        [string]$Command,      # exe to look for, e.g. 'yt-dlp'
        [string]$WingetId,     # winget package id, e.g. 'yt-dlp.yt-dlp'
        [string]$FriendlyName  # for messages
    )

    if (Get-Command $Command -ErrorAction SilentlyContinue) { return }

    Write-Host "$FriendlyName not found. Installing via winget ($WingetId)..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget is not available, so $FriendlyName cannot be auto-installed. Install $FriendlyName manually (see https://github.com/yt-dlp/yt-dlp#installation)."
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
# ffmpeg is needed for format conversion and thumbnail/metadata embedding.
if ($Format -ne 'best') {
    Ensure-Tool -Command 'ffmpeg' -WingetId 'Gyan.FFmpeg' -FriendlyName 'ffmpeg'
}

# --- Build the yt-dlp command -------------------------------------------------
$outTemplate = Join-Path $OutDir '%(title)s.%(ext)s'

$ytArgs = @(
    '--no-playlist'              # only the selected video, never the whole list
    '--no-progress'              # quieter output
    '-o', $outTemplate
)

if ($Format -eq 'best') {
    # Keep the native audio stream, no re-encode.
    $ytArgs += @('-f', 'bestaudio', '--extract-audio')
}
else {
    $ytArgs += @(
        '--extract-audio'
        '--audio-format', $Format
        '--audio-quality', '0'   # best quality for the chosen codec
        '--embed-metadata'
        '--embed-thumbnail'
    )
}

$ytArgs += $Url

Write-Host "Running: yt-dlp $($ytArgs -join ' ')"

# Note the time just before the download so we can reliably identify the file
# that was produced, independent of how yt-dlp echoes its path.
$startTime = Get-Date

# --- Run, capturing the final filename via --print after_move -----------------
# Use --print to emit the resolved output path so we can report it reliably.
$printArgs = $ytArgs + @('--print', 'after_move:filepath')
$savedPath = & yt-dlp @printArgs

if ($LASTEXITCODE -ne 0) {
    throw "yt-dlp exited with code $LASTEXITCODE. See output above."
}

# --print may emit multiple lines on odd inputs; take the last non-empty one.
$savedPath = ($savedPath | Where-Object { $_ -and $_.Trim() } | Select-Object -Last 1)

if (-not ($savedPath -and (Test-Path -LiteralPath $savedPath))) {
    # Fallback: --print can come back empty or get mangled on exotic titles.
    # The download still succeeded, so find the newest audio file dropped into
    # OutDir during this run and report that — far more useful than the folder.
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
