#Requires -Version 5.1
<#
.SYNOPSIS
    Full-screen WinRM fleet manager for discovery, inventory and remote work.
.DESCRIPTION
    Keeps hosts, groups, tags, network profiles and audit history in a local
    store. Credentials exist only in memory. Run without parameters to use
    %LOCALAPPDATA%\WinRMTui, or pass -StorePath for a portable/test store.
#>
[CmdletBinding()]
param([string]$StorePath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tuiPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'modules\ConsoleTu1\ConsoleTui.psd1'
$managerPath = Join-Path $PSScriptRoot 'WinRM.Manager.psd1'
$toolsPath = Join-Path $PSScriptRoot 'WinRM.Tools.psm1'
$addonsPath = Join-Path $PSScriptRoot 'WinRM.Addons.psm1'
$bundledAddonsPath = Join-Path $PSScriptRoot 'addons'
$scannerPath = Join-Path $PSScriptRoot 'Find-WinRM.ps1'
Import-Module $tuiPath -Force -ErrorAction Stop
Import-Module $managerPath -Force -ErrorAction Stop
Import-Module $toolsPath -Force -ErrorAction Stop
Import-Module $addonsPath -Force -ErrorAction Stop

$inputRedirected = $false
$outputRedirected = $false
try { $inputRedirected = [Console]::IsInputRedirected; $outputRedirected = [Console]::IsOutputRedirected } catch {}
if ($inputRedirected -or $outputRedirected) { throw 'WinRM Fleet Console requires an interactive terminal. Use WinRM.Manager.psd1 and WinRM.Tools.psm1 for automation.' }

if ([string]::IsNullOrWhiteSpace($StorePath)) { $StorePath = Get-WinRMDefaultStorePath }
$store = Initialize-WinRMStore -StorePath $StorePath
$config = Get-WinRMManagerConfig -StorePath $StorePath
$inventory = @(Get-WinRMInventory -StorePath $StorePath)
$credential = $null
$filter = ''
$selected = @{}
$cursor = 0
$offset = 0
$lastMessage = 'Ready'
$hostVersion = [version]'1.0.0'
$availableAddons = @(Get-WinRMAddon -Root @($bundledAddonsPath, $store.Addons) -HostVersion $hostVersion)
$addonStates = @{}

function Find-TuiVerifiedConnectionHost {
    param($HostRecord)

    $address = [string]$HostRecord.Address
    $parsedAddress = $null
    if (-not [Net.IPAddress]::TryParse($address, [ref]$parsedAddress)) { return $null }

    $candidates = @([string]$HostRecord.ComputerName) + @($script:inventory | ForEach-Object {
        [string]$_.ComputerName
        [string]$_.Address
    })
    foreach ($candidate in @($candidates | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne $address
    } | Select-Object -Unique)) {
        $parsedCandidate = $null
        if ([Net.IPAddress]::TryParse($candidate, [ref]$parsedCandidate)) { continue }
        try {
            $lookup = [Net.Dns]::GetHostAddressesAsync($candidate)
            $timeout = [Math]::Min(1000, [int]$script:config.Settings.OpenTimeoutMs)
            if ($lookup.Wait($timeout) -and
                $address -in @($lookup.Result | ForEach-Object { $_.IPAddressToString })) {
                return $candidate
            }
        }
        catch { Write-Verbose "Forward lookup for ${candidate}: $($_.Exception.Message)" }
    }
    return $null
}

function Get-TuiPreferredTarget {
    param($HostRecord)
    $endpoint = Select-WinRMPreferredEndpoint $HostRecord
    if ($null -eq $endpoint) { return $null }
    $verifiedConnectionHost = Find-TuiVerifiedConnectionHost $HostRecord
    [pscustomobject][ordered]@{
        Address = $HostRecord.Address
        ComputerName = $(if ($verifiedConnectionHost) { $verifiedConnectionHost } else { $HostRecord.ComputerName })
        VerifiedConnectionHost = $verifiedConnectionHost
        Port = $endpoint.Port
        Transport = $endpoint.Transport
        DiscoveryStatus = $endpoint.DiscoveryStatus
        ConnectionStatus = $HostRecord.ConnectionStatus
    }
}

function Get-TuiVisibleHosts {
    @(Find-WinRMInventory -HostRecord $script:inventory -Filter $script:filter -Blacklist @($script:config.Blacklist))
}

function Get-TuiActionHosts {
    param([object[]]$Visible, [switch]$AllVisible)
    $hosts = if ($AllVisible) { @($Visible) }
        elseif ($script:selected.Count -gt 0) { @($script:inventory | Where-Object { $script:selected.ContainsKey([string]$_.Id) }) }
        elseif ($Visible.Count -gt 0) { @($Visible[$script:cursor]) }
        else { @() }
    @($hosts | ForEach-Object { Get-TuiPreferredTarget $_ } | Where-Object { $null -ne $_ })
}

function Read-TuiPrompt {
    param([string]$Prompt, [string]$Default = '')
    Read-ConsoleTuiPrompt -Prompt $Prompt -Default $Default
}

function Show-TuiNotice {
    param([string]$Title, [string[]]$Lines, [ConsoleColor]$Color = [ConsoleColor]::White)
    Show-ConsoleTuiMessage -Title $Title -Lines $Lines -Color $Color
}

function Clear-TuiBufferedInput {
    param([ValidateRange(0, 1000)][int]$QuietPeriodMs = 100)

    $quiet = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($quiet.ElapsedMilliseconds -lt $QuietPeriodMs) {
            $key = Get-ConsoleTuiKey
            if ($null -ne $key) {
                $quiet.Restart()
                continue
            }
            Start-Sleep -Milliseconds 10
        }
    }
    finally { $quiet.Stop() }
}

function Get-TuiTabText {
    param([object[]]$Addons, [int]$ActiveTabIndex = 0)

    $labels = @('Fleet') + @($Addons | ForEach-Object { $_.Name })
    $rendered = for ($index = 0; $index -lt $labels.Count; $index++) {
        if ($index -eq $ActiveTabIndex) { "[ $(([string]$labels[$index]).ToUpperInvariant()) ]" } else { "  $($labels[$index])  " }
    }
    ' ' + ($rendered -join '  |  ')
}

