#Requires -Version 5.1
# Self-contained regression checks. Network traffic is limited to loopback.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$modulePath = Join-Path $root 'WinRM\WinRM.Tools.psm1'
$scanner = Join-Path $root 'WinRM\Find-WinRM.ps1'
$manager = Join-Path $root 'Invoke-OfficeComputer.ps1'
function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Assert-Throws([scriptblock]$Operation, [string]$Message) {
    $caught = $false
    try { & $Operation | Out-Null } catch { $caught = $true }
    Assert-True $caught $Message
}
foreach ($file in @($scanner, $manager, $modulePath)) {
    $parseErrors = $null
    $tokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) "Parse $file : $parseErrors"
}

# Exercise range expansion without contacting the resulting addresses.
$source = Get-Content -LiteralPath $scanner -Raw
$rangeText = $source.Substring($source.IndexOf('function ConvertTo-IPv4Number'),
    $source.IndexOf('$probe = {') - $source.IndexOf('function ConvertTo-IPv4Number'))
$rangeOnly = [scriptblock]::Create('param($IpMask, $MaxAddresses = 65536)' + "`n" + $rangeText + "`n" + '$addresses.ToArray()')
foreach ($case in @(
    @{ Mask = '192.168.1.*'; Count = 256; First = '192.168.1.0'; Last = '192.168.1.255' },
    @{ Mask = '192.168.1.123/24'; Count = 254; First = '192.168.1.1'; Last = '192.168.1.254' },
    @{ Mask = '10.0.0.3/31'; Count = 2; First = '10.0.0.2'; Last = '10.0.0.3' },
    @{ Mask = '255.255.255.255/32'; Count = 1; First = '255.255.255.255'; Last = '255.255.255.255' }
)) {
    $actual = @(& $rangeOnly $case.Mask)
    Assert-True ($actual.Count -eq $case.Count -and $actual[0] -eq $case.First -and $actual[-1] -eq $case.Last) "Range $($case.Mask)"
}
foreach ($mask in @('300.1.1.*', '10.0.0.0/33', '*.*.*.*', 'abc')) {
    Assert-Throws { & $rangeOnly $mask } "Reject range $mask"
}

