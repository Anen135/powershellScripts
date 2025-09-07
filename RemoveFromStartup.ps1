<#
.SYNOPSIS
    Удаляет приложение из автозагрузки Windows.
.DESCRIPTION
    Скрипт удаляет указанное приложение из реестра, чтобы оно не запускалось при входе пользователя в систему.
.NOTES
    Версия: 1.1
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$AppName    # Имя записи в реестре для удаления
)

try {
    # Проверим, есть ли запись
    $exists = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue | Select-Object -Property $AppName

    if ($null -ne $exists.$AppName) {
        # Удаляем запись
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $AppName
        Write-Host "✅ Запись '$AppName' удалена из автозагрузки."

        # Проверяем, что удалено
        $check = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue | Select-Object -Property $AppName
        if ($null -eq $check.$AppName) {
            Write-Host "✔ Подтверждено: запись '$AppName' больше не существует."
        }
        else {
            Write-Host "⚠ Запись '$AppName' все ещё присутствует!"
        }
    }
    else {
        Write-Host "ℹ Запись '$AppName' не найдена в автозагрузке."
    }
}
catch {
    Write-Host "❌ Ошибка: $($_.Exception.Message)"
}
