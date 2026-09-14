#Requires -Version 5.1
<#
.SYNOPSIS
    Runs inventory, commands, or scheduled power actions on selected WinRM hosts.
.DESCRIPTION
    Accepts Find-WinRM objects from the pipeline or a saved CSV. Chooses one
    endpoint per IP, preferring a previously connected endpoint, then confirmed
    WS-Management, then HTTPS. Does not retry commands on another endpoint.
    Imported inventories require -ComputerName, -Select, or -All. Pipeline
    input is already a selection and can be narrowed with Where-Object.
    -Select opens a numbered console picker. Restart and Shutdown always ask
    for confirmation with the full target list. -WhatIf never opens sessions.
    Credentials stay in memory; saved ConnectAs is informational only.
    Commands execute remotely: use param(...) and -ArgumentList for local values,
    not local variables or $using:. Results and command output go to JSONL logs.
    A command timeout does not roll back remote side effects.
.EXAMPLE
    .\Invoke-OfficeComputer.ps1 -InventoryPath .\office.csv -Select -Action Inventory -Credential (Get-Credential)
.EXAMPLE
    Import-Csv .\office.csv | Where-Object ComputerName -like 'OFFICE-PC*' |
        .\Invoke-OfficeComputer.ps1 -Action Command -ScriptBlock { Get-Service Spooler }
.EXAMPLE
    .\Invoke-OfficeComputer.ps1 -InventoryPath .\office.csv -ComputerName PC01,PC02 -Action Restart -WhatIf
