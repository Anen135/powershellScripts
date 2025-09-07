<#
.SYNOPSIS
    Очищает пользовательскую переменную среды PATH от несуществующих путей.
.DESCRIPTION
    Делает резервную копию, удаляет только несуществующие директории и прекращает выполнение, если изменений нет.
.NOTES
    Версия: 1.1
#>

$regPath = "HKCU:\Environment"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = "$env:USERPROFILE\Desktop\user-path-backup-$timestamp.txt"

# Получение текущего PATH
$oldPath = (Get-ItemProperty -Path $regPath -Name Path -ErrorAction Stop).Path
$pathList = $oldPath -split ';'

$validPaths = @()
$invalidPaths = @()

foreach ($path in $pathList) {
    if ([string]::IsNullOrWhiteSpace($path)) { continue }

    if (Test-Path $path.Trim()) {
        $validPaths += $path.TrimEnd('\')
    } else {
        $invalidPaths += $path
    }
}

if ($invalidPaths.Count -eq 0) {
    Write-Host "[∙] Все пути существуют. Изменения не требуются."
    return
}

# Создание резервной копии
$oldPath | Out-File -FilePath $backupPath -Encoding UTF8

# Обновление PATH
$newPath = ($validPaths -join ';')
Set-ItemProperty -Path $regPath -Name Path -Value $newPath

# Вывод отчёта
Write-Host "[✓] Обновлено: переменная PATH очищена."
Write-Host "[→] Резервная копия сохранена в: $backupPath"
Write-Host "`nУдалены следующие несуществующие пути:`n"
$invalidPaths | ForEach-Object { Write-Host " - $_" }
