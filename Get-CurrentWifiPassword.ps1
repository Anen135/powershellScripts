<#
.SYNOPSIS
    Получает SSID и пароль текущей Wi-Fi сети.

.DESCRIPTION
    Использует netsh для определения активного Wi-Fi подключения,
    затем выводит имя сети (SSID) и её пароль, если он доступен.

.NOTES
    Версия: 2.1
    Автор: Anen
#>

[CmdletBinding()]
param()

begin {
    # Проверка запуска с правами администратора
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin     = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Warning "Некоторые данные (пароль Wi-Fi) могут быть недоступны без прав администратора."
    }
}

process {
    try {
        # Получение SSID
        $wifiName = (netsh wlan show interfaces 2>$null) -match '^\s*SSID\s*:\s*(.+)$' |
                    ForEach-Object { ($_ -split ':')[1].Trim() }

        if (-not $wifiName) {
            Write-Warning "Активное Wi-Fi подключение не найдено."
            return
        }

        Write-Output "Текущая Wi-Fi сеть: $wifiName"

        # Получение профиля с ключом с перекодировкой (CP866 → UTF8)
        $raw = netsh wlan show profile name="$wifiName" key=clear
        $profileInfo = $raw | ForEach-Object {
            [Text.Encoding]::UTF8.GetString(
                [Text.Encoding]::GetEncoding(866).GetBytes($_)
            )
        }

        # Ищем пароль (RU и EN локализации)
        $passwordLine = $profileInfo | Select-String -Pattern "Содержимое ключа\s*:\s*(.+)$","Key Content\s*:\s*(.+)$"

        if ($passwordLine) {
            $password = $passwordLine.Matches[0].Groups[1].Value.Trim()
            Write-Output "Пароль: $password"
        }
        else {
            Write-Output "Пароль не найден или сеть не защищена."
        }


    }
    catch {
        Write-Error "Ошибка при получении информации о Wi-Fi: $($_.Exception.Message)"
    }
}

end {
    Write-Verbose "Скрипт завершён."
}
