<#
.SYNOPSIS
    Получает SSID и пароль текущей Wi-Fi сети.

.DESCRIPTION
    Использует netsh для определения активного Wi-Fi подключения,
    затем выводит имя сети (SSID) и её пароль, если он доступен.

.NOTES
    Версия: 2.3 Encoding fix
    Автор: Anen
#>

[CmdletBinding()]
param()

begin {
    # КРИТИЧЕСКИ ВАЖНО: Установка кодовой страницы 866 для корректного чтения вывода netsh в русской локали
    [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(866)
    $OutputEncoding = [System.Text.Encoding]::GetEncoding(866)

    # Проверка прав администратора
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin     = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Warning "Некоторые данные (пароль Wi-Fi) могут быть недоступны без прав администратора."
    }
}

process {
    try {
        # Получение SSID текущего подключения
        $wifiName = (netsh wlan show interfaces) -match '^\s*SSID\s*:\s*(.+)$' |
                    ForEach-Object { ($_ -split ':', 2)[1].Trim() }

        if (-not $wifiName) {
            Write-Warning "Активное Wi-Fi подключение не найдено."
            return
        }

        Write-Output "Текущая Wi-Fi сеть: $wifiName"

        # Получение профиля с паролем (вывод приходит в CP866)
        $profileInfo = netsh wlan show profile name="$wifiName" key=clear

        # Поиск пароля: обрабатываем каждую строку отдельно
        $password = $null
        foreach ($line in $profileInfo) {
            if ($line -match '(?:Содержимое ключа|Key Content)\s*:\s*(.+)') {
                $password = $matches[1].Trim()
                break
            }
        }

        if ($password) {
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