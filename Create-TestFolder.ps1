# Create-TestFolder.ps1
param(
    [string]$Path = ".\TestTrash",      # Теперь по умолчанию относительный путь без завершающего слеша
    [int]$FoldersCount = 50,
    [int]$FilesPerFolder = 100,
    [int]$MaxFileSizeKB = 512
)

# Разрешаем путь правильно (относительный → абсолютный)
$ResolvedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
if (-not $ResolvedPath) {
    $ResolvedPath = Join-Path (Get-Location) $Path
}

function CreateFolder {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "Создана папка: $Path"
    } else {
        Write-Host "Папка уже существует: $Path"
    }
}


$Path = $ResolvedPath
CreateFolder $Path

# Функция создания мусорного файла
function New-JunkFile {
    param($FilePath)
    $sizeKB = Get-Random -Minimum 1 -Maximum $MaxFileSizeKB
    $bytes = New-Object Byte[] ($sizeKB * 1024)
    (New-Object Random).NextBytes($bytes)
    [IO.File]::WriteAllBytes($FilePath, $bytes)
}

# Файлы в корневой папке
Write-Host "Создаю $FilesPerFolder файлов в корневой папке..."
for ($i = 1; $i -le $FilesPerFolder; $i++) {
    $fileName = "junk_file_$i.txt"
    $filePath = Join-Path $Path $fileName
    New-JunkFile -FilePath $filePath
    if ($i % 20 -eq 0) { Write-Progress -Activity "Корневая папка" -Status "$i из $FilesPerFolder" -PercentComplete ($i / $FilesPerFolder * 100) }
}

# Подпапки и файлы в них
Write-Host "Создаю $FoldersCount подпапок с $FilesPerFolder файлами в каждой..."
for ($f = 1; $f -le $FoldersCount; $f++) {
    $folderName = "subfolder_$f"
    $folderPath = Join-Path $Path $folderName
    New-Item -ItemType Directory -Path $folderPath -Force | Out-Null

    for ($i = 1; $i -le $FilesPerFolder; $i++) {
        $fileName = "trash_$i.bin"
        $filePath = Join-Path $folderPath $fileName
        New-JunkFile -FilePath $filePath
    }

    Write-Progress -Activity "Создание подпапок" -Status "$f из $FoldersCount" -PercentComplete ($f / $FoldersCount * 100)
}

Write-Host "Готово! Папка заполнена:" -ForegroundColor Green
Write-Host "   Путь: $Path"
Write-Host "   Папок: $($FoldersCount + 1)"
Write-Host "   Файлов всего: $((($FoldersCount + 1) * $FilesPerFolder))"
Write-Host "   Примерный объём: ~$([math]::Round((($FoldersCount + 1) * $FilesPerFolder * $MaxFileSizeKB / 2) / 1024, 2)) МБ"