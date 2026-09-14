$since = (Get-Date).AddHours(-24)
Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = $since } -ErrorAction SilentlyContinue |
    Select-Object -First 100 TimeCreated, Id, ProviderName, LevelDisplayName, Message
