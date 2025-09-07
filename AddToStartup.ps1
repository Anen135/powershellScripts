<#
.SYNOPSIS
    Добавляет приложение в автозагрузку Windows.
.DESCRIPTION
    Скрипт добавляет указанное приложение в реестр для автозапуска при входе пользователя в систему.
.NOTES
    Версия: 1.1
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$AppName,     # Имя записи в реестре

    [Parameter(Mandatory = $true)]
    [string]$AppPath      # Полный путь к приложению
)

# Формируем команду для запуска через cmd
$CmdValue = "cmd /c `"$AppPath`""

try {
    # Добавляем в HKCU автозагрузку
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $AppName -Value $CmdValue

    Write-Host "✅ Запись '$AppName' успешно добавлена в автозагрузку."
    Write-Host "`n📋 Проверка записи в HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`n"

    # Проверяем наличие записи
    $check = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" | Select-Object -Property $AppName

    if ($check.$AppName -eq $CmdValue) {
        Write-Host "✔ Найдена запись:"
        Write-Host "Имя: $AppName"
        Write-Host "Значение: $($check.$AppName)"
    }
    else {
        Write-Host "⚠ Запись не найдена или отличается!"
    }
}
catch {
    Write-Host "❌ Ошибка: $($_.Exception.Message)"
}