$testDir = Join-Path ([IO.Path]::GetTempPath()) ('OfficeWinRM-tests-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($testDir)
try {
    # A bound, non-listening socket reserves a closed port for deterministic tests.
    $closed = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork,
        [Net.Sockets.SocketType]::Stream, [Net.Sockets.ProtocolType]::Tcp)
    $closed.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback, 0))
    $closedPort = $closed.LocalEndPoint.Port
    foreach ($kind in @('WSMan', 'Authentication', 'OtherHttp')) {
        $server = Start-Job -ArgumentList $kind -ScriptBlock {
            param($Kind)
            $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
            $listener.Start()
            $listener.LocalEndpoint.Port
            try {
                for ($i = 0; $i -lt 2; $i++) {
                    $client = $listener.AcceptTcpClient()
                    try {
                        $stream = $client.GetStream()
                        $stream.ReadTimeout = 5000
                        $buffer = New-Object byte[] 8192
                        $read = $stream.Read($buffer, 0, $buffer.Length)
                        if ($read -gt 0) {
                            $body = if ($Kind -eq 'WSMan') {
                                '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:i="http://schemas.dmtf.org/wbem/wsman/identity/1/wsmanidentity.xsd"><s:Body><i:IdentifyResponse/></s:Body></s:Envelope>'
                            } else { '<html>Not WSMan</html>' }
                            $code = if ($Kind -eq 'Authentication') { '401 Unauthorized' } else { '200 OK' }
                            $reply = "HTTP/1.1 $code`r`nContent-Type: application/soap+xml`r`nContent-Length: $([Text.Encoding]::UTF8.GetByteCount($body))`r`nConnection: close`r`n`r`n$body"
                            $bytes = [Text.Encoding]::UTF8.GetBytes($reply)
                            $stream.Write($bytes, 0, $bytes.Length)
                        }
                    }
                    finally { $client.Dispose() }
                }
            }
            finally { $listener.Stop() }
        }
        try {
            $port = $null
            for ($attempt = 0; $attempt -lt 150 -and $null -eq $port; $attempt++) {
                Start-Sleep -Milliseconds 100
                $port = Receive-Job $server
            }
            Assert-True ($null -ne $port) 'Fixture started'
            $csvPath = Join-Path $testDir "$kind.csv"
            $found = @(& $scanner '127.0.0.1/32' -HttpPort $port -HttpsPort $closedPort -SkipDns -SavePath $csvPath)
            $expected = switch ($kind) {
                'WSMan' { 'WSManConfirmed' }
                'Authentication' { 'AuthenticationRequired' }
                'OtherHttp' { 'TcpOpenUnverified' }
            }
            Assert-True ($found.Count -eq 1 -and $found[0].Status -eq $expected) "Discovery $kind : $($found | ConvertTo-Json -Compress)"
            Assert-True ($found[0].ConnectionStatus -eq 'NotTested' -and $found[0].ConnectAs) 'Discovery does not claim login'
            Assert-True (@(Import-Csv -LiteralPath $csvPath).Count -eq 1) 'CSV round trip'
        }
        finally { Stop-Job $server; Remove-Job $server -Force }
    }
    & $scanner '127.0.0.1' -HttpPort $closedPort -HttpsPort $closedPort -SavePath $csvPath | Out-Null
    Assert-True (@(Import-Csv -LiteralPath $csvPath).Count -eq 0) 'Empty scan replaces stale inventory'

    # No real remoting or power action is used in these worker tests.
    Import-Module $modulePath -Force
    $module = Get-Module WinRM.Tools
    & $module {
        function script:Resolve-WinRMComputerName { param($Address, $TimeoutMs) [pscustomobject]@{ConnectionHost = $Address} }
        function script:New-PSSessionOption { param($OpenTimeout, $OperationTimeout, $CancelTimeout) @{} }
        function script:New-PSSession {
            param($ComputerName, $Port, $UseSSL, $Authentication, $SessionOption, $ErrorAction, $Credential)
            if ($script:failure -eq 'Connect') { throw [UnauthorizedAccessException]::new('Access is denied') }
            'fake-session'
        }
        function script:Remove-PSSession { param($Session, $ErrorAction) $script:removed++ }
        function script:Invoke-WinRMRemoteJob {
            param($Session, $ScriptBlock, $ArgumentList, $TimeoutSec)
            $script:jobCalls++
            if ($script:jobCalls -eq 1) { return [pscustomobject]@{ComputerName = 'PC-REAL'; AuthenticatedAs = 'OFFICE\actual'} }
            if ($script:failure -eq 'Inventory') { throw 'CIM unavailable' }
            if ($script:failure -eq 'Timeout') { throw [TimeoutException]::new('timeout') }
            if ($script:action -eq 'Inventory') {
                return [pscustomobject]@{OS='Windows Test'; OSVersion='10.0'; LastBootTime='2026-01-01T00:00:00Z'; UptimeDays=2; FreeSpaceGB=42; LoggedOnUser='OFFICE\employee'}
            }
            if ($script:action -eq 'Command') { return $ArgumentList[0] }
            # Check only the script text; never execute shutdown.exe in tests.
            if ($ScriptBlock.ToString() -notmatch 'shutdown.exe' -or $ArgumentList[1] -ne 60) { throw 'Bad power command' }
            'Scheduled'
        }
    }
    $target = [pscustomobject]@{Address='127.0.0.1'; ComputerName='PC-OLD'; Port=$closedPort; Transport='HTTP'; OS='Stale OS'}
    $credential = [pscredential]::new('OFFICE\requested', (ConvertTo-SecureString 'fixture-only' -AsPlainText -Force))
    foreach ($case in @(
        @{ Action='Inventory'; Failure=''; Expected='Connected' },
        @{ Action='Inventory'; Failure='Connect'; Expected='AccessDenied' },
        @{ Action='Inventory'; Failure='Inventory'; Expected='InventoryFailed' },
        @{ Action='Command'; Failure=''; Expected='Succeeded' },
        @{ Action='Command'; Failure='Timeout'; Expected='Timeout' },
        @{ Action='Restart'; Failure=''; Expected='Scheduled' },
        @{ Action='Shutdown'; Failure=''; Expected='Scheduled' }
    )) {
        & $module { param($Case) $script:failure=$Case.Failure; $script:action=$Case.Action; $script:removed=0; $script:jobCalls=0 } $case
        $result = Invoke-WinRMTarget -Target $target -Action $case.Action -Credential $credential -CommandText 'param($Value) $Value' -ArgumentList @('hello')
        Assert-True ($result.Status -eq $case.Expected) "Worker $($case.Action)/$($case.Failure): $($result.Detail)"
        Assert-True ($result.ConnectAs -eq 'OFFICE\requested') 'Requested identity'
        if ($case.Failure -ne 'Connect') {
            Assert-True ($result.ComputerName -eq 'PC-REAL' -and $result.AuthenticatedAs -eq 'OFFICE\actual') 'Remote identity'
            Assert-True ((& $module { $script:removed }) -eq 1) 'Session cleaned up'
        }
        if ($case.Expected -eq 'InventoryFailed') { Assert-True ($null -eq $result.OS) 'No stale inventory after failure' }
        if ($case.Expected -eq 'Connected') { Assert-True ($result.FreeSpaceGB -eq 42 -and $result.LoggedOnUser -eq 'OFFICE\employee') 'Inventory fields' }
        if ($case.Expected -eq 'Succeeded') { Assert-True ($result.Output[0] -eq 'hello') 'Command arguments and output' }
    }
    Remove-Module WinRM.Tools
    Import-Module $modulePath -Force

    # Exercise command job failure/timeout cleanup with mocked job cmdlets.
    $module = Get-Module WinRM.Tools
    & $module {
        function script:Invoke-Command { param($Session, $ScriptBlock, $ArgumentList, [switch]$AsJob, $ErrorAction) [pscustomobject]@{State='Running'} }
        function script:Wait-Job { param($Job, $Timeout, $ErrorAction) $null }
        function script:Stop-Job { param($Job, $ErrorAction) $script:stopped=$true }
        function script:Remove-Job { param($Job, [switch]$Force, $ErrorAction) $script:deleted=$true }
        $script:stopped=$false; $script:deleted=$false
    }
    Assert-Throws { & $module { Invoke-WinRMRemoteJob -Session 'fake' -ScriptBlock { 1 } -TimeoutSec 1 } } 'Command timeout throws'
    Assert-True ((& $module { $script:stopped -and $script:deleted })) 'Timed-out job stopped and removed'
    Remove-Module WinRM.Tools
    Import-Module $modulePath -Force

    $targets = @(
        [pscustomobject]@{Address='127.0.0.1'; ComputerName='PC01'; Port=$closedPort; Transport='HTTP'},
        [pscustomobject]@{Address='127.0.0.1'; ComputerName='PC01'; Port=$closedPort; Transport='HTTPS'}
    )
    $inventoryPath = Join-Path $testDir 'inventory.csv'
    $logPath = Join-Path $testDir 'audit.jsonl'
    $targets | Export-Csv -LiteralPath $inventoryPath -NoTypeInformation
    Assert-Throws { & $manager -InventoryPath $inventoryPath } 'Saved inventory requires explicit selection'
    Assert-Throws { & $manager -InventoryPath $inventoryPath -ComputerName Missing -WhatIf } 'Unknown target rejected'
    Assert-Throws { $targets | & $manager -Action Command } 'Command requires script block'
    foreach ($action in @('Inventory', 'Command', 'Restart', 'Shutdown')) {
        $options = @{Action=$action; WhatIf=$true; LogPath=$logPath}
        if ($action -eq 'Command') { $options.ScriptBlock = { throw 'Must not execute' } }
        $targets | & $manager @options
    }
    Assert-True (-not (Test-Path -LiteralPath $logPath)) 'WhatIf creates no audit file or remote work'
    # Confirmation cannot silently disappear in unattended power-action runs.
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach ($action in @('Restart', 'Shutdown')) {
        $command = "& '" + $manager.Replace("'", "''") + "' -InventoryPath '" +
            $inventoryPath.Replace("'", "''") + "' -All -Action $action -LogPath '" +
            $logPath.Replace("'", "''") + "' -Confirm:`$false"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $windowsPowerShell
        $start.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $process = [Diagnostics.Process]::Start($start)
        try {
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            Assert-True ($process.ExitCode -ne 0 -and ($stdout + $stderr) -match 'ShouldContinue') 'Power action requires confirmation'
            Assert-True (-not (Test-Path -LiteralPath $logPath)) 'Unconfirmed action starts no run'
        }
        finally { $process.Dispose() }
    }
    $results = @(& $manager -InventoryPath $inventoryPath -ComputerName PC01 -Action Inventory -SkipDns -OpenTimeoutMs 100 -LogPath $logPath)
    Assert-True ($results.Count -eq 1) 'HTTP/HTTPS deduplicated'
    Assert-True ($results[0].Status -ne 'WorkerFailed' -and $results[0].ConnectionStatus -ne 'NotTested') 'Runspace worker reports connection failure'
    $events = @(Get-Content -LiteralPath $logPath | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-True ($events.Count -eq 3 -and $events[0].Event -eq 'RunStarted' -and $events[1].Event -eq 'Result' -and $events[2].Event -eq 'RunEnded') 'Per-host audit and run lifecycle'
    'PASS: ranges, discovery fixtures, CSV, identities, inventory, commands, errors, cleanup, selection, deduplication, WhatIf, audit.'
}
finally {
    if ($null -ne (Get-Variable closed -ErrorAction SilentlyContinue)) { $closed.Dispose() }
    # Delete only the flat fixture files created in this unique temporary folder.
    Get-ChildItem -LiteralPath $testDir -File | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
    Remove-Item -LiteralPath $testDir
    Remove-Module WinRM.Tools -ErrorAction SilentlyContinue
}
