
Add-Type -TypeDefinition @"
public enum UserAction
{
    None,
    NavigateUp,
    NavigateDown,
    OpenItem,
    GoToParent,
    DeleteItem,
    Exit
}
"@ -ErrorAction SilentlyContinue

$keyToActionMap = @{
    'UpArrow'    = [UserAction]::NavigateUp
    'DownArrow'  = [UserAction]::NavigateDown
    'Enter'      = [UserAction]::OpenItem
    'Delete'     = [UserAction]::DeleteItem
    'Escape'     = [UserAction]::Exit

    'Backspace'  = [UserAction]::GoToParent
    'S'          = [UserAction]::GoToParent
}

function Get-UserActionFromKey {
    param([System.ConsoleKeyInfo]$key)

    
    $consoleKeyStr = $key.Key.ToString()
    if ($keyToActionMap.ContainsKey($consoleKeyStr)) {
        return $keyToActionMap[$consoleKeyStr]
    }

    
    $charStr = $key.KeyChar
    if ($charStr -ne 0 -and $keyToActionMap.ContainsKey($charStr)) {
        return $keyToActionMap[$charStr]
    }

    
    return [UserAction]::None
}


[Console]::CursorVisible = $false

$cwd = Get-Location
$items = Get-ChildItem -Force | Sort-Object PSIsContainer, Name
$selectedIndex = 0
$message = $null

function Get-UILayout {
    $height = [Console]::WindowHeight
    $width  = [Console]::WindowWidth

    [PSCustomObject]@{
        HeaderLine     = 0
        SeparatorLine  = 1
        ListStart      = 2
        ListLines      = [Math]::Max(10, $height - 8)
        MessageLine    = $height - 3
        HintLine       = $height - 2
        FooterLine     = $height - 1
        WindowWidth    = $width
    }
}

function Clear-Line {
    param([int]$line)
    [Console]::SetCursorPosition(0, $line)
    [Console]::Write(" " * ([Console]::WindowWidth - 1))
}

function Update-Header {
    $layout = Get-UILayout
    [Console]::SetCursorPosition(0, $layout.HeaderLine)
    $header = "Current directory: $cwd"
    Write-Host $header -ForegroundColor Cyan -NoNewline
    [Console]::Write(" " * ($layout.WindowWidth - $header.Length - 1))
}

function Update-Separator {
    $layout = Get-UILayout
    Clear-Line $layout.SeparatorLine
    [Console]::SetCursorPosition(0, $layout.SeparatorLine)
    [Console]::Write("-" * ($layout.WindowWidth - 1))
}

function Update-ItemList {
    param(
        [System.IO.FileSystemInfo[]]$items,
        [int]$selectedIndex
    )
    $layout = Get-UILayout
    $top = $layout.ListStart
    $maxLines = $layout.ListLines
    $half = [Math]::Floor($maxLines / 2)
    $start = [Math]::Max(0, $selectedIndex - $half)
    if ($start + $maxLines -gt $items.Length) {
        $start = [Math]::Max(0, $items.Length - $maxLines)
    }

    for ($i = 0; $i -lt $maxLines; $i++) {
        $row = $start + $i
        [Console]::SetCursorPosition(0, $top + $i)

        if ($row -lt $items.Length) {
            $item = $items[$row]
            $prefix = if ($row -eq $selectedIndex) { "> " } else { "  " }
            $type = if ($item.PSIsContainer) { "[DIR] " } else { "[FILE] " }
            $line = "$prefix$type$item"

            [Console]::Write($line)
            $remaining = $layout.WindowWidth - $line.Length - 1
            if ($remaining -gt 0) {
                [Console]::Write(" " * $remaining)
            }
        } else {
            [Console]::Write(" " * ($layout.WindowWidth - 1))
        }
    }
}

function Update-Message {
    param([string]$msg)
    $layout = Get-UILayout
    Clear-Line $layout.MessageLine

    if ($msg) {
        [Console]::SetCursorPosition(0, $layout.MessageLine)
        $color = switch -Wildcard ($msg) {
            "*not empty*"   { "Yellow" }
            "*Cannot*"      { "Red" }
            "*Error*"       { "Red" }
            "*confirm*"     { "Yellow" }
            "*cancelled*"   { "Yellow" }
            "*root*"        { "Yellow" }
            "*deleted*"     { "Red" }
            default         { "Green" }
        }
        Write-Host $msg -ForegroundColor $color -NoNewline
        [Console]::Write(" " * ($layout.WindowWidth - $msg.Length - 1))
    }
}