.EXAMPLE
    .\Invoke-OfficeComputer.ps1 -InventoryPath .\office.csv -All -Action Inventory -SavePath .\office-updated.csv
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Pipeline')]
param(
    [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Pipeline')]
    [psobject[]]$InputObject,
    [Parameter(Mandatory, ParameterSetName = 'File')]
    [string]$InventoryPath,
    [string[]]$ComputerName,
    [switch]$Select,
    [switch]$All,
    [ValidateSet('Inventory', 'Command', 'Restart', 'Shutdown')]
    [string]$Action = 'Inventory',
    [scriptblock]$ScriptBlock,
    [object[]]$ArgumentList = @(),
    [pscredential]$Credential,
    [ValidateSet('Default', 'Negotiate', 'Kerberos')][string]$Authentication = 'Default',
    [ValidateRange(1, 128)][int]$ThrottleLimit = 16,
    [ValidateRange(100, 60000)][int]$OpenTimeoutMs = 5000,
    [ValidateRange(1, 86400)][int]$CommandTimeoutSec = 60,
    [ValidateRange(30, 315360000)][int]$DelaySeconds = 60,
    [switch]$SkipDns,
    [string]$LogPath,
    [string]$SavePath
)
begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    Import-Module (Join-Path $PSScriptRoot 'WinRM\WinRM.Tools.psm1') -ErrorAction Stop
    $records = [System.Collections.Generic.List[object]]::new()
    if ($Action -eq 'Command' -and $null -eq $ScriptBlock) { throw '-Action Command requires -ScriptBlock.' }
    if ($Action -ne 'Command' -and ($null -ne $ScriptBlock -or $PSBoundParameters.ContainsKey('ArgumentList'))) {
        throw '-ScriptBlock and -ArgumentList are only valid with -Action Command.'
    }
    if ($SavePath -and $Action -ne 'Inventory') { throw '-SavePath is only valid with -Action Inventory.' }
    if ($All -and ($Select -or $ComputerName)) { throw 'Use -All or a selection, not both.' }
}
process {
    if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
        foreach ($record in $InputObject) { $records.Add($record) }
    }
}
end {
    if ($PSCmdlet.ParameterSetName -eq 'File') {
        if (-not ($All -or $Select -or $ComputerName)) {
            throw 'Choose targets using -ComputerName, -Select, or -All.'
        }
        foreach ($record in (Import-Csv -LiteralPath $InventoryPath)) { $records.Add($record) }
    }
    if ($records.Count -eq 0) { Write-Warning 'No computers supplied.'; return }
    foreach ($record in $records) {
        foreach ($required in @('Address', 'Port', 'Transport')) {
            if ($null -eq $record.PSObject.Properties[$required]) { throw "Missing inventory field: $required" }
        }
        $ip = $null
        $port = 0
        if (-not [Net.IPAddress]::TryParse([string]$record.Address, [ref]$ip) -or
            $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
            $ip.IPAddressToString -ne [string]$record.Address) { throw "Invalid IPv4 address: $($record.Address)" }
        if (-not [int]::TryParse([string]$record.Port, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
            throw "Invalid port for $($record.Address): $($record.Port)"
        }
        if ($record.Transport -notin @('HTTP', 'HTTPS')) { throw "Invalid transport: $($record.Transport)" }
        foreach ($default in @('ComputerName', 'ConnectionStatus', 'DiscoveryStatus')) {
            if ($null -eq $record.PSObject.Properties[$default]) {
                $value = if ($default -eq 'ComputerName') { $record.Address } else { 'Unknown' }
                $record | Add-Member -NotePropertyName $default -NotePropertyValue $value
            }
        }
    }
    $candidates = @($records)
    if ($ComputerName) {
        foreach ($requested in $ComputerName) {
            if (-not @($candidates | Where-Object { $_.ComputerName -eq $requested -or $_.Address -eq $requested }).Count) {
                throw "Computer not present in inventory: $requested"
            }
        }
        $candidates = @($candidates | Where-Object { $_.ComputerName -in $ComputerName -or $_.Address -in $ComputerName })
    }
    $targets = @($candidates | Group-Object Address | ForEach-Object {
        $_.Group | Sort-Object `
            @{ Expression = { $_.ConnectionStatus -eq 'Connected' }; Descending = $true }, `
            @{ Expression = { $_.DiscoveryStatus -eq 'WSManConfirmed' }; Descending = $true }, `
            @{ Expression = { $_.Transport -eq 'HTTPS' }; Descending = $true }, Port | Select-Object -First 1
    } | Sort-Object ComputerName, Address)
    if ($Select) {
        for ($i = 0; $i -lt $targets.Count; $i++) {
            Write-Host ('[{0}] {1} ({2}) {3}:{4} {5}' -f ($i + 1), $targets[$i].ComputerName,
                $targets[$i].Address, $targets[$i].Transport, $targets[$i].Port, $targets[$i].ConnectionStatus)
        }
        $answer = Read-Host 'Select numbers separated by commas (empty cancels)'
        if ([string]::IsNullOrWhiteSpace($answer)) { return }
        if ($answer -notmatch '^\s*\d+\s*(,\s*\d+\s*)*$') { throw 'Enter comma-separated numbers.' }
        $indices = @($answer.Split(',') | ForEach-Object {
            $index = 0
            if (-not [int]::TryParse($_.Trim(), [ref]$index) -or $index -lt 1 -or $index -gt $targets.Count) {
                throw "Invalid selection: $_"
            }
            $index - 1
        } | Select-Object -Unique)
        $targets = @($indices | ForEach-Object { $targets[$_] })
    }
    if ($targets.Count -eq 0) { Write-Warning 'No computers selected.'; return }
    $targetList = ($targets | ForEach-Object { '{0} ({1}) {2}:{3}' -f $_.ComputerName, $_.Address, $_.Transport, $_.Port }) -join "`n"
    if (-not $PSCmdlet.ShouldProcess($targetList, $Action)) { return }
    if ($Action -in @('Restart', 'Shutdown')) {
        $prompt = "$Action in $DelaySeconds seconds on these $($targets.Count) computer(s):`n$targetList`nWindows will force applications to close when the delay expires; unsaved work can be lost."
        if (-not $PSCmdlet.ShouldContinue($prompt, 'Confirm power action')) { return }
    }
    $runId = [guid]::NewGuid().ToString('N')
    if (-not $LogPath) { $LogPath = Join-Path $PWD ("winrm-logs\{0}-{1}.jsonl" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $runId) }
    $logFullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)
    $parent = [IO.Path]::GetDirectoryName($logFullPath)
    $null = [IO.Directory]::CreateDirectory($parent)
    # Open the log before making any remote changes; fail early if it is unwritable.
    $writer = [IO.StreamWriter]::new($logFullPath, $true, [Text.UTF8Encoding]::new($false))
    $writer.AutoFlush = $true
    $completed = [System.Collections.Generic.HashSet[string]]::new()
    $inventoryResults = [System.Collections.Generic.List[object]]::new()
    try {
        $writer.WriteLine(([ordered]@{
            Event = 'RunStarted'; RunId = $runId; Time = [DateTime]::UtcNow.ToString('o')
            Action = $Action; ConnectAs = Get-WinRMConnectAs $Credential
            Targets = @($targets | Select-Object Address, ComputerName, Port, Transport)
        } | ConvertTo-Json -Depth 6 -Compress))
        Write-Verbose "Audit log: $logFullPath"
        $options = @{
            Action = $Action; Credential = $Credential; Authentication = $Authentication
            OpenTimeoutMs = $OpenTimeoutMs; CommandTimeoutSec = $CommandTimeoutSec
            ArgumentList = $ArgumentList; DelaySeconds = $DelaySeconds
            SkipDns = [bool]$SkipDns
        }
        if ($null -ne $ScriptBlock) { $options.CommandText = $ScriptBlock.ToString() }
        Invoke-WinRMBatch -Target $targets -Options $options -ThrottleLimit $ThrottleLimit | ForEach-Object {
            $result = $_
            $writer.WriteLine(([ordered]@{ Event = 'Result'; RunId = $runId; Result = $result } | ConvertTo-Json -Depth 12 -Compress))
            $null = $completed.Add([string]$result.Address)
            if ($SavePath) { $inventoryResults.Add($result) }
            $result
        }
        if ($SavePath) {
            $inventoryResults | Select-Object * -ExcludeProperty Output | Export-Csv -LiteralPath $SavePath -NoTypeInformation -Encoding UTF8
        }
    }
    finally {
        try {
            foreach ($target in $targets) {
                if (-not $completed.Contains([string]$target.Address)) {
                    $writer.WriteLine(([ordered]@{
                        Event = 'Result'; RunId = $runId
                        Result = @{ Address = $target.Address; ComputerName = $target.ComputerName; Action = $Action
                            Status = 'InterruptedOrNotStarted'; Detail = 'No final result received; remote side effects are unknown.' }
                    } | ConvertTo-Json -Depth 6 -Compress))
                }
            }
            $writer.WriteLine(([ordered]@{ Event = 'RunEnded'; RunId = $runId; Time = [DateTime]::UtcNow.ToString('o'); Completed = $completed.Count } | ConvertTo-Json -Compress))
        }
        finally { $writer.Dispose() }
    }
}
