# CleanUpCache.ps1

param(
    [string]$PathsFile = "C:\Program Files\WindowsPowerShell\Scripts\cache.txt", 
    [switch]$WhatIf                   
)

if (-not (Test-Path $PathsFile)) {
    Write-Error "Path list file not found: $PathsFile"
    exit 1
}

$PathsFileDir = Split-Path -Parent $PathsFile
$paths = Get-Content $PathsFile | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }

if ($paths.Count -eq 0) {
    Write-Warning "No valid paths to clean."
    exit 0
}

Write-Host "Found $($paths.Count) path(s) to clean." -ForegroundColor Cyan
if ($WhatIf) { Write-Host "WhatIf mode: nothing will be deleted, preview only." -ForegroundColor Yellow }
$totalFilesDeleted = 0
$totalFoldersDeleted = 0
$totalErrors = 0
$failedItems = @()

foreach ($rawPath in $paths) {
    $path = [System.Environment]::ExpandEnvironmentVariables($rawPath)
    if (-not ([System.IO.Path]::IsPathRooted($path))) { $path = Join-Path $PathsFileDir $path }
    $item = Get-Item $path -ErrorAction SilentlyContinue
    if (-not $item) {
        Write-Warning "Path does not exist: $path"
        $totalErrors++
        $failedItems += $path
        continue
    }

    try {
        if ($item.PSIsContainer) {
            $contents = Get-ChildItem $path -Force -ErrorAction SilentlyContinue
            if ($contents) {
                foreach ($child in $contents) {
                    try {
                        Remove-Item $child.FullName -Recurse -Force -ErrorAction Stop -WhatIf:$WhatIf
                        if ($child.PSIsContainer) { $totalFoldersDeleted++ } else { $totalFilesDeleted++ }
                        Write-Host "Deleted: $($child.FullName)" -ForegroundColor Green
                    } catch {
                        Write-Warning "Failed to delete $($child.FullName): $_"
                        $totalErrors++
                        $failedItems += $child.FullName
                    }
                }
            } else {
                Write-Host "Folder is already empty: $path" -ForegroundColor Gray
            }
        } else {
            try {
                Remove-Item $path -Force -ErrorAction Stop -WhatIf:$WhatIf
                $totalFilesDeleted++
                Write-Host "File deleted: $path" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to delete file ${path}: $_"
                $totalErrors++
                $failedItems += $path
            }
        }
    } catch {
        Write-Warning "Failed to process path ${path}: $_"
        $totalErrors++
        $failedItems += $path
    }
}
Write-Host "`nCleanup completed!" -ForegroundColor Cyan
Write-Host "Files deleted: $totalFilesDeleted" -ForegroundColor Yellow
Write-Host "Folders deleted: $totalFoldersDeleted" -ForegroundColor Yellow
Write-Host "Errors: $totalErrors" -ForegroundColor Red

if ($failedItems.Count -gt 0) {
    Write-Host "`nFailed to process the following paths:" -ForegroundColor Red
    $failedItems | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
}

if ($WhatIf) {
    Write-Host "`nRun the script without -WhatIf parameter for actual deletion." -ForegroundColor Yellow
}