function New-TuiAddonContext {
    param($Addon, [object[]]$Addons, [int]$ActiveTabIndex)

    if (-not $script:addonStates.ContainsKey([string]$Addon.Id)) { $script:addonStates[[string]$Addon.Id] = @{} }

    [pscustomobject][ordered]@{
        HostName = 'WinRM Fleet Console'
        HostVersion = $script:hostVersion.ToString()
        RootPath = $PSScriptRoot
        StorePath = $script:StorePath
        Store = $script:store
        TuiModulePath = $script:tuiPath
        ManagerModulePath = $script:managerPath
        ToolsModulePath = $script:toolsPath
        ApplicationSessionState = $ExecutionContext.SessionState
        ConsoleHost = $Host
        Tabs = @('Fleet') + @($Addons | ForEach-Object { $_.Name })
        ActiveTabIndex = $ActiveTabIndex
        TabText = Get-TuiTabText -Addons $Addons -ActiveTabIndex $ActiveTabIndex
        State = $script:addonStates[[string]$Addon.Id]
        GetConfig = { $script:config }
        SetConfig = { param($Value) $script:config = $Value }
        GetInventory = { @($script:inventory) }
        SetInventory = { param([object[]]$Value) $script:inventory = @($Value) }
        GetVisibleHosts = { @(Get-TuiVisibleHosts) }
        GetTargets = { $visible = @(Get-TuiVisibleHosts); @(Get-TuiActionHosts -Visible $visible) }
        RequestCredential = {
            param([object[]]$Targets)
            if ($null -eq (Get-Command Resolve-WinRMComputerName -ErrorAction SilentlyContinue)) {
                Import-Module $script:toolsPath -Global -ErrorAction Stop
            }
            if (-not (Request-TuiCredential -Targets $Targets)) { return $null }
            $value = $script:credential
            $script:credential = $null
            $value
        }
        SaveState = { Save-TuiState }
        ReloadState = {
            $script:config = Get-WinRMManagerConfig -StorePath $script:StorePath
            $script:inventory = @(Get-WinRMInventory -StorePath $script:StorePath)
        }
        ReadPrompt = { param([string]$Prompt, [string]$Default = '') Read-TuiPrompt -Prompt $Prompt -Default $Default }
        Confirm = { param([string]$Message) Confirm-ConsoleTui -Message $Message }
        ShowMessage = { param([string]$Title, [string[]]$Lines, [ConsoleColor]$Color = [ConsoleColor]::White) Show-TuiNotice -Title $Title -Lines $Lines -Color $Color }
        WriteAudit = { param([string]$Event, $Data) Write-WinRMAuditEvent -StorePath $script:StorePath -Event $Event -Data $Data }
        ClearInput = { Clear-TuiBufferedInput }
    }
}

function Find-TuiRememberedComputerName {
    param([Parameter(Mandatory)][string]$Address)

    $events = @(Get-WinRMAuditEvent -StorePath $script:StorePath -Last 500)
    [array]::Reverse($events)
    foreach ($eventItem in $events) {
        if ($null -eq $eventItem.Data) { continue }
        $candidateAddress = ''
        $candidateName = ''
        if (@($eventItem.Data.PSObject.Properties.Match('Address')).Count -gt 0) { $candidateAddress = [string]$eventItem.Data.Address }
        if (@($eventItem.Data.PSObject.Properties.Match('ComputerName')).Count -gt 0) { $candidateName = [string]$eventItem.Data.ComputerName }
        if (@($eventItem.Data.PSObject.Properties.Match('Target')).Count -gt 0 -and $null -ne $eventItem.Data.Target -and
            $eventItem.Data.Target -isnot [string]) {
            if (@($eventItem.Data.Target.PSObject.Properties.Match('Address')).Count -gt 0) { $candidateAddress = [string]$eventItem.Data.Target.Address }
            if (@($eventItem.Data.Target.PSObject.Properties.Match('ComputerName')).Count -gt 0) { $candidateName = [string]$eventItem.Data.Target.ComputerName }
        }
        $parsedCandidate = $null
        if ($candidateAddress -eq $Address -and -not [string]::IsNullOrWhiteSpace($candidateName) -and
            -not [Net.IPAddress]::TryParse($candidateName, [ref]$parsedCandidate)) { return $candidateName }
    }
    return $null
}

function Request-TuiCredential {
    param([Parameter(Mandatory)][object[]]$Targets)

    $script:credential = $null
    $computerName = $null
    if ($Targets.Count -eq 1) {
        $computerName = [string]$Targets[0].ComputerName
        $parsedName = $null
        if ([string]::IsNullOrWhiteSpace($computerName) -or
            [Net.IPAddress]::TryParse($computerName, [ref]$parsedName)) {
            $resolved = Resolve-WinRMComputerName -Address ([string]$Targets[0].Address) -TimeoutMs ([Math]::Min(1500, [int]$script:config.Settings.OpenTimeoutMs))
            $computerName = [string]$resolved.ComputerName
            if ($computerName -ne [string]$Targets[0].Address) {
                $Targets[0].ComputerName = $computerName
                $inventoryHost = @($script:inventory | Where-Object { $_.Address -eq $Targets[0].Address } | Select-Object -First 1)
                if ($inventoryHost.Count -gt 0) { $inventoryHost[0].ComputerName = $computerName; Save-TuiState }
            }
            if ($resolved.ConnectionHost -ne [string]$Targets[0].Address) { $Targets[0].VerifiedConnectionHost = $resolved.ConnectionHost }
        }
    }
    $parsedComputerName = $null
    if ($Targets.Count -eq 1 -and
        ([string]::IsNullOrWhiteSpace($computerName) -or
        [Net.IPAddress]::TryParse($computerName, [ref]$parsedComputerName))) {
        $rememberedName = Find-TuiRememberedComputerName -Address ([string]$Targets[0].Address)
        if (-not [string]::IsNullOrWhiteSpace($rememberedName)) {
            $computerName = $rememberedName
            $Targets[0].ComputerName = $computerName
            $Targets[0].VerifiedConnectionHost = $computerName
            $inventoryHost = @($script:inventory | Where-Object { $_.Address -eq $Targets[0].Address } | Select-Object -First 1)
            if ($inventoryHost.Count -gt 0) { $inventoryHost[0].ComputerName = $computerName; Save-TuiState }
        }
    }
    $parsedComputerName = $null
    if ($Targets.Count -eq 1 -and
        ([string]::IsNullOrWhiteSpace($computerName) -or
        [Net.IPAddress]::TryParse($computerName, [ref]$parsedComputerName))) {
        Show-TuiNotice 'Computer name required' @(
            "The computer name for $($Targets[0].Address) could not be resolved automatically.",
            'Enter it once; it will be saved in inventory and used to build COMPUTER\login.'
        ) Yellow
        $enteredComputerName = Read-TuiPrompt "Computer name for $($Targets[0].Address)"
        $parsedEnteredName = $null
        if ([string]::IsNullOrWhiteSpace($enteredComputerName) -or
            [Net.IPAddress]::TryParse($enteredComputerName.Trim(), [ref]$parsedEnteredName)) {
            $script:lastMessage = "A computer name is required for $($Targets[0].Address)."
            return $false
        }
        $computerName = $enteredComputerName.Trim()
        $Targets[0].ComputerName = $computerName
        $Targets[0].VerifiedConnectionHost = $computerName
        $inventoryHost = @($script:inventory | Where-Object { $_.Address -eq $Targets[0].Address } | Select-Object -First 1)
        if ($inventoryHost.Count -gt 0) {
            $inventoryHost[0].ComputerName = $computerName
            Save-TuiState
        }
        $null = Write-WinRMAuditEvent -StorePath $script:StorePath -Event 'ComputerNameProvided' -Data @{ Address = $Targets[0].Address; ComputerName = $computerName }
    }
    $computerQualifier = if ($Targets.Count -eq 1) { $computerName.Split('.')[0] } else { $null }

    $prompt = if ($Targets.Count -eq 1) { "Login for $computerQualifier" } else { "Login for $($Targets.Count) hosts (DOMAIN\login)" }
    $login = Read-TuiPrompt $prompt
    if ([string]::IsNullOrWhiteSpace($login)) {
        $script:lastMessage = 'Credential entry was cancelled.'
        return $false
    }
    $login = $login.Trim()

    $qualifiedUser = $login
    if ($login -notmatch '[\\@]') {
        $parsedName = $null
        if ($Targets.Count -ne 1) {
            $script:lastMessage = 'Use DOMAIN\login for an operation on multiple computers.'
            return $false
        }
        if ([string]::IsNullOrWhiteSpace($computerQualifier) -or
            [Net.IPAddress]::TryParse($computerQualifier, [ref]$parsedName)) {
            $script:lastMessage = "Could not compute a computer name for $($Targets[0].Address). Run discovery again or enter COMPUTER\login."
            return $false
        }
        $qualifiedUser = "$computerQualifier\$login"
    }

    Clear-ConsoleTuiSurface
    $newCredential = Get-Credential -UserName $qualifiedUser -Message "Password for $qualifiedUser (not saved)"
    Clear-ConsoleTuiSurface
    Clear-TuiBufferedInput
    if ($null -eq $newCredential) {
        $script:lastMessage = "Password was not entered for $qualifiedUser."
        return $false
    }

    $script:credential = $newCredential
    $null = Write-WinRMAuditEvent -StorePath $script:StorePath -Event 'CredentialEntered' -Data @{ User = $script:credential.UserName; Targets = @($Targets | ForEach-Object { [string]$_.Address }) }
    $script:lastMessage = "Connecting as $($script:credential.UserName)."
    return $true
}

