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