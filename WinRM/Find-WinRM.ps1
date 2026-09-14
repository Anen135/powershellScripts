#Requires -Version 5.1
<#
.SYNOPSIS
    Finds reachable WinRM endpoints in an IPv4 range.
.DESCRIPTION
    Accepts IPv4, CIDR, or whole-octet wildcards. Checks TCP, then sends an
    anonymous WS-Management Identify request to /wsman. Resolves DNS names.
    With -CheckConnection, opens a PSSession and collects inventory.
    Does not change TrustedHosts. HTTPS certificate validation remains enabled.
    WSManConfirmed identifies WS-Management, not permission to open a session.
    AuthenticationRequired and TcpOpenUnverified are candidates only.
    CIDR excludes network/broadcast addresses except for /31 and /32.
    Wildcards include every matching address. No ICMP/ping dependency.
.EXAMPLE
    .\Find-WinRM.ps1 -IpMask '192.168.1.*' | Format-Table -AutoSize
.EXAMPLE
    .\Find-WinRM.ps1 '10.10.0.0/24' -TimeoutMs 1500 -ThrottleLimit 32 |
        Export-Csv .\winrm.csv -NoTypeInformation -Encoding UTF8
.EXAMPLE
    .\Find-WinRM.ps1 '192.168.1.10' -HttpPort 8080 -HttpsPort 8443
.EXAMPLE
    .\Find-WinRM.ps1 '192.168.1.*' -CheckConnection -Credential (Get-Credential) -SavePath .\office.csv
.NOTES
    Default ports: https://learn.microsoft.com/windows/win32/winrm/installation-and-configuration-for-windows-remote-management
    TimeoutMs applies separately to TCP connect and HTTP operations.
    Unreachable/closed ports are omitted; use -Verbose for their diagnostics.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [Alias('Subnet')]
    [string]$IpMask,
    [ValidateRange(1, 65535)] [int]$HttpPort = 5985,
    [ValidateRange(1, 65535)] [int]$HttpsPort = 5986,
    [ValidateRange(100, 60000)] [int]$TimeoutMs = 1000,
    [ValidateRange(1, 128)] [int]$ThrottleLimit = 32,
    [ValidateRange(1, 16777216)] [int]$MaxAddresses = 65536,
    [switch]$CheckConnection,
    [pscredential]$Credential,
    [ValidateSet('Default', 'Negotiate', 'Kerberos')] [string]$Authentication = 'Default',
    [ValidateRange(100, 60000)] [int]$OpenTimeoutMs = 5000,
    [ValidateRange(1, 86400)] [int]$CommandTimeoutSec = 60,
    [switch]$SkipDns,
    [string]$SavePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WinRM.Tools.psm1') -ErrorAction Stop
if ($null -ne $Credential -and -not $CheckConnection) {
    throw 'Use -CheckConnection with -Credential to test login; discovery does not authenticate.'
}

function ConvertTo-IPv4Number([string]$Address) {
    $parts = $Address.Split('.')
    if ($parts.Count -ne 4) { throw "Invalid IPv4 address: $Address" }
    [long]$number = 0
    foreach ($part in $parts) {
        if ($part -notmatch '^\d{1,3}$' -or [int]$part -gt 255) {
            throw "Invalid IPv4 address: $Address"
        }
        $number = $number * 256 + [int]$part
    }
    return $number
}

# Validate size before expanding the range or making any connections.
$IpMask = $IpMask.Trim()
$addresses = [System.Collections.Generic.List[string]]::new()
if ($IpMask.Contains('/')) {
    $parts = $IpMask.Split('/')
    if ($parts.Count -ne 2 -or $parts[1] -notmatch '^\d{1,2}$' -or [int]$parts[1] -gt 32) {
        throw "Invalid CIDR: $IpMask"
    }
    $number = ConvertTo-IPv4Number $parts[0]
    [long]$size = [math]::Pow(2, 32 - [int]$parts[1])
    [long]$first = [long][math]::Floor($number / $size) * $size
    [long]$last = $first + $size - 1
    if ([int]$parts[1] -lt 31) { $first++; $last-- }
    if ($last - $first + 1 -gt $MaxAddresses) { throw 'Range exceeds MaxAddresses.' }
    for ($n = $first; $n -le $last; $n++) {
        $addresses.Add(('{0}.{1}.{2}.{3}' -f (($n -shr 24) -band 255),
            (($n -shr 16) -band 255), (($n -shr 8) -band 255), ($n -band 255)))
    }
}
else {
    $parts = $IpMask.Split('.')
    if ($parts.Count -ne 4) { throw "Expected IPv4, CIDR or wildcard mask: $IpMask" }
    [long]$count = 1
    foreach ($part in $parts) {
        if ($part -eq '*') { $count *= 256 }
        elseif ($part -notmatch '^\d{1,3}$' -or [int]$part -gt 255) { throw "Invalid mask: $IpMask" }
    }
    if ($count -gt $MaxAddresses) { throw 'Range exceeds MaxAddresses.' }
    $prefixes = @('')
    foreach ($part in $parts) {
        $values = if ($part -eq '*') { 0..255 } else { @([int]$part) }
        $prefixes = @(foreach ($prefix in $prefixes) {
            foreach ($value in $values) {
                if ($prefix -eq '') { "$value" } else { "$prefix.$value" }
            }
        })
    }
    foreach ($address in $prefixes) { $addresses.Add($address) }
}