function Show-TuiBusyStatus {
    param([string]$Title, [string]$Detail, [string]$InputHint = 'Input is ignored while this request is running.')

    $width = Get-ConsoleTuiWidth
    Start-ConsoleTuiFrame
    Write-ConsoleTuiLine (Format-ConsoleTuiText ' WinRM Fleet Console - operation ' $width) Black Cyan
    Write-ConsoleTuiLine
    Write-ConsoleTuiLine (Format-ConsoleTuiText "  Status: running - $Title" $width) Cyan
    Write-ConsoleTuiLine (Format-ConsoleTuiText "  $Detail" $width) Gray
    Write-ConsoleTuiLine
    Write-ConsoleTuiLine (Format-ConsoleTuiText "  $InputHint" $width) Yellow
    Complete-ConsoleTuiFrame
}

function Invoke-TuiRunspace {
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Detail,
        [Parameter(Mandatory)][scriptblock]$Operation,
        [object[]]$Arguments = @()
    )
    Clear-ConsoleTuiInputBacklog
    $ps = [powershell]::Create()
    $output = @()
    $null = $ps.AddScript($Operation.ToString())
    foreach ($argument in $Arguments) { $null = $ps.AddArgument($argument) }
    $handle = $ps.BeginInvoke()
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $frame = 0
    $cancelled = $false
    $errors = @()
    try {
        while (-not $handle.IsCompleted) {
            $spinner = @('|', '/', '-', '\')[$frame % 4]
            $width = Get-ConsoleTuiWidth
            Start-ConsoleTuiFrame
            Write-ConsoleTuiLine (Format-ConsoleTuiText ' WinRM Fleet Console - operation ' $width) Black Cyan
            Write-ConsoleTuiLine
            Write-ConsoleTuiLine (Format-ConsoleTuiText ("  $spinner Status: running - $Title") $width) Cyan
            Write-ConsoleTuiLine (Format-ConsoleTuiText ("  $Detail") $width) Gray
            Write-ConsoleTuiLine (Format-ConsoleTuiText ("  Elapsed: {0:hh\:mm\:ss}" -f $watch.Elapsed) $width) DarkGray
            Write-ConsoleTuiLine
            Write-ConsoleTuiLine '  Esc = cancel; other input is ignored while the request is running' Yellow
            Complete-ConsoleTuiFrame
            $frame++
            $key = Get-ConsoleTuiKey
            if ($null -ne $key -and $key.Key -eq [ConsoleKey]::Escape) {
                $cancelled = $true
                $ps.Stop()
                break
            }
            Start-Sleep -Milliseconds 80
        }
        if (-not $cancelled) {
            try { $output = @($ps.EndInvoke($handle)) }
            catch { $errors += $_ }
        }
        $errors += @($ps.Streams.Error)
        [pscustomobject]@{ Cancelled = $cancelled; Output = @($output); Errors = @($errors) }
    }
    finally {
        $watch.Stop()
        $ps.Dispose()
        Clear-TuiBufferedInput
        Clear-ConsoleTuiSurface
    }
}

function Save-TuiState {
    $script:inventory = @(Save-WinRMInventory -HostRecord $script:inventory -StorePath $script:StorePath)
    $null = Save-WinRMManagerConfig -Config $script:config -StorePath $script:StorePath
}

function Select-TuiDiscoveryProfile {
    param([object[]]$Profiles)

    $choices = @($Profiles | ForEach-Object {
        [pscustomobject]@{
            Name = [string]$_.Name
            Pattern = ConvertTo-WinRMDiscoveryPattern -Range ([string]$_.Range)
            HttpPort = [int]$_.HttpPort
            HttpsPort = [int]$_.HttpsPort
            Custom = $false
        }
    }) + @([pscustomobject]@{
        Name = '[custom]'
        Pattern = 'Enter an IPv4/CIDR/wildcard pattern'
        HttpPort = 5985
        HttpsPort = 5986
        Custom = $true
    })
    $cursor = 0
    $offset = 0

    while ($true) {
        $width = Get-ConsoleTuiWidth
        $height = Get-ConsoleTuiHeight
        $pageSize = [Math]::Max(1, $height - 6)
        if ($cursor -lt $offset) { $offset = $cursor }
        if ($cursor -ge $offset + $pageSize) { $offset = $cursor - $pageSize + 1 }
        $offset = [Math]::Max(0, [Math]::Min($offset, [Math]::Max(0, $choices.Count - $pageSize)))

        Start-ConsoleTuiFrame
        Write-ConsoleTuiLine (Format-ConsoleTuiText ' WinRM Fleet Console - discovery ' $width) Black Cyan
        Write-ConsoleTuiLine (Format-ConsoleTuiText ' Select a network pattern to scan:' $width) Gray
        Write-ConsoleTuiLine
        for ($row = 0; $row -lt $pageSize; $row++) {
            $index = $offset + $row
            if ($index -ge $choices.Count) { Write-ConsoleTuiLine; continue }
            $choice = $choices[$index]
            $number = if ($index -lt 9) { '{0}.' -f ($index + 1) } else { '  ' }
            $line = Format-ConsoleTuiText ("  {0,-3} {1}  [{2}]" -f $number, $choice.Name, $choice.Pattern) $width
            if ($index -eq $cursor) { Write-ConsoleTuiLine $line Black Cyan }
            else { Write-ConsoleTuiLine $line Gray Black }
        }
        Write-ConsoleTuiLine (Format-ConsoleTuiText ' Up/Down + Enter, 1-9 = select immediately, Esc = cancel ' $width) Black DarkGray
        Complete-ConsoleTuiFrame

        $key = Get-ConsoleTuiKey
        if ($null -eq $key) { Start-Sleep -Milliseconds 15; continue }
        switch ($key.Key) {
            'UpArrow' { if ($cursor -gt 0) { $cursor-- } }
            'DownArrow' { if ($cursor -lt $choices.Count - 1) { $cursor++ } }
            'PageUp' { $cursor = [Math]::Max(0, $cursor - $pageSize) }
            'PageDown' { $cursor = [Math]::Min($choices.Count - 1, $cursor + $pageSize) }
            'Home' { $cursor = 0 }
            'End' { $cursor = $choices.Count - 1 }
            'Enter' { Clear-ConsoleTuiSurface; return $choices[$cursor] }
            'Escape' { Clear-ConsoleTuiSurface; return $null }
            default {
                if ([char]::IsDigit($key.KeyChar)) {
                    $selectedIndex = [int][string]$key.KeyChar - 1
                    if ($selectedIndex -ge 0 -and $selectedIndex -lt $choices.Count) {
                        Clear-ConsoleTuiSurface
                        return $choices[$selectedIndex]
                    }
                }
            }
        }
    }
}

