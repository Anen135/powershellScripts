<#
.SYNOPSIS
    Analyzes MP4 video files using FFprobe and generates a detailed analysis report.

.DESCRIPTION
    Uses ffprobe to extract general format information, stream details,
    video/audio stream properties, key frame counts, and produces a
    comprehensive text-based analysis report alongside the source file.

.PARAMETER InputFile
    Path to the MP4 file to analyze.

.EXAMPLE
    .\Analyze-MP4.ps1 -InputFile "video.mp4"

.EXAMPLE
    .\Analyze-MP4.ps1 -InputFile "C:\Videos\sample.mp4"

.NOTES
    Version: 1.0
    Author: Anen
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile
)

if (!(Test-Path $InputFile)) {
    Write-Host "File not found: $InputFile" -ForegroundColor Red
    exit 1
}

if (!(Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    Write-Host "ffprobe not found." -ForegroundColor Red
    exit 1
}

$OutputFile = [System.IO.Path]::ChangeExtension($InputFile, ".analysis.txt")

function Step($text) {
    Write-Host ""
    Write-Host "[*] $text [$((Get-Date).TimeOfDay)]" -ForegroundColor Cyan
}

function Start-Probe($ProbeArgs, $section) {
    Step $section

    $start = Get-Date

    & ffprobe @ProbeArgs 2>> $null |
        Out-File $OutputFile -Append

    $time = (Get-Date) - $start

    Write-Host "    Completed in $([math]::Round($time.TotalSeconds,2)) sec." -ForegroundColor Green
}


Remove-Item $OutputFile -ErrorAction SilentlyContinue


"======================================" | Out-File $OutputFile
"FFmpeg MP4 ANALYSIS REPORT"             | Out-File $OutputFile -Append
"File: $InputFile"                       | Out-File $OutputFile -Append
"Date: $(Get-Date)"                      | Out-File $OutputFile -Append
"======================================" | Out-File $OutputFile -Append


Start-Probe @(
    "-v","error",
    "-show_entries",
    "format=filename,format_name,duration,size,bit_rate",
    "-of",
    "default=noprint_wrappers=1",
    $InputFile
) "General information"


Start-Probe @(
    "-v","error",
    "-show_entries",
    "stream=index,codec_type,codec_name,profile,level,width,height,pix_fmt,r_frame_rate,avg_frame_rate,bit_rate,channels,sample_rate",
    "-of",
    "default=noprint_wrappers=1",
    $InputFile
) "Stream information"


Start-Probe @(
    "-v","error",
    "-select_streams","v:0",
    "-show_entries","stream",
    "-of","default=noprint_wrappers=1",
    $InputFile
) "Video stream"


Start-Probe @(
    "-v","error",
    "-select_streams","a:0",
    "-show_entries","stream",
    "-of","default=noprint_wrappers=1",
    $InputFile
) "Audio stream"


Step "Counting key frames"

$start = Get-Date

$keyFrames = ffprobe `
    -select_streams v:0 `
    -show_frames `
    -show_entries frame=pict_type `
    -of csv `
    $InputFile |
    Select-String ",I"

$elapsed = (Get-Date) - $start

"=== KEY FRAMES ==="                    | Out-File $OutputFile -Append
"Key frames count: $($keyFrames.Count)" | Out-File $OutputFile -Append

Write-Host "    Key frames: $($keyFrames.Count)"
Write-Host "    Time: $([math]::Round($elapsed.TotalSeconds,2)) sec." -ForegroundColor Green


Start-Probe @(
    "-v","error",
    "-show_entries",
    "stream=index,codec_type,codec_name",
    "-of","table",
    $InputFile
) "Checking all streams"


Write-Host ""
Write-Host "================================="
Write-Host "Analysis completed" -ForegroundColor Green
Write-Host "Report file:"
Write-Host $OutputFile