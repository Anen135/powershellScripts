<#
.SYNOPSIS
    Добавляет указанное приложение в автозагрузку Windows.

.DESCRIPTION
    Скрипт регистрирует путь к приложению в разделе реестра HKCU:\Software\Microsoft\Windows\CurrentVersion\Run
    для автоматического запуска при входе пользователя в систему.

.PARAMETER AppName
    Имя записи в автозагрузке (ключ в реестре).

.PARAMETER AppPath
    Полный путь к исполняемому файлу приложения.

.NOTES
    Версия: 2.0
    Автор: Системный администратор
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AppName,

    [Parameter(Mandatory = $true)]
    [ValidateScript({Test-Path $_})]
    [string]$AppPath
)

begin {
    Write-Verbose "Инициализация параметров..."
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $CmdValue = "cmd /c `"$AppPath`""
}

process {
    try {
        Write-Verbose "Добавление записи в реестр: $RegPath"
        Set-ItemProperty -Path $RegPath -Name $AppName -Value $CmdValue -ErrorAction Stop

        Write-Output "Запись '$AppName' успешно добавлена в автозагрузку."

        Write-Verbose "Проверка результата..."
        $Check = Get-ItemProperty -Path $RegPath -ErrorAction Stop | Select-Object -Property $AppName

        if ($Check.$AppName -eq $CmdValue) {
            Write-Output "Проверка завершена успешно:"
            Write-Output "Имя: $AppName"
            Write-Output "Значение: $($Check.$AppName)"
        }
        else {
            Write-Warning "Запись '$AppName' не совпадает с ожидаемым значением."
        }
    }
    catch {
        Write-Error "Ошибка при добавлении записи в автозагрузку: $($_.Exception.Message)"
    }
}

end {
    Write-Verbose "Завершение работы скрипта."
}