$probe = {
    param($Address, $Port, $Scheme, $Timeout)
    $ErrorActionPreference = 'Stop'
    $tcp = [System.Net.Sockets.TcpClient]::new()
    $pending = $null
    try {
        $pending = $tcp.BeginConnect($Address, $Port, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne($Timeout)) { throw 'TCP timeout' }
        $tcp.EndConnect($pending)
    }
    catch {
        return [pscustomobject]@{ Reachable = $false; Address = $Address; Port = $Port; Detail = $_.Exception.Message }
    }
    finally {
        $tcp.Close()
        if ($null -ne $pending) { $pending.AsyncWaitHandle.Close() }
    }

    $uri = '{0}://{1}:{2}/wsman' -f $Scheme, $Address, $Port
    $status = 'TcpOpenUnverified'
    $detail = $null
    $response = $null
    $request = $null
    $reader = $null
    try {
        $request = [System.Net.HttpWebRequest]::Create($uri)
        $request.Proxy = $null
        $request.Method = 'POST'
        $request.AllowAutoRedirect = $false
        $request.KeepAlive = $false
        $request.Timeout = $Timeout
        $request.ReadWriteTimeout = $Timeout
        $request.ContentType = 'application/soap+xml;charset=UTF-8'
        $body = '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:i="http://schemas.dmtf.org/wbem/wsman/identity/1/wsmanidentity.xsd"><s:Header/><s:Body><i:Identify/></s:Body></s:Envelope>'
        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
        $request.ContentLength = $bytes.Length
        $stream = $request.GetRequestStream()
        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
        $response = $request.GetResponse()
        $settings = [System.Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $settings.MaxCharactersInDocument = 65536
        $reader = [System.Xml.XmlReader]::Create($response.GetResponseStream(), $settings)
        $document = [System.Xml.XmlDocument]::new()
        $document.XmlResolver = $null
        $document.Load($reader)
        $ns = [System.Xml.XmlNamespaceManager]::new($document.NameTable)
        $ns.AddNamespace('s', 'http://www.w3.org/2003/05/soap-envelope')
        $ns.AddNamespace('i', 'http://schemas.dmtf.org/wbem/wsman/identity/1/wsmanidentity.xsd')
        if ($null -ne $document.SelectSingleNode('/s:Envelope/s:Body/i:IdentifyResponse', $ns)) {
            $status = 'WSManConfirmed'
        }
        else { $detail = 'Response did not contain a WS-Management IdentifyResponse.' }
    }
    catch {
        $detail = $_.Exception.Message
        $exception = $_.Exception
        while ($null -ne $exception.InnerException -and $exception -isnot [System.Net.WebException]) {
            $exception = $exception.InnerException
        }
        if ($exception -is [System.Net.WebException] -and $null -ne $exception.Response) {
            $response = $exception.Response
            if ([int]$response.StatusCode -eq 401) { $status = 'AuthenticationRequired' }
        }
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $response) { $response.Close() }
        if ($null -ne $request) { $request.Abort() }
    }
    [pscustomobject]@{
        Reachable = $true; Address = $Address; Port = $Port
        Transport = $Scheme.ToUpperInvariant(); Endpoint = $uri
        Status = $status; Detail = $detail
    }
}