function Update-Hint {
    $layout = Get-UILayout
    Clear-Line $layout.HintLine
    [Console]::SetCursorPosition(0, $layout.HintLine)
    $hint = "Arrows: navigate (cyclic) | Enter: open folder | S: parent | Del: delete | Esc: exit"
    Write-Host $hint -ForegroundColor Yellow -NoNewline
    [Console]::Write(" " * ($layout.WindowWidth - $hint.Length - 1))
}

function Update-Footer {
    $layout = Get-UILayout
    Clear-Line $layout.FooterLine
}


[Console]::Clear()
Update-Header
Update-Separator
Update-ItemList -items $items -selectedIndex $selectedIndex
Update-Message -msg $null
Update-Hint
Update-Footer


$running = $true

while ($running) {
    $message = $null

    $key = [Console]::ReadKey($true)
    $action = Get-UserActionFromKey -key $key

    switch ($action) {
        ([UserAction]::NavigateUp) {
            if ($items.Length -eq 0) { continue }
            $selectedIndex = if ($selectedIndex -le 0) { $items.Length - 1 } else { $selectedIndex - 1 }
            Update-ItemList -items $items -selectedIndex $selectedIndex
        }
        ([UserAction]::NavigateDown) {
            if ($items.Length -eq 0) { continue }
            $selectedIndex = ($selectedIndex + 1) % $items.Length
            Update-ItemList -items $items -selectedIndex $selectedIndex
        }
        ([UserAction]::OpenItem) {
            if ($items.Length -eq 0) { continue }
            $item = $items[$selectedIndex]
            if ($item.PSIsContainer) {
                try {
                    Set-Location $item.FullName -ErrorAction Stop
                    $cwd = Get-Location
                    $items = Get-ChildItem -Force | Sort-Object PSIsContainer, Name
                    $selectedIndex = 0

                    Update-Header
                    Update-ItemList -items $items -selectedIndex $selectedIndex
                    Update-Message -msg "Entered folder: $($item.Name)"
                } catch {
                    Update-Message -msg "Cannot enter folder: $($item.Name) (access denied)"
                }
            } else {
                Update-Message -msg "Cannot enter a file: $($item.Name)"
            }
        }
        ([UserAction]::GoToParent) {
            $parent = Split-Path -Path $cwd -Parent
            if ($parent) {
                Set-Location $parent
                $cwd = Get-Location
                $items = Get-ChildItem -Force | Sort-Object PSIsContainer, Name
                $selectedIndex = 0

                Update-Header
                Update-ItemList -items $items -selectedIndex $selectedIndex
                Update-Message -msg "Moved to parent folder"
            } else {
                Update-Message -msg "Already at root directory."
            }
        }
        ([UserAction]::DeleteItem) {
            if ($items.Length -eq 0) { continue }
            $item = $items[$selectedIndex]

            Update-Message -msg "Press DELETE again to confirm deletion of '$($item.Name)'"

            $confirmKey = [Console]::ReadKey($true)
            if ($confirmKey.Key -ne 'Delete') {
                Update-Message -msg "Deletion cancelled."
                continue
            }

            try {
                if ($item.PSIsContainer) {
                    $childCount = (Get-ChildItem -LiteralPath $item.FullName -Force -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
                    if ($childCount -gt 0) {
                        Update-Message -msg "Folder '$($item.Name)' is not empty - only empty folders can be deleted."
                        continue
                    }
                    Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                    Update-Message -msg "Folder '$($item.Name)' deleted."
                } else {
                    Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                    Update-Message -msg "File '$($item.Name)' deleted."
                }

                $items = Get-ChildItem -Force | Sort-Object PSIsContainer, Name
                if ($selectedIndex -ge $items.Length -and $items.Length -gt 0) {
                    $selectedIndex = $items.Length - 1
                }
                Update-ItemList -items $items -selectedIndex $selectedIndex
            } catch {
                Update-Message -msg "Error deleting '$($item.Name)': $($_.Exception.Message)"
            }
        }
        ([UserAction]::Exit) {
            $running = $false
        }
}
}

[Console]::Clear()
[Console]::CursorVisible = $true
Write-Host "Goodbye!" -ForegroundColor Green