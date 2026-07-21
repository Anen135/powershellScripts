<#
.SYNOPSIS
    Converts ZIP archives to RAR format using WinRAR with maximum compression.

.DESCRIPTION
    Extracts a ZIP archive to a temporary folder, then re-compresses the
    contents using WinRAR with maximum compression (m5) and solid archive mode.
    Outputs compression statistics including space saved.

.PARAMETER ZipFile
    Path to the ZIP file to convert.

.PARAMETER WinRAR
    Path to the WinRAR executable. Default: "C:\Program Files\WinRAR\WinRAR.exe".

.PARAMETER OutputFile
    Path for the output RAR file. Default: same path as ZIP with .rar extension.

.EXAMPLE
    Convert-ZipToRar -ZipFile "archive.zip"

.EXAMPLE
    Convert-ZipToRar -ZipFile "archive.zip" -OutputFile "compressed.rar"

.NOTES
    Version: 1.0
    Author: Anen
#>

function Convert-ZipToRar {
    param(
        [Parameter(Mandatory)]
        [string]$ZipFile,

        [string]$WinRAR = "${env:ProgramFiles}\WinRAR\WinRAR.exe",

        [string]$OutputFile
    )

    if (-not (Test-Path $ZipFile)) {
        throw "File not found: $ZipFile"
    }

    if (-not (Test-Path $WinRAR)) {
        throw "WinRAR not found: $WinRAR"
    }

    if (-not $OutputFile) {
        $OutputFile = [System.IO.Path]::ChangeExtension($ZipFile, ".rar")
    }

    $tempDir = Join-Path $env:TEMP ("rar_" + [guid]::NewGuid())

    try {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        Write-Host "Extracting ZIP..."
        Expand-Archive -Path $ZipFile -DestinationPath $tempDir -Force

        Write-Host "Creating RAR..."
        & $WinRAR a `
            -r `
            -ma5 `
            -m5 `
            -s `
            $OutputFile `
            "$tempDir\*"

        if ($LASTEXITCODE -ne 0) {
            throw "WinRAR exited with code $LASTEXITCODE"
        }

        $zipSize = (Get-Item $ZipFile).Length
        $rarSize = (Get-Item $OutputFile).Length

        [PSCustomObject]@{
            SourceFile     = $ZipFile
            OutputFile     = $OutputFile
            SourceSizeGB   = [math]::Round($zipSize / 1GB, 2)
            OutputSizeGB   = [math]::Round($rarSize / 1GB, 2)
            SavedMB        = [math]::Round(($zipSize - $rarSize) / 1MB, 2)
            CompressionPct = [math]::Round((1 - $rarSize / $zipSize) * 100, 2)
        }
    }
    finally {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}