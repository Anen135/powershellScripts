# === PATH Editor ===
param( [switch]$Current )
if ($Current) {
    $currentPath = (Get-Location).Path

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if ($userPath -split ";" | Where-Object { $_ -eq $currentPath }) { Write-Host "Path already exists in PATH." -ForegroundColor Yellow }
    else {
        $newPath = "$userPath;$currentPath"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "Added to PATH: $currentPath" -ForegroundColor Green
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") 
    }

    return
}

$paths = ($env:Path -split ';') | Where-Object { $_ -and $_.Trim() }
$paths += ""  # пустая строка для добавления новой
$selectedIndex = 0
$message = $null

function Get-UILayout {
    $height = [Console]::WindowHeight
    $width  = [Console]::WindowWidth

    [PSCustomObject]@{
        HeaderLine     = 0
        SeparatorLine  = 1
        ListStart      = 2
        ListLines      = [Math]::Max(5, $height - 8)  # заголовок, разделитель, 2 строки ввода, сообщение, подсказка
        EditLabelLine  = $height - 6                 # "Editing: ..."
        EditInputLine  = $height - 5                 # строка ввода
        MessageLine    = $height - 3
        HintLine       = $height - 2
        WindowWidth    = $width
    }
}

function Clear-Line {
    param([int]$line)
    [Console]::SetCursorPosition(0, $line)
    [Console]::Write(" " * ([Console]::WindowWidth - 1))
}

function Show-PathList {
    param(
        [string[]]$paths,
        [int]$selectedIndex,
        [PSCustomObject]$layout
    )

    $top = $layout.ListStart
    $maxLines = $layout.ListLines
    $half = [Math]::Floor($maxLines / 2)
    $start = [Math]::Max(0, $selectedIndex - $half)
    if ($start + $maxLines -gt $paths.Length) {
        $start = [Math]::Max(0, $paths.Length - $maxLines)
    }

    for ($i = 0; $i -lt $maxLines; $i++) {
        $row = $start + $i
        [Console]::SetCursorPosition(0, $top + $i)

        if ($row -lt $paths.Length) {
            $prefix = if ($row -eq $selectedIndex) { "> " } else { "  " }
            $line = "$prefix[$row] $($paths[$row])"
            [Console]::Write($line.PadRight($layout.WindowWidth - 1))
        } else {
            [Console]::Write(" " * ($layout.WindowWidth - 1))
        }
    }
}

function Show-UI {
    param(
        [string[]]$paths,
        [int]$selectedIndex,
        [string]$message
    )

    $layout = Get-UILayout

    # Заголовок
    [Console]::SetCursorPosition(0, $layout.HeaderLine)
    $header = "Edit PATH entries (total: $($paths.Length - 1) real paths)"
    Write-Host $header.PadRight($layout.WindowWidth - 1) -ForegroundColor Cyan

    # Разделитель
    Clear-Line $layout.SeparatorLine

    # Список путей
    Show-PathList -paths $paths -selectedIndex $selectedIndex -layout $layout

    # Очистка строк редактирования (на всякий случай)
    Clear-Line $layout.EditLabelLine
    Clear-Line $layout.EditInputLine

    # Сообщение
    Clear-Line $layout.MessageLine
    if ($message) {
        [Console]::SetCursorPosition(0, $layout.MessageLine)
        $color = switch -Wildcard ($message) {
            "*cancelled*" { "Yellow" }
            "*error*"     { "Red" }
            "*Nothing*"   { "Gray" }
            "*No changes*" { "Gray" }
            default       { "Green" }
        }
        Write-Host $message -ForegroundColor $color -NoNewline
    }

    # Подсказка
    [Console]::SetCursorPosition(0, $layout.HintLine)
    $hint = "Arrows: navigate | Enter: edit | Del: delete | S: save | Esc: exit"
    Write-Host $hint -ForegroundColor Yellow -NoNewline
    [Console]::Write(" " * ($layout.WindowWidth - 1 - $hint.Length))

    [Console]::CursorVisible = $false
}

# === Основной цикл ===
[Console]::Clear()
$running = $true

while ($running) {
    Show-UI -paths $paths -selectedIndex $selectedIndex -message $message
    $message = $null

    $key = [Console]::ReadKey($true)

    switch ($key.Key) {
        'DownArrow' {
            $selectedIndex = ($selectedIndex + 1) % $paths.Length
        }
        'UpArrow' {
            $selectedIndex = if ($selectedIndex -le 0) { $paths.Length - 1 } else { $selectedIndex - 1 }
        }

        'Enter' {
            if ($selectedIndex -ge $paths.Length) { continue }
            $currentValue = $paths[$selectedIndex]
            $layout = Get-UILayout

            # Показываем строки редактирования
            Clear-Line $layout.EditLabelLine
            [Console]::SetCursorPosition(0, $layout.EditLabelLine)
            Write-Host "Editing: [$selectedIndex] $currentValue" -ForegroundColor Cyan

            Clear-Line $layout.EditInputLine
            [Console]::SetCursorPosition(0, $layout.EditInputLine)
            Write-Host "New value (empty = keep current): " -ForegroundColor Cyan -NoNewline

            [Console]::CursorVisible = $true
            $newValue = Read-Host
            [Console]::CursorVisible = $false

            # Сразу стираем строки редактирования
            Clear-Line $layout.EditLabelLine
            Clear-Line $layout.EditInputLine

            if ([string]::IsNullOrWhiteSpace($newValue)) {
                $message = "No changes made."
            } else {
                $paths[$selectedIndex] = $newValue.Trim()
                if ($selectedIndex -eq $paths.Length - 1) {
                    $paths += ""
                }
                $message = "Entry updated."
            }
        }

        'S' {
            $cleanPaths = $paths | Where-Object { $_ -and $_.Trim() }
            [Environment]::SetEnvironmentVariable("Path", ($cleanPaths -join ';'), "User")
            $env:Path = [Environment]::GetEnvironmentVariable("Path", "User")
            $message = "PATH saved successfully (User scope). Restart apps or logoff to apply."
        }

        'Delete' {
            if ($selectedIndex -ge $paths.Length -or [string]::IsNullOrWhiteSpace($paths[$selectedIndex])) {
                $message = "Nothing to delete."
                continue
            }

            $layout = Get-UILayout
            Clear-Line $layout.MessageLine
            [Console]::SetCursorPosition(0, $layout.MessageLine)
            Write-Host "Press DELETE again to confirm removal of entry [$selectedIndex]" -ForegroundColor Red

            $confirm = [Console]::ReadKey($true)

            if ($confirm.Key -eq 'Delete') {
                $list = [System.Collections.ArrayList]$paths
                $list.RemoveAt($selectedIndex)
                $paths = $list.ToArray()
                if ($paths.Length -eq 0 -or $paths[-1] -ne "") { $paths += "" }
                $selectedIndex = [Math]::Min($selectedIndex, $paths.Length - 1)
                $message = "Entry removed."
            } else {
                $message = "Deletion cancelled."
            }
        }

        'Escape' {
            $running = $false
        }
    }
}

[Console]::Clear()
Write-Host "Goodbye!" -ForegroundColor Green