function Invoke-TuiDiscovery {
    $profiles = @($script:config.Networks | Where-Object { @($_.PSObject.Properties.Match('Enabled')).Count -eq 0 -or $_.Enabled })
    $choice = Select-TuiDiscoveryProfile -Profiles $profiles
    if ($null -eq $choice) { return }
    $pattern = if ($choice.Custom) {
        Read-TuiPrompt 'Custom IPv4, CIDR or wildcard pattern' '192.168.1.*'
    }
    else { $choice.Pattern }
    if ([string]::IsNullOrWhiteSpace($pattern)) { return }
    $scanProfiles = @([pscustomobject]@{
        Name = $choice.Name
        Range = $pattern.Trim()
        HttpPort = [int]$choice.HttpPort
        HttpsPort = [int]$choice.HttpsPort
    })
    $run = Invoke-TuiRunspace -Title 'Discovering WinRM endpoints' -Detail (($scanProfiles.Range) -join ', ') -Operation {
        param($Scanner, $Profiles, $Timeout, $Throttle)
        foreach ($profile in $Profiles) {
            & $Scanner -IpMask $profile.Range -HttpPort ([int]$profile.HttpPort) -HttpsPort ([int]$profile.HttpsPort) -TimeoutMs $Timeout -ThrottleLimit $Throttle
        }
    } -Arguments @($scannerPath, $scanProfiles, [int]$config.Settings.DiscoveryTimeoutMs, [int]$config.Settings.ThrottleLimit)
    if ($run.Cancelled) {
        $script:lastMessage = 'Discovery cancelled; remote changes do not apply to discovery.'
        $null = Write-WinRMAuditEvent -StorePath $StorePath -Event 'DiscoveryCancelled' -Data @{ Profiles = @($scanProfiles.Range); Partial = $run.Output.Count }
        return
    }
    elseif ($run.Errors.Count -gt 0) { Show-TuiNotice 'Discovery errors' @($run.Errors | ForEach-Object { $_.ToString() }) Red }
    $script:inventory = @(Merge-WinRMDiscoveryResult -Current $script:inventory -Discovery $run.Output -Blacklist @($config.Blacklist))
    Save-TuiState
    $script:lastMessage = "Discovery returned $($run.Output.Count) endpoint(s); inventory has $($script:inventory.Count) host(s)."
    $null = Write-WinRMAuditEvent -StorePath $StorePath -Event 'DiscoveryCompleted' -Data @{ Profiles = @($scanProfiles.Range); Endpoints = $run.Output.Count; Hosts = $script:inventory.Count }
}

function Update-TuiInventoryFromResults {
    param([object[]]$Results)
    foreach ($result in $Results) {
        $hostItem = @($script:inventory | Where-Object { $_.Address -eq $result.Address } | Select-Object -First 1)
        if ($hostItem.Count -eq 0) { continue }
        foreach ($name in @('ComputerName', 'ConnectionStatus', 'Status', 'OS', 'OSVersion', 'LastBootTime', 'UptimeDays', 'FreeSpaceGB', 'LoggedOnUser', 'CheckedAt')) {
            if (@($result.PSObject.Properties.Match($name)).Count -gt 0) {
                if (@($hostItem[0].PSObject.Properties.Match($name)).Count -eq 0) { $hostItem[0] | Add-Member -NotePropertyName $name -NotePropertyValue $result.$name }
                else { $hostItem[0].$name = $result.$name }
            }
        }
        if ($result.Status -in @('Connected', 'Succeeded', 'Scheduled')) { $hostItem[0].LastSeen = [DateTime]::UtcNow.ToString('o') }
        foreach ($endpoint in @($hostItem[0].Endpoints)) {
            if ($endpoint.Port -eq $result.Port -and $endpoint.Transport -eq $result.Transport) { $endpoint.ConnectionStatus = $result.ConnectionStatus }
        }
    }
}

function Invoke-TuiRemoteAction {
    param([string]$Action, [string]$CommandText, [object[]]$Targets, [object[]]$ArgumentList = @(), [int]$DelaySeconds = 60)
    if ($Targets.Count -eq 0) { $script:lastMessage = 'No targets have a usable endpoint.'; return }
    if (-not (Request-TuiCredential -Targets $Targets)) { return }
    try {
        $options = @{
            Action = $Action; Credential = $script:credential; Authentication = 'Default'
            OpenTimeoutMs = [int]$script:config.Settings.OpenTimeoutMs
            CommandTimeoutSec = [int]$script:config.Settings.CommandTimeoutSec
            ArgumentList = $ArgumentList; DelaySeconds = $DelaySeconds
            SkipDns = [bool]$script:config.Settings.SkipDns
        }
        if (-not [string]::IsNullOrWhiteSpace($CommandText)) { $options.CommandText = $CommandText }
        $runId = [guid]::NewGuid().ToString('N')
        $null = Write-WinRMAuditEvent -StorePath $script:StorePath -Event 'RunStarted' -Data @{ RunId = $runId; Action = $Action; Targets = @($Targets | Select-Object Address, ComputerName, VerifiedConnectionHost, Port, Transport); ConnectAs = $script:credential.UserName }
        $run = Invoke-TuiRunspace -Title "$Action on $($Targets.Count) host(s)" -Detail (($Targets.ComputerName) -join ', ') -Operation {
            param($ModulePath, $InputTargets, $InputOptions, $Throttle)
            Import-Module $ModulePath -Force
            Invoke-WinRMBatch -Target $InputTargets -Options $InputOptions -ThrottleLimit $Throttle
        } -Arguments @($toolsPath, $Targets, $options, [int]$config.Settings.ThrottleLimit)
        foreach ($result in $run.Output) { $null = Write-WinRMAuditEvent -StorePath $StorePath -Event 'Result' -Data @{ RunId = $runId; Result = $result } }
        if ($run.Cancelled) { $null = Write-WinRMAuditEvent -StorePath $StorePath -Event 'RunCancelled' -Data @{ RunId = $runId; Received = $run.Output.Count } }
        else { $null = Write-WinRMAuditEvent -StorePath $StorePath -Event 'RunCompleted' -Data @{ RunId = $runId; Received = $run.Output.Count; Errors = $run.Errors.Count } }
        Update-TuiInventoryFromResults $run.Output
        Save-TuiState
        $failed = @($run.Output | Where-Object { $_.Status -notin @('Connected', 'Succeeded', 'Scheduled') }).Count
        $script:lastMessage = "$Action finished: $($run.Output.Count - $failed) succeeded, $failed failed."
        if ($run.Errors.Count -gt 0) { Show-TuiNotice 'Worker errors' @($run.Errors | ForEach-Object { $_.ToString() }) Red }
    }
    finally { $script:credential = $null }
}

function Invoke-TuiScript {
    param([object[]]$Targets)
    $inputValue = Read-TuiPrompt 'PowerShell script path or one-line command'
    if ([string]::IsNullOrWhiteSpace($inputValue)) { return }
    if (Test-Path -LiteralPath $inputValue -PathType Leaf) { $command = Get-Content -LiteralPath $inputValue -Raw }
    else { $command = $inputValue }
    $argumentText = Read-TuiPrompt 'ArgumentList as JSON array (optional)' '[]'
    try { $parsedArguments = $argumentText | ConvertFrom-Json; $arguments = @($parsedArguments) }
    catch { Show-TuiNotice 'Invalid arguments' @('ArgumentList must be a JSON array, for example: ["Spooler", 5]') Red; return }
    if (-not (Confirm-ConsoleTui "Execute script on $($Targets.Count) host(s)?")) { return }
    Invoke-TuiRemoteAction -Action Command -CommandText $command -Targets $Targets -ArgumentList $arguments
}

