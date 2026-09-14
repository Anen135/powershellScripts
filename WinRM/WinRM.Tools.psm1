#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-WinRMDnsNameEndOffset {
    param([Parameter(Mandatory)][byte[]]$Message, [Parameter(Mandatory)][int]$Offset)

    while ($Offset -lt $Message.Length) {
        $length = [int]$Message[$Offset]
        if (($length -band 0xC0) -eq 0xC0) { return $Offset + 2 }
        $Offset++
        if ($length -eq 0) { return $Offset }
        $Offset += $length
    }
    return -1
}

function Get-WinRMNetBiosNameFromResponse {
    param([Parameter(Mandatory)][byte[]]$Response)

    if ($Response.Length -lt 12) { return $null }
    $questionCount = ([int]$Response[4] * 256) + [int]$Response[5]
    $answerCount = ([int]$Response[6] * 256) + [int]$Response[7]
    $offset = 12
    for ($question = 0; $question -lt $questionCount; $question++) {
        $offset = Get-WinRMDnsNameEndOffset -Message $Response -Offset $offset
        if ($offset -lt 0 -or $offset + 4 -gt $Response.Length) { return $null }
        $offset += 4
    }
    for ($answer = 0; $answer -lt $answerCount; $answer++) {
        $offset = Get-WinRMDnsNameEndOffset -Message $Response -Offset $offset
        if ($offset -lt 0 -or $offset + 10 -gt $Response.Length) { return $null }
        $recordType = ([int]$Response[$offset] * 256) + [int]$Response[$offset + 1]
        $dataLength = ([int]$Response[$offset + 8] * 256) + [int]$Response[$offset + 9]
        $dataOffset = $offset + 10
        if ($dataOffset + $dataLength -gt $Response.Length) { return $null }
        if ($recordType -eq 0x21 -and $dataLength -gt 1) {
            $nameCount = [int]$Response[$dataOffset]
            for ($nameIndex = 0; $nameIndex -lt $nameCount; $nameIndex++) {
                $entryOffset = $dataOffset + 1 + ($nameIndex * 18)
                if ($entryOffset + 18 -gt $dataOffset + $dataLength) { break }
                if ($Response[$entryOffset + 15] -eq 0x20) {
                    return ([Text.Encoding]::ASCII.GetString($Response, $entryOffset, 15) -replace '[\x00 ]+$', '')
                }
            }
        }
        $offset = $dataOffset + $dataLength
    }
    return $null
}

function Resolve-WinRMNetBiosComputerName {
    param([Parameter(Mandatory)][string]$Address, [ValidateRange(100, 30000)][int]$TimeoutMs = 1000)

    # NBSTAT wildcard query sent directly to the target. Unlike nbtstat.exe this
    # does not walk every VPN/virtual adapter and has a strict receive timeout.
    $request = [byte[]]::new(50)
    $request[0] = 0x57; $request[1] = 0x52
    $request[4] = 0x00; $request[5] = 0x01
    $request[12] = 0x20
    $netBiosName = [byte[]]::new(16)
    $netBiosName[0] = 0x2A
    for ($index = 0; $index -lt $netBiosName.Length; $index++) {
        $request[13 + ($index * 2)] = 0x41 + (($netBiosName[$index] -shr 4) -band 0x0F)
        $request[14 + ($index * 2)] = 0x41 + ($netBiosName[$index] -band 0x0F)
    }
    $request[45] = 0x00
    $request[46] = 0x00; $request[47] = 0x21
    $request[48] = 0x00; $request[49] = 0x01

    $client = [Net.Sockets.UdpClient]::new()
    try {
        $client.Client.SendTimeout = $TimeoutMs
        $client.Client.ReceiveTimeout = $TimeoutMs
        $client.Connect($Address, 137)
        $null = $client.Send($request, $request.Length)
        $sender = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
        $response = $client.Receive([ref]$sender)
        Get-WinRMNetBiosNameFromResponse -Response $response
    }
    catch { Write-Verbose "NetBIOS lookup for ${Address}: $($_.Exception.Message)" }
    finally { $client.Dispose() }
}

