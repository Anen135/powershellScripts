<#
.SYNOPSIS
    Cleans and optimizes MP4 files by removing metadata and optimizing for streaming.

.DESCRIPTION
    Processes all MP4 files in the current directory using FFmpeg.
    Strips all metadata, adds a faststart moov atom for web optimization,
    and copies video/audio streams without re-encoding (lossless).

.PARAMETER OutputDir
    Directory where cleaned files will be saved. Default: "cleaned".

.EXAMPLE
    Optimize-MP4

.EXAMPLE
    Optimize-MP4 -OutputDir "optimized_videos"

.NOTES
    Version: 1.0
    Author: Anen
#>

function Optimize-MP4 {
    param(
        [string]$OutputDir = "cleaned"
    )

    $InputDir = Get-Location
    $OutputPath = Join-Path $InputDir $OutputDir

    # Create destination folder
    if (!(Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath | Out-Null
    }

    # Find MP4 files
    $files = Get-ChildItem -Path $InputDir -Filter "*.mp4" -File

    if ($files.Count -eq 0) {
        Write-Host "No MP4 files found." -ForegroundColor Yellow
        return
    }

    foreach ($file in $files) {

        $destination = Join-Path $OutputPath $file.Name

        Write-Host ""
        Write-Host "Processing: $($file.Name)" -ForegroundColor Cyan

        if (Test-Path $destination) {
            Write-Host "Skipping (already exists): $destination" -ForegroundColor Yellow
            continue
        }

        & ffmpeg `
            -hide_banner `
            -loglevel warning `
            -i $file.FullName `
            -map 0 `
            -c copy `
            -map_metadata -1 `
            -movflags +faststart `
            $destination

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Done: $destination" -ForegroundColor Green
        }
        else {
            Write-Host "Error: $($file.Name)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "Cleanup completed." -ForegroundColor Green
}