<#
.SYNOPSIS
    Creates a folder filled with randomly sized junk files and subfolders for testing purposes (e.g., disk space usage, backup tools, deduplication, search performance).

.DESCRIPTION
    The script generates a specified number of subfolders inside the target directory, each containing a configurable number of binary junk files with random sizes.
    Files are filled with random byte data using System.Random.
    
    Features:
    - Automatically creates the root folder if it does not exist.
    - If the folder already exists, new subfolders and files are added without overwriting existing ones (unless -Recreate is used).
    - Progress bars are displayed during file and folder creation.
    - Approximate size of generated data is shown at the end.
    
    Useful for:
    - Quickly consuming disk space for testing
    - Generating test data for storage, backup, or file system tools
    - Stress-testing file indexing or search utilities

.PARAMETER Path
    The target directory where the trash folder structure will be created.
    Default: ".\TrashFolder" (relative to the script's location).

.PARAMETER FoldersCount
    Number of subfolders to create inside the root folder.
    Default: 50

.PARAMETER FilesPerFolder
    Number of junk files to create in each folder (including the root folder).
    Default: 100

.PARAMETER MaxFileSizeKB
    Maximum size of each generated file in kilobytes. Actual file sizes will be random between 1 KB and this value.
    Default: 512

.PARAMETER Recreate
    If specified, deletes the existing target folder (with all contents) before creating a new one.
    Without this switch, new content is appended to any existing folder.

.EXAMPLE
    .\Create-TrashFolder.ps1

    Creates .\TrashFolder with default settings (50 subfolders, 100 files each, max 512 KB per file).

.EXAMPLE
    .\Create-TrashFolder.ps1 -Path "C:\TestData\Trash" -FoldersCount 20 -FilesPerFolder 200 -MaxFileSizeKB 1024

    Creates a larger test dataset in a custom location.

.EXAMPLE
    .\Create-TrashFolder.ps1 -Recreate

    Deletes any existing TrashFolder and rebuilds it from scratch with default parameters.

.NOTES
    Version: 1.0
    Author: Anen
#>

param(
    [ValidateNotNullOrEmpty()]
    [string]$Path = ".\TrashFolder",
    [ValidateRange(1, [int]::MaxValue)]
    [int]$FoldersCount = 50,
    [ValidateRange(1, [int]::MaxValue)]
    [int]$FilesPerFolder = 100,
    [ValidateRange(1, [int]::MaxValue)]
    [int]$MaxFileSizeKB = 512,
    [switch]$Recreate
)

$Path = [System.IO.Path]::GetFullPath($Path)
$Random = [System.Random]::new()

# Handle existing folder
if (Test-Path $Path) {
    if ($Recreate) {
        Remove-Item $Path -Recurse -Force
        Write-Host "Old folder removed: $Path" -ForegroundColor Yellow
    } else {
        Write-Host "Folder already exists: $Path. Adding new files and subfolders." -ForegroundColor Cyan
    }
}

if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Write-Host "Folder created: $Path" -ForegroundColor Green
}

function New-JunkFile {
    param([string]$FilePath)

    $sizeKB = $Random.Next(1, $MaxFileSizeKB + 1)

    $byteCount = $sizeKB * 1024
    $bytes = New-Object Byte[] $byteCount

    $Random.NextBytes($bytes)

    try {
        [IO.File]::WriteAllBytes($FilePath, $bytes)
    } catch {
        Write-Error "Failed to create file: $FilePath ($($_.Exception.Message))"
        throw
    }
}

function New-FilesInFolder {
    param(
        [string]$FolderPath,
        [int]$Count,
        [string]$Activity
    )

    for ($i = 1; $i -le $Count; $i++) {
        $filePath = Join-Path $FolderPath "junk_$i.bin"
        New-JunkFile $filePath

        if ($i % 20 -eq 0) {
            Write-Progress -Activity $Activity -Status "$i of $Count" -PercentComplete ($i / $Count * 100)
        }
    }
}

try {
    # Files in root folder
    Write-Host "Creating $FilesPerFolder files in the root folder..."
    New-FilesInFolder -FolderPath $Path -Count $FilesPerFolder -Activity "Root folder"

    # Subfolders
    Write-Host "Creating $FoldersCount subfolders with $FilesPerFolder files each..."
    for ($f = 1; $f -le $FoldersCount; $f++) {
        $subPath = Join-Path $Path "subfolder_$f"
        if (-not (Test-Path $subPath)) {
            New-Item -ItemType Directory -Path $subPath -Force | Out-Null
        }
        New-FilesInFolder -FolderPath $subPath -Count $FilesPerFolder -Activity "Subfolder $f"
        Write-Progress -Activity "Creating subfolders" -Status "$f of $FoldersCount" -PercentComplete ($f / $FoldersCount * 100)
    }

    # Statistics
    $totalFolders = $FoldersCount + 1
    $totalNewFiles = $totalFolders * $FilesPerFolder
    $avgFileSizeKB = $MaxFileSizeKB / 2
    $approxMB = [math]::Round(($totalNewFiles * $avgFileSizeKB) / 1024, 2)

    Write-Host "Done!" -ForegroundColor Green
    Write-Host "Path: $Path"
    Write-Host "Added subfolders: $FoldersCount"
    Write-Host "Added files: $totalNewFiles"
    Write-Host "Approximate size of added data: ~$approxMB MB"
} catch {
    Write-Error "Error creating trash folder: $($_.Exception.Message)"
    throw
}
