<#
.SYNOPSIS
    Очищает пользовательскую переменную среды PATH от несуществующих путей.

.DESCRIPTION
    Делает резервную копию PATH, удаляет только несуществующие директории,
    обновляет значение в реестре и сообщает список удалённых путей.
    Если изменений нет — завершает работу без обновления PATH.

.NOTES
    Версия: 2.0
    Автор: Системный администратор
#>

[CmdletBinding()]
param()

begin {
    $regPath   = "HKCU:\Environment"
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $env:USERPROFILE "Desktop\user-path-backup-$timestamp.txt"

    Write-Verbose "Регистровый путь: $regPath"
    Write-Verbose "Путь для резервной копии: $backupPath"
}

process {
    try {
        if (-not (Test-Path $regPath)) {
            throw "Раздел реестра $regPath не существует."
        }

        $oldPath = (Get-ItemProperty -Path $regPath -Name Path -ErrorAction Stop).Path
        if ([string]::IsNullOrWhiteSpace($oldPath)) {
            Write-Warning "Переменная PATH отсутствует или пуста."
            return
        }

        $pathList    = $oldPath -split ';'
        $validPaths  = @()
        $invalidPaths = @()

        foreach ($path in $pathList) {
            if ([string]::IsNullOrWhiteSpace($path)) { continue }

            $trimmed = $path.Trim().TrimEnd('\')

            if (Test-Path $trimmed) {
                $validPaths += $trimmed
            } else {
                $invalidPaths += $path
            }
        }

        if ($invalidPaths.Count -eq 0) {
            Write-Output "Все пути в PATH существуют. Изменений не требуется."
            return
        }

        # Сначала вычисляем новый PATH
        $newPath = $validPaths -join ';'

        # Потом создаём объект для бэкапа (теперь $newPath существует)
        $backupObject = [PSCustomObject]@{
            Timestamp     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            OriginalPath  = $oldPath
            OriginalPaths = $pathList
            ValidPaths    = $validPaths
            InvalidPaths  = $invalidPaths
            NewPath       = $newPath
            RemovedCount  = $invalidPaths.Count
        }

        # Сохраняем JSON-бэкап
        $backupPath = Join-Path $env:USERPROFILE "Desktop\user-path-backup-$timestamp.json"
        $backupObject | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupPath -Encoding UTF8 -Force

        Write-Output "Резервная копия сохранена в JSON: $backupPath"
        Write-Output "Удалено несуществующих путей: $($invalidPaths.Count)"

        # Обновляем реестр
        Set-ItemProperty -Path $regPath -Name Path -Value $newPath -ErrorAction Stop
        Write-Output "Переменная PATH успешно обновлена."
    }
    catch {
        Write-Error "Ошибка при обновлении PATH: $($_.Exception.Message)"
        exit 1
    }
}

end {
    Write-Verbose "Завершение работы скрипта."
}
