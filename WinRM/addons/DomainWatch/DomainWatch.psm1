#Requires -Version 5.1
Set-StrictMode -Version Latest
$script:addonRoot = $PSScriptRoot

function Get-DomainWatchList {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    @((Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object {
        (([string]$_).Trim() -replace '^\*\.', '').TrimEnd('.').ToLowerInvariant()
    } | Where-Object { $_ } | Sort-Object -Unique)
}

function Save-DomainWatchList {
    param([Parameter(Mandatory)][string]$Path, [string[]]$Domain)

    $json = ConvertTo-Json -InputObject @($Domain | Sort-Object -Unique)
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Test-DomainWatchMatch {
    param([string]$Domain, [string[]]$Watchlist)

    $candidate = $Domain.Trim().TrimEnd('.').ToLowerInvariant()
    if (-not $candidate -or $candidate -eq '-') { return $false }
    foreach ($watched in $Watchlist) {
        if ($candidate -eq $watched -or $candidate.EndsWith('.' + $watched, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-DomainWatchSnapshot {
    param([Parameter(Mandatory)][object[]]$Connection)

    if ($Connection.Count -eq 0) { return @() }
    $sessions = @($Connection | ForEach-Object { $_.Session })
    @(Invoke-Command -Session $sessions -ThrottleLimit ([Math]::Min(32, $sessions.Count)) -ErrorAction SilentlyContinue -ScriptBlock {
        $dnsByAddress = @{}
        if (Get-Command Get-DnsClientCache -ErrorAction SilentlyContinue) {
            foreach ($record in @(Get-DnsClientCache -ErrorAction SilentlyContinue)) {
                $address = [string]$record.Data
                $parsedAddress = $null
                if (-not [Net.IPAddress]::TryParse($address, [ref]$parsedAddress)) { continue }
                $domain = [string]$record.Entry
                if ([string]::IsNullOrWhiteSpace($domain)) { $domain = [string]$record.RecordName }
                if ([string]::IsNullOrWhiteSpace($domain)) { continue }
                if (-not $dnsByAddress.ContainsKey($address)) { $dnsByAddress[$address] = [Collections.Generic.List[string]]::new() }
                if (-not $dnsByAddress[$address].Contains($domain)) { $dnsByAddress[$address].Add($domain) }
            }
        }

        $processNames = @{}
        foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) { $processNames[[int]$process.Id] = [string]$process.ProcessName }
        foreach ($connectionItem in @(Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object {
            $_.RemoteAddress -notin @('0.0.0.0', '::', '::0') -and $_.RemotePort -gt 0
        })) {
            $remoteAddress = [string]$connectionItem.RemoteAddress
            $domains = if ($dnsByAddress.ContainsKey($remoteAddress)) { @($dnsByAddress[$remoteAddress]) } else { @('-') }
            foreach ($domain in $domains) {
                [pscustomobject][ordered]@{
                    ComputerName = $env:COMPUTERNAME
                    LocalAddress = [string]$connectionItem.LocalAddress
                    Domain = [string]$domain
                    RemoteAddress = $remoteAddress
                    RemotePort = [int]$connectionItem.RemotePort
                    ProcessName = $(if ($processNames.ContainsKey([int]$connectionItem.OwningProcess)) { $processNames[[int]$connectionItem.OwningProcess] } else { [string]$connectionItem.OwningProcess })
                    State = [string]$connectionItem.State
                    ObservedAt = [DateTime]::UtcNow.ToString('o')
                }
            }
        }
    })
}

function Write-DomainWatchFrame {
    param(
        [object[]]$Row,
        [int]$HostCount,
        [string[]]$Watchlist,
        [bool]$WatchOnly,
        [string]$TabText = ' WinRM Fleet Console | Fleet | [Domain Watch]',
        [int]$Offset = 0,
        [string]$Activity = 'Monitoring'
    )

    $width = Get-ConsoleTuiWidth
    $height = Get-ConsoleTuiHeight
    $pageSize = [Math]::Max(1, $height - 7)
    $compact = $width -lt 110
    if ($compact) {
        $hostAddressWidth = 13; $computerWidth = 14; $domainWidth = 16; $remoteWidth = 18; $timeWidth = 9
        $stateWidth = [Math]::Max(8, $width - $hostAddressWidth - $computerWidth - $domainWidth - $remoteWidth - $timeWidth - 5)
    }
    else {
        $hostAddressWidth = 15
        $computerWidth = [Math]::Max(14, [Math]::Min(20, [int]($width * 0.15)))
        $domainWidth = [Math]::Max(18, [Math]::Min(30, [int]($width * 0.22)))
        $remoteWidth = 21
        $processWidth = [Math]::Max(10, [Math]::Min(18, [int]($width * 0.12)))
        $timeWidth = 9
        $stateWidth = [Math]::Max(10, $width - $hostAddressWidth - $computerWidth - $domainWidth - $remoteWidth - $processWidth - $timeWidth - 6)
    }

    Start-ConsoleTuiFrame
    Write-ConsoleTuiLine (Format-ConsoleTuiText ' WinRM Fleet Console ' $width) Black DarkCyan
    Write-ConsoleTuiLine (Format-ConsoleTuiText $TabText $width) Black Cyan
    Write-ConsoleTuiLine (Format-ConsoleTuiText (" Hosts: {0}  Connections: {1}  Watchlist: {2}  View: {3}  {4}" -f $HostCount, $Row.Count, $Watchlist.Count, $(if ($WatchOnly) { 'watched' } else { 'all' }), $Activity) $width) Gray
    if ($compact) {
        Write-ConsoleTuiLine (Format-ConsoleTuiColumns @('HOST IP', 'COMPUTER', 'DOMAIN', 'REMOTE', 'TIME', 'STATUS') @($hostAddressWidth, $computerWidth, $domainWidth, $remoteWidth, $timeWidth, $stateWidth)) Black DarkCyan
    }
    else {
        Write-ConsoleTuiLine (Format-ConsoleTuiColumns @('HOST IP', 'COMPUTER', 'DOMAIN', 'REMOTE ADDRESS', 'PROCESS', 'TIME', 'STATUS') @($hostAddressWidth, $computerWidth, $domainWidth, $remoteWidth, $processWidth, $timeWidth, $stateWidth)) Black DarkCyan
    }
    for ($index = 0; $index -lt $pageSize; $index++) {
        $sourceIndex = $Offset + $index
        if ($sourceIndex -ge $Row.Count) { Write-ConsoleTuiLine; continue }
        $item = $Row[$sourceIndex]
        $remoteEndpoint = '{0}:{1}' -f $item.RemoteAddress, $item.RemotePort
        $line = if ($compact) {
            Format-ConsoleTuiColumns @($item.LocalAddress, $item.ComputerName, $item.Domain, $remoteEndpoint, $item.Time, $item.Status) @($hostAddressWidth, $computerWidth, $domainWidth, $remoteWidth, $timeWidth, $stateWidth)
        }
        else {
            Format-ConsoleTuiColumns @($item.LocalAddress, $item.ComputerName, $item.Domain, $remoteEndpoint, $item.ProcessName, $item.Time, $item.Status) @($hostAddressWidth, $computerWidth, $domainWidth, $remoteWidth, $processWidth, $timeWidth, $stateWidth)
        }
        if ($item.Watched) { Write-ConsoleTuiLine $line Black Yellow } else { Write-ConsoleTuiLine $line Gray Black }
    }
    Write-ConsoleTuiLine (Format-ConsoleTuiText ' Tab switch  Up/Down/PgUp/PgDn scroll  Space watched/all  W list  R refresh  Esc return ' $width) Black DarkGray
    Complete-ConsoleTuiFrame
}

function Invoke-DomainWatchAddon {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)

    # Reuse the host's tools module. Forcing a reload from module scope can
    # remove the root application's exported commands in Windows PowerShell.
    Import-Module $Context.ToolsModulePath -ErrorAction Stop
    $dataRoot = Join-Path $Context.StorePath 'addon-data\domain-watch'
    $null = [IO.Directory]::CreateDirectory($dataRoot)
    $watchlistPath = Join-Path $dataRoot 'watchlist.json'
    if (-not (Test-Path -LiteralPath $watchlistPath -PathType Leaf)) {
        [IO.File]::Copy((Join-Path $script:addonRoot 'watchlist.json'), $watchlistPath)
    }
    $watchlist = @(Get-DomainWatchList -Path $watchlistPath)

    $state = $Context.State
    if (-not $state.ContainsKey('Connections')) { $state.Connections = [Collections.Generic.List[object]]::new() }
    if (-not $state.ContainsKey('FirstSeen')) { $state.FirstSeen = @{} }
    if (-not $state.ContainsKey('Rows')) { $state.Rows = @() }
    if (-not $state.ContainsKey('WatchOnly')) { $state.WatchOnly = $false }
    if (-not $state.ContainsKey('ViewOffset')) { $state.ViewOffset = 0 }
    if (-not $state.ContainsKey('Dispose')) {
        $state.Dispose = {
            param($State)
            foreach ($connection in @($State.Connections)) {
                Remove-PSSession -Session $connection.Session -ErrorAction SilentlyContinue
            }
            $State.Connections.Clear()
        }
    }

    $connections = $state.Connections
    foreach ($connection in @($connections)) {
        if ([string]$connection.Session.State -ne 'Opened') {
            Remove-PSSession -Session $connection.Session -ErrorAction SilentlyContinue
            $null = $connections.Remove($connection)
        }
    }
    $targets = if ($connections.Count -eq 0) { @(& $Context.GetTargets) } else { @() }
    if ($connections.Count -eq 0 -and $targets.Count -eq 0) {
        $null = & $Context.ShowMessage -Title 'Domain Watch' -Lines @('Select one or more hosts with a usable WinRM endpoint.') -Color Yellow
        return
    }

    $firstSeen = $state.FirstSeen
    $rows = @($state.Rows)
    $watchOnly = [bool]$state.WatchOnly
    $viewOffset = [int]$state.ViewOffset
    $navigation = 'Home'
    $credentialEntryCancelled = $false
    $connectionErrors = [Collections.Generic.List[string]]::new()
    try {
        for ($index = 0; $index -lt $targets.Count; $index++) {
            Write-DomainWatchFrame -Row @() -HostCount $connections.Count -Watchlist $watchlist -WatchOnly $false -TabText $Context.TabText -Activity ("Connecting {0}/{1}: {2}" -f ($index + 1), $targets.Count, $targets[$index].ComputerName)
            $credential = & $Context.RequestCredential -Targets @($targets[$index])
            if ($null -eq $credential) { $credentialEntryCancelled = $true; break }
            try {
                $session = New-WinRMTargetSession -Target $targets[$index] -Credential $credential -OpenTimeoutMs 5000
                $connections.Add([pscustomobject]@{ Target = $targets[$index]; Session = $session })
            }
            catch {
                $connectionErrors.Add(('{0}: {1}' -f $targets[$index].Address, $_.Exception.Message))
                $null = & $Context.WriteAudit -Event 'DomainWatchConnectionFailed' -Data @{ Address = $targets[$index].Address; Detail = $_.ToString() }
            }
            $credential = $null
            $null = & $Context.ClearInput
        }
        if ($connections.Count -eq 0) {
            if ($credentialEntryCancelled) { return }
            $lines = @('None of the selected computers accepted the connection.') + @($connectionErrors) + @('Full errors were written to the audit log.')
            $null = & $Context.ShowMessage -Title 'Domain Watch' -Lines $lines -Color Red
            return
        }

        $nextPoll = [DateTime]::MinValue
        $running = $true
        while ($running) {
            if ([DateTime]::UtcNow -ge $nextPoll) {
                Write-DomainWatchFrame -Row $rows -HostCount $connections.Count -Watchlist $watchlist -WatchOnly $watchOnly -TabText $Context.TabText -Offset $viewOffset -Activity 'Polling...'
                $snapshot = @(Get-DomainWatchSnapshot -Connection @($connections))
                $now = [DateTime]::UtcNow
                $newRows = foreach ($item in $snapshot) {
                    $key = '{0}|{1}|{2}|{3}|{4}' -f $item.ComputerName, $item.Domain, $item.RemoteAddress, $item.RemotePort, $item.ProcessName
                    if (-not $firstSeen.ContainsKey($key)) { $firstSeen[$key] = $now }
                    $watched = Test-DomainWatchMatch -Domain ([string]$item.Domain) -Watchlist $watchlist
                    [pscustomobject][ordered]@{
                        LocalAddress = $item.LocalAddress
                        ComputerName = $item.ComputerName
                        Domain = $item.Domain
                        RemoteAddress = $item.RemoteAddress
                        RemotePort = $item.RemotePort
                        ProcessName = $item.ProcessName
                        Time = ([DateTime]$firstSeen[$key]).ToLocalTime().ToString('HH:mm:ss')
                        Status = $(if ($watched) { "WATCHLIST / $($item.State)" } elseif ($item.Domain -eq '-') { 'IP only' } else { $item.State })
                        Watched = $watched
                    }
                }
                $rows = @($newRows | Where-Object { -not $watchOnly -or $_.Watched } | Sort-Object @{ Expression = 'Watched'; Descending = $true }, ComputerName, Domain, RemoteAddress)
                $pageSize = [Math]::Max(1, (Get-ConsoleTuiHeight) - 7)
                $viewOffset = [Math]::Min($viewOffset, [Math]::Max(0, $rows.Count - $pageSize))
                $nextPoll = [DateTime]::UtcNow.AddSeconds(3)
                $null = & $Context.ClearInput
            }

            Write-DomainWatchFrame -Row $rows -HostCount $connections.Count -Watchlist $watchlist -WatchOnly $watchOnly -TabText $Context.TabText -Offset $viewOffset
            $keyInfo = Get-ConsoleTuiKey
            if ($null -eq $keyInfo) { Start-Sleep -Milliseconds 25; continue }
            $pageSize = [Math]::Max(1, (Get-ConsoleTuiHeight) - 7)
            $maxOffset = [Math]::Max(0, $rows.Count - $pageSize)
            switch ($keyInfo.Key) {
                'UpArrow' { $viewOffset = [Math]::Max(0, $viewOffset - 1) }
                'DownArrow' { $viewOffset = [Math]::Min($maxOffset, $viewOffset + 1) }
                'PageUp' { $viewOffset = [Math]::Max(0, $viewOffset - $pageSize) }
                'PageDown' { $viewOffset = [Math]::Min($maxOffset, $viewOffset + $pageSize) }
                'Home' { $viewOffset = 0 }
                'End' { $viewOffset = $maxOffset }
                'Tab' {
                    $navigation = if (($keyInfo.Modifiers -band [ConsoleModifiers]::Shift) -ne 0) { 'PreviousTab' } else { 'NextTab' }
                    $running = $false
                }
                'Spacebar' { $watchOnly = -not $watchOnly; $viewOffset = 0; $nextPoll = [DateTime]::MinValue }
                'W' {
                    $value = & $Context.ReadPrompt -Prompt 'Watchlist domains, comma-separated' -Default ($watchlist -join ', ')
                    if (-not [string]::IsNullOrWhiteSpace($value)) {
                        $watchlist = @($value.Split(',') | ForEach-Object { ($_.Trim() -replace '^\*\.', '').TrimEnd('.').ToLowerInvariant() } | Where-Object { $_ } | Sort-Object -Unique)
                        Save-DomainWatchList -Path $watchlistPath -Domain $watchlist
                        $nextPoll = [DateTime]::MinValue
                    }
                }
                'R' { $nextPoll = [DateTime]::MinValue }
                'Escape' { $running = $false }
                'Q' { $running = $false }
            }
        }
    }
    finally {
        $state.Rows = @($rows)
        $state.WatchOnly = $watchOnly
        $state.ViewOffset = $viewOffset
        $null = & $Context.ClearInput
    }
    [pscustomobject]@{ Navigation = $navigation }
}

Export-ModuleMember -Function Invoke-DomainWatchAddon
