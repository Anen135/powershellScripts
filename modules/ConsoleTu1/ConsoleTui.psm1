# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Windows Restore Manager

Set-StrictMode -Version 2.0

$script:Initialized = $false
$script:ApplicationTitle = 'Console TUI'
$script:OriginalState = $null
$script:FrameActive = $false
$script:FrameLines = New-Object System.Collections.ArrayList
$script:LastFrame = @()
$script:LastWidth = 0
$script:LastHeight = 0
$script:PendingInputKey = $null

function Initialize-ConsoleTui {
    [CmdletBinding()]
    param(
        [string]$Title = 'Console TUI'
    )

    if (-not $script:Initialized) {
        $cursorVisible = $true
        $foreground = [ConsoleColor]::Gray
        $background = [ConsoleColor]::Black
        $consoleTitle = ''
        $treatControlCAsInput = $false

        try { $cursorVisible = [Console]::CursorVisible } catch {}
        try { $foreground = [Console]::ForegroundColor } catch {}
        try { $background = [Console]::BackgroundColor } catch {}
        try { $consoleTitle = [Console]::Title } catch {}
        try { $treatControlCAsInput = [Console]::TreatControlCAsInput } catch {}

        $script:OriginalState = [pscustomobject]@{
            CursorVisible = $cursorVisible
            Foreground = $foreground
            Background = $background
            Title = $consoleTitle
            TreatControlCAsInput = $treatControlCAsInput
        }
        $script:Initialized = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        $script:ApplicationTitle = $Title
    }

    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
    try { [Console]::InputEncoding = [Text.Encoding]::UTF8 } catch {}
    try { [Console]::Title = $script:ApplicationTitle } catch {}
    try { [Console]::TreatControlCAsInput = $true } catch {}
    try { [Console]::CursorVisible = $false } catch {}

    $script:FrameActive = $false
    $script:FrameLines.Clear()
    $script:LastFrame = @()
    $script:LastWidth = 0
    $script:LastHeight = 0
    $script:PendingInputKey = $null
}

function Restore-ConsoleTui {
    [CmdletBinding()]
    param()

    if ($null -ne $script:OriginalState) {
        try { [Console]::CursorVisible = $script:OriginalState.CursorVisible } catch {}
        try { [Console]::ForegroundColor = $script:OriginalState.Foreground } catch {}
        try { [Console]::BackgroundColor = $script:OriginalState.Background } catch {}
        try { [Console]::Title = $script:OriginalState.Title } catch {}
        try { [Console]::TreatControlCAsInput = $script:OriginalState.TreatControlCAsInput } catch {}
    }

    try { [Console]::ResetColor() } catch {}

    $script:FrameActive = $false
    $script:FrameLines.Clear()
    $script:LastFrame = @()
    $script:PendingInputKey = $null
}

function Get-ConsoleTuiWidth {
    [CmdletBinding()]
    param()

    try {
        # Do not write into the last physical column. Classic conhost and some
        # Windows Terminal configurations wrap that column and scroll.
        return [Math]::Max(1, [Console]::WindowWidth - 1)
    }
    catch {
        return 119
    }
}

function Get-ConsoleTuiHeight {
    [CmdletBinding()]
    param()

    try {
        return [Math]::Max(1, [Console]::WindowHeight)
    }
    catch {
        return 35
    }
}

function Format-ConsoleTuiText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [int]$Width
    )

    if ($Width -le 0) { return '' }
    if ($null -eq $Text) { $Text = '' }

    $Text = $Text -replace "`r|`n", ' '

    if ($Text.Length -gt $Width) {
        if ($Width -le 3) {
            return $Text.Substring(0, $Width)
        }

        return ($Text.Substring(0, $Width - 3) + '...')
    }

    return $Text.PadRight($Width)
}

function Format-ConsoleTuiColumns {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Values,

        [Parameter(Mandatory = $true)]
        [int[]]$Widths,

        [string]$Prefix = ' '
    )

    if ($null -eq $Values) { return $Prefix }

    $parts = @()

    for ($i = 0; $i -lt $Values.Count; $i++) {
        $value = [string]$Values[$i]

        if ($i -lt $Widths.Count) {
            $width = [Math]::Max(1, [int]$Widths[$i])
            $parts += Format-ConsoleTuiText -Text $value -Width $width
        }
        else {
            $parts += $value
        }
    }

    return ($Prefix + ($parts -join ' '))
}

function New-ConsoleTuiFrameLine {
    param(
        [string]$Text,
        [ConsoleColor]$Foreground,
        [ConsoleColor]$Background
    )

    return [pscustomobject]@{
        Text = $Text
        Foreground = $Foreground
        Background = $Background
    }
}