function Add-TuiManualHost {
    $address = Read-TuiPrompt 'DNS name or IP address'
    if ([string]::IsNullOrWhiteSpace($address)) { return }
    $transport = (Read-TuiPrompt 'Transport HTTP or HTTPS' 'HTTP').ToUpperInvariant()
    if ($transport -notin @('HTTP', 'HTTPS')) { $script:lastMessage = 'Transport must be HTTP or HTTPS.'; return }
    $defaultPort = if ($transport -eq 'HTTPS') { 5986 } else { 5985 }
    $portText = Read-TuiPrompt 'Port' ([string]$defaultPort)
    $port = 0
    if (-not [int]::TryParse($portText, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { $script:lastMessage = 'Port must be between 1 and 65535.'; return }
    $resolved = Resolve-WinRMComputerName -Address $address.Trim() -TimeoutMs ([int]$script:config.Settings.DiscoveryTimeoutMs)
    $record = [pscustomobject][ordered]@{
        Address = $address.Trim(); ComputerName = $resolved.ComputerName; ConnectionHost = $resolved.ConnectionHost; NameSource = $resolved.NameSource
        Port = $port; Transport = $transport
        Endpoint = '{0}://{1}:{2}/wsman' -f $transport.ToLowerInvariant(), $address.Trim(), $port
        DiscoveryStatus = 'ManuallyAdded'; ConnectionStatus = 'NotTested'; Status = 'ManuallyAdded'; Detail = $null
    }
    $script:inventory = @(Merge-WinRMDiscoveryResult -Current $script:inventory -Discovery @($record) -Blacklist @($script:config.Blacklist))
    Save-TuiState
    $script:lastMessage = "Added: $address ($transport/$port)"
}

function Invoke-TuiLibraryScript {
    param([object[]]$Targets)
    $scripts = @((Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'scripts'), $store.Scripts -Filter '*.ps1' -File -ErrorAction SilentlyContinue) | Sort-Object Name, FullName -Unique)
    if ($scripts.Count -eq 0) { $script:lastMessage = 'Script library is empty.'; return }
    $lines = @()
    for ($i = 0; $i -lt $scripts.Count; $i++) { $lines += "  $($i + 1). $($scripts[$i].Name)" }
    Show-TuiNotice 'Script library' $lines
    $answer = Read-TuiPrompt 'Script number'
    if ($answer -notmatch '^\d+$' -or [int]$answer -lt 1 -or [int]$answer -gt $scripts.Count) { return }
    $scriptFile = $scripts[[int]$answer - 1]
    if (-not (Confirm-ConsoleTui "Run $($scriptFile.Name) on $($Targets.Count) host(s)?")) { return }
    Invoke-TuiRemoteAction -Action Command -CommandText (Get-Content -LiteralPath $scriptFile.FullName -Raw) -Targets $Targets
}

function Invoke-TuiTransfer {
    param([ValidateSet('Upload', 'Download')]$Direction, [object[]]$Targets)
    if ($Targets.Count -eq 0) { $script:lastMessage = 'No targets have a usable endpoint.'; return }
    if ($Direction -eq 'Upload') {
        $source = Read-TuiPrompt 'Local file or directory'
        if (-not (Test-Path -LiteralPath $source)) { $script:lastMessage = "Not found: $source"; return }
        $destination = Read-TuiPrompt 'Remote destination' 'C:\Windows\Temp'
    }
    else {
        $source = Read-TuiPrompt 'Remote path (wildcards allowed)' 'C:\Windows\Temp\*.log'
        $destination = Read-TuiPrompt 'Local root (a folder per host is created)' $store.Downloads
    }
    if (-not (Confirm-ConsoleTui "$Direction on $($Targets.Count) host(s)?")) { return }
    if (-not (Request-TuiCredential -Targets $Targets)) { return }
    try {
        $options = @{ Direction = $Direction; Source = $source; Destination = $destination; Credential = $script:credential; Authentication = 'Default'; OpenTimeoutMs = [int]$config.Settings.OpenTimeoutMs; SkipDns = [bool]$config.Settings.SkipDns; Recurse = $true }
        $runId = [guid]::NewGuid().ToString('N')
        $null = Write-WinRMAuditEvent -StorePath $StorePath -Event 'TransferStarted' -Data @{ RunId = $runId; Direction = $Direction; Targets = @($Targets.Address); Source = $source; Destination = $destination; ConnectAs = $script:credential.UserName }
        $run = Invoke-TuiRunspace -Title "$Direction on $($Targets.Count) host(s)" -Detail $source -Operation {
            param($ModulePath, $InputTargets, $InputOptions, $Throttle)
            Import-Module $ModulePath -Force
            Invoke-WinRMFileTransferBatch -Target $InputTargets -Options $InputOptions -ThrottleLimit $Throttle
        } -Arguments @($toolsPath, $Targets, $options, [Math]::Min(8, [int]$config.Settings.ThrottleLimit))
        foreach ($result in $run.Output) { $null = Write-WinRMAuditEvent -StorePath $StorePath -Event 'TransferResult' -Data @{ RunId = $runId; Result = $result } }
        $failed = @($run.Output | Where-Object Status -ne 'Succeeded').Count
        $script:lastMessage = "$Direction finished: $($run.Output.Count - $failed) succeeded, $failed failed."
    }
    finally { $script:credential = $null }
}

function Invoke-TuiRemoteCommandShell {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$ComputerName
    )

    Write-Host "Remote PowerShell session: $ComputerName" -ForegroundColor Cyan
    Write-Host 'Enter one PowerShell command per line. Type exit to return to WinRM Fleet Console.' -ForegroundColor DarkGray
    Write-Host
    while ($true) {
        try {
            $remotePath = Invoke-Command -Session $Session -ScriptBlock { (Get-Location).Path } -ErrorAction Stop
            $promptPath = [string]@($remotePath)[0]
        }
        catch { $promptPath = '?' }

        Write-Host "[$ComputerName]: PS $promptPath> " -NoNewline -ForegroundColor Yellow
        $commandText = Read-Host
        if ($null -eq $commandText) { continue }
        $trimmedCommand = $commandText.Trim()
        if ($trimmedCommand -in @('exit', 'Exit-PSSession')) { break }
        if ([string]::IsNullOrWhiteSpace($trimmedCommand)) { continue }
        if ($trimmedCommand -in @('cls', 'clear', 'Clear-Host')) {
            Clear-Host
            continue
        }

        try {
            $outputWidth = try { [Math]::Max(80, [Console]::WindowWidth - 1) } catch { 160 }
            $renderedOutput = @(Invoke-Command -Session $Session -ErrorAction Stop -ArgumentList $commandText, $outputWidth -ScriptBlock {
                param([string]$Text, [int]$Width)
                try {
                    $command = [scriptblock]::Create($Text)
                    . $command 2>&1 | Out-String -Stream -Width $Width
                }
                catch { $_ | Out-String -Stream -Width $Width }
            })
            foreach ($line in $renderedOutput) { Write-Host ([string]$line) }
        }
        catch { Write-Host $_ -ForegroundColor Red }
    }
}

