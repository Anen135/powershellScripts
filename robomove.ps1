param([string]$source, [string]$destination)

if (-not (Test-Path -Path $destination)) {
    Write-Host "Creating destination folder: $destination" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
}

robocopy $source $destination /MOV /E /MT:16 /R:3 /W:5
Write-Host "Done" -ForegroundColor Green
Get-ChildItem -Path $destination