function Start-ConsoleTuiFrame {
    [CmdletBinding()]
    param()

    $script:FrameActive = $true
    $script:FrameLines.Clear()
}

function Write-ConsoleTuiLine {
    [CmdletBinding()]
    param(
        [string]$Text = '',
        [ConsoleColor]$Foreground = [ConsoleColor]::Gray,
        [ConsoleColor]$Background = [ConsoleColor]::Black,
        [switch]$NoNewline
    )

    if ($script:FrameActive) {
        [void]$script:FrameLines.Add(
            (New-ConsoleTuiFrameLine -Text $Text -Foreground $Foreground -Background $Background)
        )
        return
    }

    $oldForeground = try { [Console]::ForegroundColor } catch { [ConsoleColor]::Gray }
    $oldBackground = try { [Console]::BackgroundColor } catch { [ConsoleColor]::Black }

    try {
        [Console]::ForegroundColor = $Foreground
        [Console]::BackgroundColor = $Background

        if ($NoNewline) {
            [Console]::Write($Text)
        }
        else {
            [Console]::WriteLine($Text)
        }
    }
    finally {
        try { [Console]::ForegroundColor = $oldForeground } catch {}
        try { [Console]::BackgroundColor = $oldBackground } catch {}
    }
}

function Clear-ConsoleTuiPhysicalLine {
    param(
        [int]$Row,
        [int]$Width
    )

    try {
        if ($Row -lt 0 -or $Row -ge [Console]::BufferHeight) { return }

        [Console]::SetCursorPosition(0, $Row)
        [Console]::ForegroundColor = [ConsoleColor]::Gray
        [Console]::BackgroundColor = [ConsoleColor]::Black
        [Console]::Write((' ' * $Width))
    }
    catch {}
}