function Enter-TuiRemoteShell {
    param([object[]]$Targets)

    if ($Targets.Count -ne 1) {
        $script:lastMessage = 'Interactive shell requires exactly one current/selected host.'
        return
    }
    if (-not (Request-TuiCredential -Targets $Targets)) { return }

    $target = $Targets[0]
    $userName = if ($null -ne $script:credential) { $script:credential.UserName } else { [Environment]::UserName }
    $runId = [guid]::NewGuid().ToString('N')
    $session = $null
    $consoleRestored = $false
    $connected = $false
    $null = Write-WinRMAuditEvent -StorePath $script:StorePath -Event 'InteractiveSessionStarted' -Data @{
        RunId = $runId
        Target = $target | Select-Object Address, ComputerName, VerifiedConnectionHost, Port, Transport
        ConnectAs = $userName
    }
    Show-TuiBusyStatus -Title 'Connecting interactive shell' -Detail "$($target.ComputerName) as $userName"
    try {
        $session = New-WinRMTargetSession -Target $target -Credential $script:credential -OpenTimeoutMs ([int]$script:config.Settings.OpenTimeoutMs) -SkipDns:([bool]$script:config.Settings.SkipDns)
        $remoteComputerName = [string]@(Invoke-Command -Session $session -ErrorAction SilentlyContinue -ScriptBlock {
            try {
                $oemCodePage = [Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
                $oemEncoding = [Text.Encoding]::GetEncoding($oemCodePage)
                [Console]::InputEncoding = $oemEncoding
                [Console]::OutputEncoding = $oemEncoding
                $global:OutputEncoding = $oemEncoding
            }
            catch {}
            $env:COMPUTERNAME
        })[0]
        if (-not [string]::IsNullOrWhiteSpace($remoteComputerName)) {
            $target.ComputerName = $remoteComputerName
            $target.VerifiedConnectionHost = $remoteComputerName
            $inventoryHost = @($script:inventory | Where-Object { $_.Address -eq $target.Address } | Select-Object -First 1)
            if ($inventoryHost.Count -gt 0) { $inventoryHost[0].ComputerName = $remoteComputerName; Save-TuiState }
        }
        $connected = $true
        $null = Write-WinRMAuditEvent -StorePath $script:StorePath -Event 'InteractiveSessionConnected' -Data @{ RunId = $runId; Target = $target.ComputerName; ConnectAs = $userName }
        Clear-TuiBufferedInput
        Restore-ConsoleTui
        $consoleRestored = $true
        Write-Host "Connected to $($target.ComputerName) as $userName." -ForegroundColor Cyan
        Invoke-TuiRemoteCommandShell -Session $session -ComputerName $target.ComputerName
        $null = Write-WinRMAuditEvent -StorePath $script:StorePath -Event 'InteractiveSessionEnded' -Data @{ RunId = $runId; Target = $target.ComputerName; ConnectAs = $userName }
    }
    catch {
        $null = Write-WinRMAuditEvent -StorePath $script:StorePath -Event 'InteractiveSessionFailed' -Data @{
            RunId = $runId
            Target = $target.ComputerName
            ConnectAs = $userName
            Phase = $(if ($connected) { 'InteractiveShell' } else { 'Connect' })
            Detail = $_.ToString()
        }
        if ($consoleRestored) {
            Write-Warning $_
            Read-Host 'Press Enter to return' | Out-Null
        }
        else {
            Clear-TuiBufferedInput
            Show-TuiNotice 'Connection failed' @($_.ToString()) Red
        }
    }
    finally {
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
        if ($consoleRestored) { Initialize-ConsoleTui -Title 'WinRM Fleet Console' }
        $script:credential = $null
        Clear-TuiBufferedInput
    }
}

function Show-TuiAudit {
    $events = @(Get-WinRMAuditEvent -StorePath $StorePath -Last 30)
    if ($events.Count -eq 0) { Show-TuiNotice 'Audit log' @('No events yet.'); return }
    $lines = @($events | ForEach-Object {
        $summary = if ($null -ne $_.Data -and @($_.Data.PSObject.Properties.Match('Action')).Count -gt 0) { " $($_.Data.Action)" } else { '' }
        '{0}  {1}{2}' -f ([DateTime]$_.Time).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss'), $_.Event, $summary
    })
    Show-TuiNotice 'Last audit events' $lines
}

function Invoke-TuiAddon {
    param(
        [Parameter(Mandatory)]$Addon,
        [Parameter(Mandatory)][object[]]$Addons,
        [Parameter(Mandatory)][int]$ActiveTabIndex
    )

    if ($Addon.Status -ne 'Ready') {
        Show-TuiNotice "Add-on: $($Addon.Name)" @($Addon.Detail) Red
        return 'Home'
    }

    $failure = $null
    $addonOutput = @()
    $null = Write-WinRMAuditEvent -StorePath $script:StorePath -Event 'AddonStarted' -Data @{ Id = $Addon.Id; Version = $Addon.Version }
    try {
        Import-Module $script:toolsPath -Global -ErrorAction Stop
        $loaded = Import-WinRMAddon -Addon $Addon
        $context = New-TuiAddonContext -Addon $Addon -Addons $Addons -ActiveTabIndex $ActiveTabIndex
        Clear-TuiBufferedInput
        $addonOutput = @(& $loaded.Command -Context $context)
        $null = Write-WinRMAuditEvent -StorePath $script:StorePath -Event 'AddonCompleted' -Data @{ Id = $Addon.Id; Version = $Addon.Version }
    }
    catch {
        $failure = $_
        $null = Write-WinRMAuditEvent -StorePath $script:StorePath -Event 'AddonFailed' -Data @{ Id = $Addon.Id; Version = $Addon.Version; Detail = $_.ToString() }
    }
    finally {
        # Trusted add-ons may replace commands or own the console. Restore both
        # the screen and the root command exports before changing tabs.
        if ($null -ne (Get-Command Restore-ConsoleTui -ErrorAction SilentlyContinue)) { Restore-ConsoleTui }
        Import-Module $script:tuiPath -Force -Global -ErrorAction Stop
        Import-Module $script:managerPath -Force -Global -ErrorAction Stop
        Import-Module $script:toolsPath -Force -Global -ErrorAction Stop
        Import-Module $script:addonsPath -Force -Global -ErrorAction Stop
        Initialize-ConsoleTui -Title 'WinRM Fleet Console'
        Clear-TuiBufferedInput
    }
    if ($null -ne $failure) {
        Show-TuiNotice "Add-on failed: $($Addon.Name)" @($failure.ToString()) Red
        return 'Home'
    }
    foreach ($value in @($addonOutput | Select-Object -Last 1)) {
        if ($value -is [string] -and $value -in @('Home', 'NextTab', 'PreviousTab')) { return $value }
        if (@($value.PSObject.Properties.Match('Navigation')).Count -gt 0 -and
            [string]$value.Navigation -in @('Home', 'NextTab', 'PreviousTab')) { return [string]$value.Navigation }
    }
    return 'Home'
}

function Switch-TuiTab {
    param([Parameter(Mandatory)][int]$TabIndex)

    while ($TabIndex -gt 0 -and $script:availableAddons.Count -gt 0) {
        $addonIndex = $TabIndex - 1
        if ($addonIndex -ge $script:availableAddons.Count) { return }
        $navigation = Invoke-TuiAddon -Addon $script:availableAddons[$addonIndex] -Addons $script:availableAddons -ActiveTabIndex $TabIndex
        $tabCount = $script:availableAddons.Count + 1
        switch ($navigation) {
            'NextTab' { $TabIndex = ($TabIndex + 1) % $tabCount }
            'PreviousTab' { $TabIndex = ($TabIndex - 1 + $tabCount) % $tabCount }
            default { $TabIndex = 0 }
        }
    }
}

function Stop-TuiAddons {
    foreach ($addonId in @($script:addonStates.Keys)) {
        $state = $script:addonStates[$addonId]
        if (-not $state.ContainsKey('Dispose') -or $state.Dispose -isnot [scriptblock]) { continue }
        try { $null = & $state.Dispose -State $state }
        catch {
            $null = Write-WinRMAuditEvent -StorePath $script:StorePath -Event 'AddonDisposeFailed' -Data @{ Id = $addonId; Detail = $_.ToString() }
        }
    }
    $script:addonStates.Clear()
}

function Show-TuiHelp {
    Show-TuiNotice 'Keyboard help' @(
        'Navigation: Up/Down, PgUp/PgDn, Home/End; Space = select; A = select visible; Esc = clear selection/filter',
        'Tab / Shift+Tab switches Fleet and add-on tabs.',
        'D discovery | N network profiles | F filter | I inventory',
        'Login and password are requested before every remote operation.',
        'M add a known host manually',
        'X command/file script | L script library | Enter interactive PSSession',
        'U upload | O download/collect | P restart/shutdown',
        'G groups | T tags | B blacklist | H details | J audit',
        'E export CSV | V import CSV | S settings | R reload | Q quit',
        '',
        'Filters: text, group:Office, tag:prod, status:Connected, os:Server, ip:10.*, disk:<10, !tag:test',
        'Selected hosts are the action scope; when none are selected, actions use the current row.'
    )
}

function Edit-TuiNetworks {
    $lines = @('Use + name|range|http|https, - number, or press Enter to cancel.')
    for ($i = 0; $i -lt $config.Networks.Count; $i++) { $lines += "  $($i + 1). $($config.Networks[$i].Name) | $($config.Networks[$i].Range) | $($config.Networks[$i].HttpPort)/$($config.Networks[$i].HttpsPort)" }
    Show-TuiNotice 'Network profiles' $lines
    $answer = Read-TuiPrompt 'Change'
    if ($answer -match '^\+\s*(.+)$') {
        $parts = $Matches[1].Split('|')
        if ($parts.Count -lt 2) { $script:lastMessage = 'Expected: + name|range|http|https'; return }
        $config.Networks = @($config.Networks) + [pscustomobject][ordered]@{ Name = $parts[0].Trim(); Range = $parts[1].Trim(); HttpPort = $(if ($parts.Count -gt 2) { [int]$parts[2] } else { 5985 }); HttpsPort = $(if ($parts.Count -gt 3) { [int]$parts[3] } else { 5986 }); Enabled = $true }
        Save-TuiState; $script:lastMessage = 'Network profile added.'
    }
    elseif ($answer -match '^-\s*(\d+)$') {
        $index = [int]$Matches[1] - 1
        if ($index -ge 0 -and $index -lt $config.Networks.Count) { $script:config.Networks = @($config.Networks | Where-Object { $_ -ne $config.Networks[$index] }); Save-TuiState; $script:lastMessage = 'Network profile removed.' }
    }
}

function Edit-TuiBlacklist {
    param($CurrentHost)
    $lines = @('Entries use wildcard names/IPs or CIDR. Use + pattern|reason, - number, or current.')
    for ($i = 0; $i -lt $config.Blacklist.Count; $i++) { $lines += "  $($i + 1). $($config.Blacklist[$i].Pattern)  $($config.Blacklist[$i].Reason)" }
    Show-TuiNotice 'Blacklist' $lines
    $default = if ($null -ne $CurrentHost) { 'current' } else { '' }
    $answer = Read-TuiPrompt 'Change' $default
    if ($answer -eq 'current' -and $null -ne $CurrentHost) { $pattern = $CurrentHost.Address; $reason = 'Added from host list' }
    elseif ($answer -match '^\+\s*(.+)$') { $parts = $Matches[1].Split('|', 2); $pattern = $parts[0].Trim(); $reason = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' } }
    elseif ($answer -match '^-\s*(\d+)$') {
        $index = [int]$Matches[1] - 1
        if ($index -ge 0 -and $index -lt $config.Blacklist.Count) { $script:config.Blacklist = @($config.Blacklist | Where-Object { $_ -ne $config.Blacklist[$index] }); Save-TuiState; $script:lastMessage = 'Blacklist entry removed.' }
        return
    }
    else { return }
    $script:config = Add-WinRMBlacklistEntry -Config $config -Pattern $pattern -Reason $reason
    Save-TuiState; $script:lastMessage = "Blacklisted: $pattern"
}

function Edit-TuiSettings {
    $current = "timeout=$($config.Settings.DiscoveryTimeoutMs);open=$($config.Settings.OpenTimeoutMs);command=$($config.Settings.CommandTimeoutSec);throttle=$($config.Settings.ThrottleLimit);skipdns=$($config.Settings.SkipDns)"
    $answer = Read-TuiPrompt 'Settings timeout/open/command/throttle/skipdns' $current
    foreach ($pair in $answer.Split(';')) {
        $parts = $pair.Split('=', 2); if ($parts.Count -ne 2) { continue }
        switch ($parts[0].Trim().ToLowerInvariant()) {
            'timeout' { $config.Settings.DiscoveryTimeoutMs = [Math]::Max(100, [int]$parts[1]) }
            'open' { $config.Settings.OpenTimeoutMs = [Math]::Max(100, [int]$parts[1]) }
            'command' { $config.Settings.CommandTimeoutSec = [Math]::Max(1, [int]$parts[1]) }
            'throttle' { $config.Settings.ThrottleLimit = [Math]::Min(128, [Math]::Max(1, [int]$parts[1])) }
            'skipdns' { $config.Settings.SkipDns = $parts[1].Trim() -match '^(?i:true|1|yes)$' }
        }
    }
    Save-TuiState; $script:lastMessage = 'Settings saved.'
}

try {
    Initialize-ConsoleTui -Title 'WinRM Fleet Console'
    $running = $true
    while ($running) {
        $visible = @(Get-TuiVisibleHosts)
        if ($visible.Count -eq 0) { $cursor = 0; $offset = 0 }
        else { $cursor = [Math]::Min($cursor, $visible.Count - 1) }
        $height = Get-ConsoleTuiHeight
        $width = Get-ConsoleTuiWidth
        $pageSize = [Math]::Max(1, $height - 10)
        if ($cursor -lt $offset) { $offset = $cursor }
        if ($cursor -ge $offset + $pageSize) { $offset = $cursor - $pageSize + 1 }
        $offset = [Math]::Max(0, [Math]::Min($offset, [Math]::Max(0, $visible.Count - $pageSize)))
        $connected = @($inventory | Where-Object { $_.ConnectionStatus -eq 'Connected' }).Count
        Start-ConsoleTuiFrame
        Write-ConsoleTuiLine (Format-ConsoleTuiText ' WinRM Fleet Console ' $width) Black DarkCyan
        Write-ConsoleTuiLine (Format-ConsoleTuiText (Get-TuiTabText -Addons $availableAddons -ActiveTabIndex 0) $width) Black Cyan
        Write-ConsoleTuiLine (Format-ConsoleTuiText (" Hosts: {0}  Visible: {1}  Connected: {2}  Selected: {3}  Credentials: ask on connect" -f $inventory.Count, $visible.Count, $connected, $selected.Count) $width) Gray
        Write-ConsoleTuiLine (Format-ConsoleTuiText (" Filter: {0}" -f $(if ($filter) { $filter } else { '<none>' })) $width) DarkGray
        $nameWidth = [Math]::Max(12, [Math]::Min(28, [int]($width * 0.23)))
        $ipWidth = 15; $groupWidth = [Math]::Max(10, [Math]::Min(18, [int]($width * 0.14)))
        $statusWidth = 16; $diskWidth = 8
        $osWidth = [Math]::Max(8, $width - $nameWidth - $ipWidth - $groupWidth - $statusWidth - $diskWidth - 12)
        Write-ConsoleTuiLine (Format-ConsoleTuiColumns @(' ', 'NAME', 'ADDRESS', 'GROUP', 'STATUS', 'DISK', 'OS') @(1, $nameWidth, $ipWidth, $groupWidth, $statusWidth, $diskWidth, $osWidth)) Black DarkCyan
        for ($row = 0; $row -lt $pageSize; $row++) {
            $index = $offset + $row
            if ($index -ge $visible.Count) { Write-ConsoleTuiLine; continue }
            $item = $visible[$index]
            $mark = if ($selected.ContainsKey([string]$item.Id)) { '*' } else { ' ' }
            $disk = if ($null -ne $item.FreeSpaceGB -and [string]$item.FreeSpaceGB) { '{0:N1}G' -f [double]$item.FreeSpaceGB } else { '-' }
            $line = Format-ConsoleTuiColumns @($mark, $item.ComputerName, $item.Address, (@($item.Groups) -join ','), $item.Status, $disk, $item.OS) @(1, $nameWidth, $ipWidth, $groupWidth, $statusWidth, $diskWidth, $osWidth)
            $foreground = if ($item.Status -in @('Connected', 'Succeeded')) {
                [ConsoleColor]::Green
            }
            elseif ($item.Status -in @('AccessDenied', 'AuthenticationError', 'Failed')) {
                [ConsoleColor]::Red
            }
            else {
                [ConsoleColor]::Gray
            }
            if ($index -eq $cursor) { Write-ConsoleTuiLine $line Black Cyan } else { Write-ConsoleTuiLine $line $foreground Black }
        }
        Write-ConsoleTuiLine (Format-ConsoleTuiText (" $lastMessage") $width) Yellow
        Write-ConsoleTuiLine (Format-ConsoleTuiText ' Tab switch  D scan  F filter  Space select  I inventory  X script  Enter shell  ? help  Q quit ' $width) Black DarkGray
        Complete-ConsoleTuiFrame

        $key = Get-ConsoleTuiKey
        if ($null -eq $key) { Start-Sleep -Milliseconds 15; continue }
        switch ($key.Key) {
            'UpArrow' { if ($cursor -gt 0) { $cursor-- } }
            'DownArrow' { if ($cursor -lt $visible.Count - 1) { $cursor++ } }
            'PageUp' { $cursor = [Math]::Max(0, $cursor - $pageSize) }
            'PageDown' { $cursor = [Math]::Min([Math]::Max(0, $visible.Count - 1), $cursor + $pageSize) }
            'Home' { $cursor = 0 }
            'End' { $cursor = [Math]::Max(0, $visible.Count - 1) }
            'Spacebar' { if ($visible.Count -gt 0) { $id = [string]$visible[$cursor].Id; if ($selected.ContainsKey($id)) { $selected.Remove($id) } else { $selected[$id] = $true } } }
            'A' { foreach ($item in $visible) { $selected[[string]$item.Id] = $true }; $lastMessage = "Selected $($visible.Count) visible host(s)." }
            'Escape' { if ($selected.Count -gt 0) { $selected.Clear(); $lastMessage = 'Selection cleared.' } elseif ($filter) { $filter = ''; $lastMessage = 'Filter cleared.' } }
            'Tab' {
                if ($availableAddons.Count -gt 0) {
                    $targetTab = if (($key.Modifiers -band [ConsoleModifiers]::Shift) -ne 0) { $availableAddons.Count } else { 1 }
                    Switch-TuiTab -TabIndex $targetTab
                }
            }
            'D' { Invoke-TuiDiscovery }
            'N' { Edit-TuiNetworks }
            'F' { $filter = Read-TuiPrompt 'Filter query' $filter; $cursor = 0; $offset = 0 }
            'M' { Add-TuiManualHost }
            'I' { Invoke-TuiRemoteAction -Action Inventory -Targets @(Get-TuiActionHosts $visible) }
            'X' { Invoke-TuiScript -Targets @(Get-TuiActionHosts $visible) }
            'L' { Invoke-TuiLibraryScript -Targets @(Get-TuiActionHosts $visible) }
            'U' { Invoke-TuiTransfer -Direction Upload -Targets @(Get-TuiActionHosts $visible) }
            'O' { Invoke-TuiTransfer -Direction Download -Targets @(Get-TuiActionHosts $visible) }
            'Enter' { Enter-TuiRemoteShell -Targets @(Get-TuiActionHosts $visible) }
            'P' {
                $targets = @(Get-TuiActionHosts $visible); if ($targets.Count -eq 0) { continue }
                $action = Read-TuiPrompt 'Power action: restart or shutdown' 'restart'
                if ($action -notin @('restart', 'shutdown')) { continue }
                if (Confirm-ConsoleTui "$action $($targets.Count) host(s) after 60 seconds? Unsaved remote work may be lost.") { Invoke-TuiRemoteAction -Action $(if ($action -eq 'restart') { 'Restart' } else { 'Shutdown' }) -Targets $targets -DelaySeconds 60 }
            }
            'G' { $targets = @(Get-TuiActionHosts $visible); if ($targets.Count -gt 0) { $value = Read-TuiPrompt 'Comma-separated groups'; foreach ($target in $targets) { $hostItem = $inventory | Where-Object Address -eq $target.Address | Select-Object -First 1; $null = Set-WinRMHostGroups $hostItem @($value.Split(',')) }; Save-TuiState; $lastMessage = 'Groups updated.' } }
            'T' { $targets = @(Get-TuiActionHosts $visible); if ($targets.Count -gt 0) { $value = Read-TuiPrompt 'Comma-separated tags'; foreach ($target in $targets) { $hostItem = $inventory | Where-Object Address -eq $target.Address | Select-Object -First 1; $null = Set-WinRMHostTags $hostItem @($value.Split(',')) }; Save-TuiState; $lastMessage = 'Tags updated.' } }
            'B' { Edit-TuiBlacklist $(if ($visible.Count -gt 0) { $visible[$cursor] } else { $null }) }
            'H' { if ($visible.Count -gt 0) { $item = $visible[$cursor]; Show-TuiNotice 'Host details' @($item | ConvertTo-Json -Depth 8).Split("`n") } }
            'J' { Show-TuiAudit }
            'E' { $path = Read-TuiPrompt 'Export CSV path' (Join-Path $StorePath 'inventory.csv'); $null = Export-WinRMInventoryCsv -HostRecord $inventory -Path $path; $lastMessage = "Exported: $path" }
            'V' { $path = Read-TuiPrompt 'Import CSV path'; if (Test-Path -LiteralPath $path) { $inventory = @(Import-WinRMInventoryCsv -Path $path -Current $inventory -Blacklist @($config.Blacklist)); Save-TuiState; $lastMessage = "Imported: $path" } }
            'S' { Edit-TuiSettings }
            'R' { $config = Get-WinRMManagerConfig -StorePath $StorePath; $inventory = @(Get-WinRMInventory -StorePath $StorePath); $availableAddons = @(Get-WinRMAddon -Root @($bundledAddonsPath, $store.Addons) -HostVersion $hostVersion); $lastMessage = 'State and add-on tabs reloaded.' }
            'Oem2' { Show-TuiHelp }
            'Q' { $running = $false }
        }
    }
}
finally {
    Stop-TuiAddons
    Restore-ConsoleTui
}
