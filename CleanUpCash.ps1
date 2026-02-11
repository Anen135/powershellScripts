# Safe-Cleanup-v2.ps1
# Скрипт для безопасной очистки папок и файлов из списка
# Продолжает удаление даже если некоторые файлы/папки заняты

param(
    [string]$PathsFile = "C:\Program Files\WindowsPowerShell\Scripts\cash.txt",  # Файл со списком путей
    [switch]$WhatIf                    # Режим предпросмотра
)

# Проверка файла со списком
if (-not (Test-Path $PathsFile)) {
    Write-Error "Файл со списком путей не найден: $PathsFile"
    exit 1
}

# Папка файла списка, чтобы корректно обрабатывать относительные пути
$PathsFileDir = Split-Path -Parent $PathsFile

# Чтение путей, удаление кавычек, игнорирование пустых строк и комментариев
$paths = Get-Content $PathsFile | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }

if ($paths.Count -eq 0) {
    Write-Warning "Нет валидных путей для очистки."
    exit 0
}

Write-Host "Найдено $($paths.Count) пут(ей) для очистки." -ForegroundColor Cyan
if ($WhatIf) { Write-Host "Режим WhatIf: ничего не будет удалено, только предпросмотр." -ForegroundColor Yellow }

# Статистика
$totalFilesDeleted = 0
$totalFoldersDeleted = 0
$totalErrors = 0
$failedItems = @()

foreach ($rawPath in $paths) {
    $path = [System.Environment]::ExpandEnvironmentVariables($rawPath)
    if (-not ([System.IO.Path]::IsPathRooted($path))) { $path = Join-Path $PathsFileDir $path }
    $item = Get-Item $path -ErrorAction SilentlyContinue
    if (-not $item) {
        Write-Warning "Путь не существует: $path"
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
                        Write-Host "Удалено: $($child.FullName)" -ForegroundColor Green
                    } catch {
                        Write-Warning "Не удалось удалить $($child.FullName): $_"
                        $totalErrors++
                        $failedItems += $child.FullName
                    }
                }
            } else {
                Write-Host "Папка уже пуста: $path" -ForegroundColor Gray
            }
        } else {
            try {
                Remove-Item $path -Force -ErrorAction Stop -WhatIf:$WhatIf
                $totalFilesDeleted++
                Write-Host "Файл удален: $path" -ForegroundColor Green
            } catch {
                Write-Warning "Не удалось удалить файл ${path}: $_"
                $totalErrors++
                $failedItems += $path
            }
        }
    } catch {
        Write-Warning "Не удалось обработать путь ${path}: $_"
        $totalErrors++
        $failedItems += $path
    }
}

# Итоги
Write-Host "`nОчистка завершена!" -ForegroundColor Cyan
Write-Host "Файлов удалено: $totalFilesDeleted" -ForegroundColor Yellow
Write-Host "Папок удалено: $totalFoldersDeleted" -ForegroundColor Yellow
Write-Host "Ошибок: $totalErrors" -ForegroundColor Red

if ($failedItems.Count -gt 0) {
    Write-Host "`nНе удалось обработать следующие пути:" -ForegroundColor Red
    $failedItems | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
}

if ($WhatIf) {
    Write-Host "`nЗапустите скрипт без параметра -WhatIf для реального удаления." -ForegroundColor Yellow
}
