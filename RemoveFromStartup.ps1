<#
.SYNOPSIS
    Удаляет указанное приложение из автозагрузки Windows.

.DESCRIPTION
    Скрипт удаляет запись из раздела реестра HKCU:\Software\Microsoft\Windows\CurrentVersion\Run,
    что предотвращает автоматический запуск приложения при входе пользователя.

.PARAMETER AppName
    Имя записи в автозагрузке (ключ в реестре), которую необходимо удалить.

.NOTES
    Версия: 2.0
    Автор: Системный администратор
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AppName
)

begin {
    Write-Verbose "Инициализация параметров..."
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
}

process {
    try {
        Write-Verbose "Проверка наличия записи '$AppName' в $RegPath..."
        $Exists = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue | Select-Object -Property $AppName

        if ($null -ne $Exists.$AppName) {
            Write-Verbose "Запись найдена. Удаление..."
            Remove-ItemProperty -Path $RegPath -Name $AppName -ErrorAction Stop

            Write-Output "Запись '$AppName' удалена из автозагрузки."

            Write-Verbose "Проверка результата..."
            $Check = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue | Select-Object -Property $AppName
            if ($null -eq $Check.$AppName) {
                Write-Output "Подтверждено: запись '$AppName' отсутствует в автозагрузке."
            }
            else {
                Write-Warning "Запись '$AppName' все ещё существует после попытки удаления."
            }
        }
        else {
            Write-Output "Запись '$AppName' не найдена в автозагрузке."
        }
    }
    catch {
        Write-Error "Ошибка при удалении записи: $($_.Exception.Message)"
    }
}

end {
    Write-Verbose "Завершение работы скрипта."
}