function Resolve-WinRMComputerName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Address, [int]$TimeoutMs = 1000)
    $name = $Address
    $connectionHost = $Address
    $source = 'Address'
    try {
        $lookup = [System.Net.Dns]::GetHostEntryAsync($Address)
        if ($lookup.Wait($TimeoutMs)) {
            $name = $lookup.Result.HostName
            $source = 'DNS'
        }
    }
    catch { Write-Verbose "DNS lookup for ${Address}: $($_.Exception.Message)" }

    if ($name -eq $Address) {
        $parsedAddress = $null
        if ([Net.IPAddress]::TryParse($Address, [ref]$parsedAddress) -and
            $parsedAddress.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
            $netBiosResult = Resolve-WinRMNetBiosComputerName -Address $Address -TimeoutMs $TimeoutMs
            if (-not [string]::IsNullOrWhiteSpace($netBiosResult)) {
                $name = $netBiosResult
                $source = 'NetBIOS'
            }
        }
    }

    # A discovered name may be displayed, but must not redirect authentication
    # unless its forward lookup points back to the scanned address.
    if ($name -ne $Address) {
        try {
            $forward = [System.Net.Dns]::GetHostAddressesAsync($name)
            if ($forward.Wait($TimeoutMs) -and
                $Address -in @($forward.Result | ForEach-Object { $_.IPAddressToString })) {
                $connectionHost = $name
            }
        }
        catch { Write-Verbose "Forward lookup for ${name}: $($_.Exception.Message)" }
    }
    [pscustomobject]@{ ComputerName = $name; ConnectionHost = $connectionHost; NameSource = $source }
}

function Get-WinRMConnectAs {
    param([pscredential]$Credential)
    if ($null -ne $Credential) { return $Credential.UserName }
    try { return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name }
    catch { return [Environment]::UserName }
}

function Resolve-WinRMTargetConnection {
    param(
        [Parameter(Mandatory)]$Target,
        [int]$TimeoutMs = 1000,
        [switch]$SkipDns
    )

    if ($SkipDns) { return [pscustomobject]@{ ConnectionHost = $Target.Address } }

    $verifiedHost = if (@($Target.PSObject.Properties.Match('VerifiedConnectionHost')).Count -gt 0) {
        [string]$Target.VerifiedConnectionHost
    }
    else { '' }
    if (-not [string]::IsNullOrWhiteSpace($verifiedHost)) {
        try {
            $forward = [Net.Dns]::GetHostAddressesAsync($verifiedHost)
            if ($forward.Wait($TimeoutMs) -and
                [string]$Target.Address -in @($forward.Result | ForEach-Object { $_.IPAddressToString })) {
                return [pscustomobject]@{ ConnectionHost = $verifiedHost }
            }
        }
        catch { Write-Verbose "Forward verification for ${verifiedHost}: $($_.Exception.Message)" }
    }

    Resolve-WinRMComputerName -Address $Target.Address -TimeoutMs $TimeoutMs
}

function Get-WinRMErrorStatus {
    param([System.Management.Automation.ErrorRecord]$Record)
    $description = $Record.ToString() + ' ' + $Record.FullyQualifiedErrorId
    if ($Record.CategoryInfo.Category -eq 'PermissionDenied' -or
        $description -match '(?i)AccessDenied|access is denied|access denied|отказано в доступе|0x80070005') {
        return 'AccessDenied'
    }
    if ($description -match '(?i)certificate|сертификат|0x80072f8f|0x80338115') { return 'CertificateError' }
    if ($description -match '(?i)timed?\s*out|timeout|время ожидания|времени ожидания|0x80338029') { return 'Timeout' }
    if ($description -match '(?i)TrustedHosts|Kerberos|кeрберос|0x8009030e') { return 'AuthenticationError' }
    return 'ConnectionFailed'
}

function New-WinRMTargetSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Target,
        [pscredential]$Credential,
        [ValidateSet('Default', 'Negotiate', 'Kerberos')][string]$Authentication = 'Default',
        [int]$OpenTimeoutMs = 5000,
        [switch]$SkipDns
    )

    $resolved = Resolve-WinRMTargetConnection -Target $Target -TimeoutMs $OpenTimeoutMs -SkipDns:$SkipDns
    $options = New-PSSessionOption -OpenTimeout $OpenTimeoutMs -OperationTimeout 20000 -CancelTimeout 1000
    $parameters = @{
        ComputerName = $resolved.ConnectionHost
        Port = [int]$Target.Port
        UseSSL = ($Target.Transport -eq 'HTTPS')
        Authentication = $Authentication
        SessionOption = $options
        ErrorAction = 'Stop'
    }
    if ($null -ne $Credential) { $parameters.Credential = $Credential }
    New-PSSession @parameters
}