$enrichProbe = {
    param($ProbeText, $Address, $Port, $Scheme, $Timeout, $CheckConnection, $Credential,
        $Authentication, $OpenTimeoutMs, $CommandTimeoutSec, $SkipDns)
    $result = & ([scriptblock]::Create($ProbeText)) $Address $Port $Scheme $Timeout
    if (-not $result.Reachable) { return $result }
    $resolved = if ($SkipDns) {
        [pscustomobject]@{ ComputerName = $Address; ConnectionHost = $Address; NameSource = 'Address' }
    }
    else { Resolve-WinRMComputerName -Address $Address -TimeoutMs $Timeout }
    $record = [pscustomobject][ordered]@{
        Reachable = $true; Address = $Address; ComputerName = $resolved.ComputerName
        ConnectionHost = $resolved.ConnectionHost; NameSource = $resolved.NameSource
        Port = $Port; Transport = $result.Transport; Endpoint = $result.Endpoint
        ConnectAs = Get-WinRMConnectAs $Credential; AuthenticatedAs = $null; LoggedOnUser = $null
        DiscoveryStatus = $result.Status; ConnectionStatus = 'NotTested'
        Status = $result.Status; Detail = $result.Detail
        OS = $null; OSVersion = $null; LastBootTime = $null; UptimeDays = $null; FreeSpaceGB = $null
        CheckedAt = [DateTime]::UtcNow.ToString('o')
    }
    if ($CheckConnection) {
        Invoke-WinRMTarget -Target $record -Credential $Credential -Authentication $Authentication `
            -OpenTimeoutMs $OpenTimeoutMs -CommandTimeoutSec $CommandTimeoutSec -SkipDns:$SkipDns
    }
    else { $record }
}

$state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$state.ImportPSModule(@((Join-Path $PSScriptRoot 'WinRM.Tools.psm1')))
$pool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit, $state, $Host)
$active = [System.Collections.Generic.List[object]]::new()
$savedResults = [System.Collections.Generic.List[object]]::new()
$total = $addresses.Count * 2
$next = 0
$completed = 0
try {
    $pool.Open()
    while ($next -lt $total -or $active.Count -gt 0) {
        while ($next -lt $total -and $active.Count -lt $ThrottleLimit) {
            $address = $addresses[[int][math]::Floor($next / 2)]
            $scheme = if ($next % 2 -eq 0) { 'http' } else { 'https' }
            $port = if ($scheme -eq 'http') { $HttpPort } else { $HttpsPort }
            $ps = [powershell]::Create()
            try {
                $ps.RunspacePool = $pool
                $null = $ps.AddScript($enrichProbe.ToString()).AddArgument($probe.ToString()).AddArgument($address).AddArgument($port).AddArgument($scheme).AddArgument($TimeoutMs).AddArgument([bool]$CheckConnection).AddArgument($Credential).AddArgument($Authentication).AddArgument($OpenTimeoutMs).AddArgument($CommandTimeoutSec).AddArgument([bool]$SkipDns)
                $active.Add([pscustomobject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke() })
            }
            catch { $ps.Dispose(); throw }
            $next++
        }
        for ($i = $active.Count - 1; $i -ge 0; $i--) {
            $job = $active[$i]
            if (-not $job.Handle.IsCompleted) { continue }
            foreach ($result in $job.PowerShell.EndInvoke($job.Handle)) {
                if ($result.Reachable) {
                    $record = $result | Select-Object Address, ComputerName, ConnectionHost, NameSource, Port, Transport, Endpoint, ConnectAs, AuthenticatedAs, LoggedOnUser, DiscoveryStatus, ConnectionStatus, Status, Detail, OS, OSVersion, LastBootTime, UptimeDays, FreeSpaceGB, CheckedAt
                    if ($SavePath) { $savedResults.Add($record) }
                    $record
                }
                else { Write-Verbose ('{0}:{1}: {2}' -f $result.Address, $result.Port, $result.Detail) }
            }
            foreach ($probeError in $job.PowerShell.Streams.Error) { Write-Warning $probeError.ToString() }
            $job.PowerShell.Dispose()
            $active.RemoveAt($i)
            $completed++
        }
        Write-Progress -Activity 'Scanning WinRM endpoints' -Status "$completed / $total" -PercentComplete (100 * $completed / $total)
        if ($active.Count -gt 0) { Start-Sleep -Milliseconds 25 }
    }
}
finally {
    foreach ($job in $active) {
        $job.PowerShell.Stop()
        $job.PowerShell.Dispose()
    }
    $pool.Dispose()
    Write-Progress -Activity 'Scanning WinRM endpoints' -Completed
}
if ($SavePath) {
    if ($savedResults.Count -gt 0) {
        $savedResults | Export-Csv -LiteralPath $SavePath -NoTypeInformation -Encoding UTF8
    }
    else {
        # Overwrite a stale inventory even when this scan found no endpoints.
        '"Address","ComputerName","ConnectionHost","NameSource","Port","Transport","Endpoint","ConnectAs","AuthenticatedAs","LoggedOnUser","DiscoveryStatus","ConnectionStatus","Status","Detail","OS","OSVersion","LastBootTime","UptimeDays","FreeSpaceGB","CheckedAt"' |
            Set-Content -LiteralPath $SavePath -Encoding UTF8
    }
}