function Complete-ConsoleTuiFrame {
    [CmdletBinding()]
    param()

    $script:FrameActive = $false

    $width = Get-ConsoleTuiWidth
    $height = Get-ConsoleTuiHeight
    $maxRows = [Math]::Max(1, $height - 1)

    if ($script:LastWidth -ne 0 -and
        ($script:LastWidth -ne $width -or $script:LastHeight -ne $height)) {
        try { [Console]::Clear() } catch {}
        $script:LastFrame = @()
    }

    $newFrame = @()
    $count = [Math]::Min($script:FrameLines.Count, $maxRows)

    for ($i = 0; $i -lt $count; $i++) {
        $source = $script:FrameLines[$i]
        $line = New-ConsoleTuiFrameLine `
            -Text (Format-ConsoleTuiText -Text ([string]$source.Text) -Width $width) `
            -Foreground $source.Foreground `
            -Background $source.Background

        $newFrame += $line
        $changed = $true

        if ($i -lt $script:LastFrame.Count) {
            $old = $script:LastFrame[$i]
            $changed = (
                $old.Text -ne $line.Text -or
                $old.Foreground -ne $line.Foreground -or
                $old.Background -ne $line.Background
            )
        }

        if (-not $changed) { continue }

        try {
            [Console]::SetCursorPosition(0, $i)
            [Console]::ForegroundColor = $line.Foreground
            [Console]::BackgroundColor = $line.Background
            [Console]::Write($line.Text)
        }
        catch {}
    }

    if ($script:LastFrame.Count -gt $newFrame.Count) {
        $upper = [Math]::Min($script:LastFrame.Count, $maxRows)
        for ($i = $newFrame.Count; $i -lt $upper; $i++) {
            Clear-ConsoleTuiPhysicalLine -Row $i -Width $width
        }
    }

    $script:LastFrame = @($newFrame)
    $script:LastWidth = $width
    $script:LastHeight = $height

    try {
        [Console]::CursorVisible = $false
        $cursorRow = [Math]::Min($newFrame.Count, [Math]::Max(0, $height - 1))
        [Console]::SetCursorPosition(0, $cursorRow)
    }
    catch {}

    try { [Console]::ResetColor() } catch {}
}

function Clear-ConsoleTuiSurface {
    [CmdletBinding()]
    param()

    $script:FrameActive = $false
    $script:FrameLines.Clear()
    $script:LastFrame = @()
    $script:LastWidth = 0
    $script:LastHeight = 0

    try {
        [Console]::CursorVisible = $false
        [Console]::ResetColor()
        [Console]::Clear()
        [Console]::SetCursorPosition(0, 0)
    }
    catch {
        try { Clear-Host } catch {}
    }
}

function Read-ConsoleTuiPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [AllowEmptyString()]
        [string]$Default = ''
    )

    Clear-ConsoleTuiSurface

    try {
        [Console]::CursorVisible = $true
        [Console]::ForegroundColor = [ConsoleColor]::White
        [Console]::BackgroundColor = [ConsoleColor]::Black
    }
    catch {}

    if ($Default) {
        $value = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = $Default
        }
    }
    else {
        $value = Read-Host $Prompt
    }

    try { [Console]::CursorVisible = $false } catch {}
    $script:LastFrame = @()

    return $value
}

function Confirm-ConsoleTui {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    $value = Read-ConsoleTuiPrompt -Prompt "$Prompt (y/N)"
    return $value -match '^(?i:y|yes)$'
}

function Show-ConsoleTuiMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [string[]]$Lines = @(),

        [ConsoleColor]$Color = [ConsoleColor]::White,

        [string]$Footer = 'Press any key to continue...'
    )

    Clear-ConsoleTuiSurface
    Start-ConsoleTuiFrame

    $width = Get-ConsoleTuiWidth
    Write-ConsoleTuiLine `
        -Text (Format-ConsoleTuiText -Text " $script:ApplicationTitle - $Title " -Width $width) `
        -Foreground Black `
        -Background Cyan
    Write-ConsoleTuiLine

    foreach ($line in $Lines) {
        Write-ConsoleTuiLine `
            -Text (Format-ConsoleTuiText -Text $line -Width $width) `
            -Foreground $Color
    }

    Write-ConsoleTuiLine
    Write-ConsoleTuiLine -Text $Footer -Foreground DarkGray
    Complete-ConsoleTuiFrame

    [void][Console]::ReadKey($true)
    $script:LastFrame = @()
}

function Test-ConsoleTuiNavigationKey {
    param([ConsoleKeyInfo]$KeyInfo)

    return $KeyInfo.Key -in @(
        [ConsoleKey]::UpArrow,
        [ConsoleKey]::DownArrow,
        [ConsoleKey]::PageUp,
        [ConsoleKey]::PageDown,
        [ConsoleKey]::Home,
        [ConsoleKey]::End
    )
}

function Get-ConsoleTuiKey {
    [CmdletBinding()]
    param()

    if ($null -ne $script:PendingInputKey) {
        $key = $script:PendingInputKey
        $script:PendingInputKey = $null
        return $key
    }

    try {
        $keyAvailable = [Console]::KeyAvailable
    }
    catch {
        return $null
    }

    if (-not $keyAvailable) {
        return $null
    }

    $key = [Console]::ReadKey($true)

    if (-not (Test-ConsoleTuiNavigationKey $key)) {
        return $key
    }

    while ([Console]::KeyAvailable) {
        $next = [Console]::ReadKey($true)

        if ((Test-ConsoleTuiNavigationKey $next) -and
            $next.Key -eq $key.Key -and
            $next.Modifiers -eq $key.Modifiers) {
            continue
        }

        $script:PendingInputKey = $next
        break
    }

    return $key
}

function Clear-ConsoleTuiInputBacklog {
    [CmdletBinding()]
    param()

    while ($true) {
        try {
            $keyAvailable = [Console]::KeyAvailable
        }
        catch {
            return
        }

        if (-not $keyAvailable) { return }

        $next = [Console]::ReadKey($true)

        if (Test-ConsoleTuiNavigationKey $next) {
            continue
        }

        $script:PendingInputKey = $next
        break
    }
}

function ConvertTo-ConsoleTuiWindowsArgument {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0

    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $slashes++
            continue
        }

        if ($character -eq '"') {
            [void]$builder.Append((('\' * ($slashes * 2 + 1)) -join ''))
            [void]$builder.Append('"')
            $slashes = 0
            continue
        }

        if ($slashes -gt 0) {
            [void]$builder.Append((('\' * $slashes) -join ''))
            $slashes = 0
        }
        [void]$builder.Append($character)
    }

    if ($slashes -gt 0) {
        [void]$builder.Append((('\' * ($slashes * 2)) -join ''))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Stop-ConsoleTuiProcess {
    param([Diagnostics.Process]$Process)

    if ($null -eq $Process -or $Process.HasExited) { return }

    if ($env:OS -eq 'Windows_NT') {
        try {
            & taskkill.exe /PID $Process.Id /T /F *> $null
        }
        catch {}
    }

    if (-not $Process.HasExited) {
        try { $Process.Kill() } catch {}
    }
}

function Show-ConsoleTuiOperation {
    param(
        [string]$Title,
        [string]$Detail,
        [int]$Frame,
        [TimeSpan]$Elapsed
    )

    $spinner = @('|', '/', '-', '\')[$Frame % 4]
    $width = Get-ConsoleTuiWidth

    Start-ConsoleTuiFrame
    Write-ConsoleTuiLine `
        -Text (Format-ConsoleTuiText -Text " $script:ApplicationTitle - operation " -Width $width) `
        -Foreground Black `
        -Background Cyan
    Write-ConsoleTuiLine
    Write-ConsoleTuiLine `
        -Text (Format-ConsoleTuiText -Text ("  {0} {1}" -f $spinner, $Title) -Width $width) `
        -Foreground Cyan
    Write-ConsoleTuiLine

    if ($Detail) {
        Write-ConsoleTuiLine `
            -Text (Format-ConsoleTuiText -Text ("  " + $Detail) -Width $width) `
            -Foreground Gray
    }
    else {
        Write-ConsoleTuiLine
    }

    Write-ConsoleTuiLine `
        -Text (Format-ConsoleTuiText -Text ("  Elapsed: {0:hh\:mm\:ss}" -f $Elapsed) -Width $width) `
        -Foreground DarkGray
    Write-ConsoleTuiLine
    Write-ConsoleTuiLine `
        -Text (Format-ConsoleTuiText -Text '  ESC = cancel operation' -Width $width) `
        -Foreground Yellow
    Complete-ConsoleTuiFrame
}

function Invoke-ConsoleTuiProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [AllowEmptyCollection()]
        [string[]]$ArgumentList = @(),

        [string]$Title = 'Working',

        [string]$Detail = '',

        [ValidateRange(20, 5000)]
        [int]$RefreshMilliseconds = 120
    )

    Clear-ConsoleTuiInputBacklog

    $processInfo = New-Object Diagnostics.ProcessStartInfo
    $processInfo.FileName = $FilePath
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
    $processInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
    $processInfo.Arguments = (($ArgumentList | ForEach-Object {
        ConvertTo-ConsoleTuiWindowsArgument -Value ([string]$_)
    }) -join ' ')

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $processInfo

    if (-not $process.Start()) {
        throw "Failed to start process: $FilePath"
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $frame = 0
    $cancelled = $false

    try {
        while (-not $process.HasExited) {
            Show-ConsoleTuiOperation `
                -Title $Title `
                -Detail $Detail `
                -Frame $frame `
                -Elapsed $stopwatch.Elapsed
            $frame++

            $until = [DateTime]::UtcNow.AddMilliseconds($RefreshMilliseconds)
            while ([DateTime]::UtcNow -lt $until -and -not $process.HasExited) {
                $key = Get-ConsoleTuiKey

                if ($null -ne $key -and $key.Key -eq [ConsoleKey]::Escape) {
                    $cancelled = $true
                    Stop-ConsoleTuiProcess -Process $process
                    break
                }

                Start-Sleep -Milliseconds 20
            }

            if ($cancelled) { break }
        }

        if (-not $process.HasExited) {
            try { $process.WaitForExit(3000) | Out-Null } catch {}
        }
        else {
            $process.WaitForExit()
        }

        if (-not $process.HasExited) {
            Stop-ConsoleTuiProcess -Process $process
            try { $process.WaitForExit(3000) | Out-Null } catch {}
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = if ($process.HasExited) { $process.ExitCode } else { $null }

        return [pscustomobject]@{
            Cancelled = $cancelled
            ExitCode = $exitCode
            StdOut = $stdout
            StdErr = $stderr
        }
    }
    finally {
        $stopwatch.Stop()
        $process.Dispose()
    }
}

Export-ModuleMember -Function @(
    'Initialize-ConsoleTui',
    'Restore-ConsoleTui',
    'Get-ConsoleTuiWidth',
    'Get-ConsoleTuiHeight',
    'Format-ConsoleTuiText',
    'Format-ConsoleTuiColumns',
    'Start-ConsoleTuiFrame',
    'Write-ConsoleTuiLine',
    'Complete-ConsoleTuiFrame',
    'Clear-ConsoleTuiSurface',
    'Read-ConsoleTuiPrompt',
    'Confirm-ConsoleTui',
    'Show-ConsoleTuiMessage',
    'Get-ConsoleTuiKey',
    'Clear-ConsoleTuiInputBacklog',
    'Invoke-ConsoleTuiProcess'
)

$ExecutionContext.SessionState.Module.OnRemove = {
    Restore-ConsoleTui
}