function Invoke-WinRMRemoteJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [int]$TimeoutSec = 60
    )
    $job = $null
    try {
        $job = Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -AsJob -ErrorAction Stop
        if ($null -eq (Wait-Job -Job $job -Timeout $TimeoutSec -ErrorAction Stop)) {
            throw [TimeoutException]::new("Remote command timeout after $TimeoutSec seconds. Side effects may already have occurred; do not automatically retry.")
        }
        $output = @(Receive-Job -Job $job -ErrorAction Stop)
        if ($job.State -ne 'Completed') {
            $reason = @($job.ChildJobs | ForEach-Object { $_.JobStateInfo.Reason } | Where-Object { $null -ne $_ })
            throw "Remote job ended in state $($job.State): $($reason -join '; ')"
        }
        $output
    }
    finally {
        if ($null -ne $job) {
            if ($job.State -in @('Running', 'NotStarted', 'Blocked', 'Disconnected')) {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
            }
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-WinRMTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Target,
        [ValidateSet('Inventory', 'Command', 'Restart', 'Shutdown')][string]$Action = 'Inventory',
        [pscredential]$Credential,
        [ValidateSet('Default', 'Negotiate', 'Kerberos')][string]$Authentication = 'Default',
        [int]$OpenTimeoutMs = 5000,
        [int]$CommandTimeoutSec = 60,
        [string]$CommandText,
        [object[]]$ArgumentList = @(),
        [int]$DelaySeconds = 60,
        [switch]$SkipDns
    )
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $result = [ordered]@{}
    foreach ($property in $Target.PSObject.Properties) { $result[$property.Name] = $property.Value }
    $result['ConnectAs'] = Get-WinRMConnectAs $Credential
    $result['AuthenticatedAs'] = $null
    $result['ConnectionStatus'] = 'NotTested'
    $result['Action'] = $Action
    $result['Status'] = 'ConnectionFailed'
    $result['Detail'] = $null
    $result['Output'] = @()
    $result['CheckedAt'] = [DateTime]::UtcNow.ToString('o')
    if ($Action -eq 'Inventory') {
        foreach ($field in @('OS', 'OSVersion', 'LastBootTime', 'UptimeDays', 'FreeSpaceGB', 'LoggedOnUser')) {
            $result[$field] = $null
        }
    }
    $session = $null
    $phase = 'Connect'
    try {
        # Resolve again when using saved inventory; never trust a cached DNS name
        # or a ConnectionHost supplied by an imported CSV for routing credentials.
        $resolved = Resolve-WinRMTargetConnection -Target $Target -TimeoutMs $OpenTimeoutMs -SkipDns:$SkipDns
        $result['ConnectionHost'] = $resolved.ConnectionHost
        $options = New-PSSessionOption -OpenTimeout $OpenTimeoutMs -OperationTimeout 20000 -CancelTimeout 1000
        $parameters = @{
            ComputerName = $resolved.ConnectionHost
            Port = [int]$Target.Port
            UseSSL = ($Target.Transport -eq 'HTTPS')
            Authentication = $Authentication
            SessionOption = $options
            ErrorAction = 'Stop'
        }
        if ($null -ne $Credential) { $parameters.Credential = $Credential }
        $session = New-PSSession @parameters
        $result['ConnectionStatus'] = 'Connected'
        $phase = 'Identify'
        $identity = @(Invoke-WinRMRemoteJob -Session $session -TimeoutSec $CommandTimeoutSec -ScriptBlock {
            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                AuthenticatedAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            }
        })
        if ($identity.Count -ne 1) { throw 'The remote endpoint did not return a unique computer identity.' }
        $result['ComputerName'] = $identity[0].ComputerName
        $result['NameSource'] = 'Remote'
        $result['AuthenticatedAs'] = $identity[0].AuthenticatedAs
        $phase = $Action
        if ($Action -eq 'Inventory') {
            $inventory = @(Invoke-WinRMRemoteJob -Session $session -TimeoutSec $CommandTimeoutSec -ScriptBlock {
                $ErrorActionPreference = 'Stop'
                $os = Get-CimInstance Win32_OperatingSystem
                $computer = Get-CimInstance Win32_ComputerSystem
                $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
                [pscustomobject]@{
                    OS = $os.Caption
                    OSVersion = $os.Version
                    LastBootTime = $os.LastBootUpTime.ToUniversalTime().ToString('o')
                    UptimeDays = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 2)
                    FreeSpaceGB = if ($null -ne $disk) { [math]::Round($disk.FreeSpace / 1GB, 2) } else { $null }
                    LoggedOnUser = $computer.UserName
                }
            })
            if ($inventory.Count -ne 1) { throw 'The endpoint did not return a unique inventory record.' }
            foreach ($field in @('OS', 'OSVersion', 'LastBootTime', 'UptimeDays', 'FreeSpaceGB', 'LoggedOnUser')) {
                $result[$field] = $inventory[0].$field
            }
            $result['Status'] = 'Connected'
        }
        elseif ($Action -eq 'Command') {
            if ([string]::IsNullOrWhiteSpace($CommandText)) { throw 'CommandText must not be empty.' }
            $result['Output'] = @(Invoke-WinRMRemoteJob -Session $session -TimeoutSec $CommandTimeoutSec `
                -ScriptBlock ([scriptblock]::Create($CommandText)) -ArgumentList $ArgumentList)
            $result['Status'] = 'Succeeded'
        }
        else {
            $result['Output'] = @(Invoke-WinRMRemoteJob -Session $session -TimeoutSec $CommandTimeoutSec -ArgumentList @($Action, $DelaySeconds) -ScriptBlock {
                param($RequestedAction, $Delay)
                $flag = if ($RequestedAction -eq 'Restart') { '/r' } else { '/s' }
                # Delay allows WinRM to acknowledge scheduling before shutdown.
                $message = & "$env:SystemRoot\System32\shutdown.exe" $flag /t $Delay /d 'p:0:0' 2>&1
                if ($LASTEXITCODE -ne 0) { throw "shutdown.exe failed ($LASTEXITCODE): $message" }
                "Scheduled $RequestedAction in $Delay seconds."
            })
            $result['Status'] = 'Scheduled'
        }
    }
    catch {
        $result['Detail'] = $_.ToString()
        if ($phase -eq 'Connect') {
            $result['Status'] = Get-WinRMErrorStatus $_
            $result['ConnectionStatus'] = $result['Status']
        }
        elseif ($_.Exception -is [TimeoutException]) { $result['Status'] = 'Timeout' }
        elseif ($phase -eq 'Inventory') { $result['Status'] = 'InventoryFailed' }
        else { $result['Status'] = 'Failed' }
        $result['Detail'] = "${phase}: $($result['Detail'])"
    }
    finally {
        if ($null -ne $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    }
    $result['DurationMs'] = $timer.ElapsedMilliseconds
    [pscustomobject]$result
}

function Invoke-WinRMBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Target,
        [Parameter(Mandatory)][hashtable]$Options,
        [ValidateRange(1, 128)][int]$ThrottleLimit = 16
    )
    $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $state.ImportPSModule(@($PSCommandPath))
    $pool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit, $state, $Host)
    $active = [System.Collections.Generic.List[object]]::new()
    $next = 0
    try {
        $pool.Open()
        while ($next -lt $Target.Count -or $active.Count -gt 0) {
            while ($next -lt $Target.Count -and $active.Count -lt $ThrottleLimit) {
                $ps = [powershell]::Create()
                try {
                    $ps.RunspacePool = $pool
                    $null = $ps.AddCommand('Invoke-WinRMTarget').AddParameter('Target', $Target[$next]).AddParameters($Options)
                    $active.Add([pscustomobject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Target = $Target[$next] })
                }
                catch { $ps.Dispose(); throw }
                $next++
            }
            for ($i = $active.Count - 1; $i -ge 0; $i--) {
                $worker = $active[$i]
                if (-not $worker.Handle.IsCompleted) { continue }
                try {
                    $records = @($worker.PowerShell.EndInvoke($worker.Handle))
                    if ($records.Count -ne 1) { throw "Worker returned $($records.Count) records: $($worker.PowerShell.Streams.Error)" }
                    $records[0]
                }
                catch {
                    [pscustomobject]@{
                        Address = $worker.Target.Address; Port = $worker.Target.Port
                        ComputerName = $worker.Target.ComputerName; Action = $Options.Action
                        Status = 'WorkerFailed'; Detail = $_.ToString(); CheckedAt = [DateTime]::UtcNow.ToString('o')
                    }
                }
                finally { $worker.PowerShell.Dispose(); $active.RemoveAt($i) }
            }
            if ($active.Count -gt 0) { Start-Sleep -Milliseconds 25 }
        }
    }
    finally {
        foreach ($worker in $active) { $worker.PowerShell.Stop(); $worker.PowerShell.Dispose() }
        $pool.Dispose()
    }
}

function Invoke-WinRMFileTransferTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][ValidateSet('Upload', 'Download')][string]$Direction,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [pscredential]$Credential,
        [ValidateSet('Default', 'Negotiate', 'Kerberos')][string]$Authentication = 'Default',
        [int]$OpenTimeoutMs = 5000,
        [switch]$SkipDns,
        [switch]$Recurse
    )

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $session = $null
    $result = [ordered]@{
        Address = $Target.Address
        ComputerName = $Target.ComputerName
        Action = $Direction
        Source = $Source
        Destination = $Destination
        ConnectAs = Get-WinRMConnectAs $Credential
        Status = 'ConnectionFailed'
        Detail = $null
        CheckedAt = [DateTime]::UtcNow.ToString('o')
    }
    try {
        if ($Direction -eq 'Upload' -and -not (Test-Path -LiteralPath $Source)) {
            throw [IO.FileNotFoundException]::new("Local source not found: $Source")
        }
        if ($Direction -eq 'Download') {
            $localParent = if ([IO.Path]::HasExtension($Destination)) { [IO.Path]::GetDirectoryName($Destination) } else { $Destination }
            if (-not [string]::IsNullOrWhiteSpace($localParent)) { $null = [IO.Directory]::CreateDirectory($localParent) }
        }
        $session = New-WinRMTargetSession -Target $Target -Credential $Credential -Authentication $Authentication -OpenTimeoutMs $OpenTimeoutMs -SkipDns:$SkipDns
        if ($Direction -eq 'Upload') {
            Copy-Item -LiteralPath $Source -Destination $Destination -ToSession $session -Recurse:$Recurse -Force -ErrorAction Stop
        }
        else {
            Copy-Item -Path $Source -Destination $Destination -FromSession $session -Recurse:$Recurse -Force -ErrorAction Stop
        }
        $result.Status = 'Succeeded'
    }
    catch {
        $result.Detail = $_.ToString()
        $result.Status = if ($null -eq $session) { Get-WinRMErrorStatus $_ } else { 'Failed' }
    }
    finally {
        if ($null -ne $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
        $result.DurationMs = $timer.ElapsedMilliseconds
    }
    [pscustomobject]$result
}

function Invoke-WinRMFileTransferBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Target,
        [Parameter(Mandatory)][hashtable]$Options,
        [ValidateRange(1, 128)][int]$ThrottleLimit = 8
    )

    $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $state.ImportPSModule(@($PSCommandPath))
    $pool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit, $state, $Host)
    $active = [System.Collections.Generic.List[object]]::new()
    $next = 0
    try {
        $pool.Open()
        while ($next -lt $Target.Count -or $active.Count -gt 0) {
            while ($next -lt $Target.Count -and $active.Count -lt $ThrottleLimit) {
                $ps = [powershell]::Create()
                try {
                    $ps.RunspacePool = $pool
                    $workerOptions = @{} + $Options
                    if ($Options.Direction -eq 'Download') {
                        $safeName = ([string]$Target[$next].ComputerName -replace '[^a-zA-Z0-9._-]', '_')
                        $workerOptions.Destination = Join-Path $Options.Destination $safeName
                        $null = [IO.Directory]::CreateDirectory($workerOptions.Destination)
                    }
                    $null = $ps.AddCommand('Invoke-WinRMFileTransferTarget').AddParameter('Target', $Target[$next]).AddParameters($workerOptions)
                    $active.Add([pscustomobject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Target = $Target[$next] })
                }
                catch { $ps.Dispose(); throw }
                $next++
            }
            for ($i = $active.Count - 1; $i -ge 0; $i--) {
                $worker = $active[$i]
                if (-not $worker.Handle.IsCompleted) { continue }
                try {
                    $records = @($worker.PowerShell.EndInvoke($worker.Handle))
                    if ($records.Count -ne 1) { throw "Worker returned $($records.Count) records: $($worker.PowerShell.Streams.Error)" }
                    $records[0]
                }
                catch {
                    [pscustomobject]@{ Address = $worker.Target.Address; ComputerName = $worker.Target.ComputerName; Action = $Options.Direction; Status = 'WorkerFailed'; Detail = $_.ToString(); CheckedAt = [DateTime]::UtcNow.ToString('o') }
                }
                finally { $worker.PowerShell.Dispose(); $active.RemoveAt($i) }
            }
            if ($active.Count -gt 0) { Start-Sleep -Milliseconds 25 }
        }
    }
    finally {
        foreach ($worker in $active) { $worker.PowerShell.Stop(); $worker.PowerShell.Dispose() }
        $pool.Dispose()
    }
}

Export-ModuleMember -Function Resolve-WinRMComputerName, Get-WinRMConnectAs, New-WinRMTargetSession, Invoke-WinRMTarget, Invoke-WinRMBatch, Invoke-WinRMFileTransferTarget, Invoke-WinRMFileTransferBatch
