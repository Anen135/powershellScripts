#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$managerPath = Join-Path $root 'WinRM.Manager.psd1'
$toolsPath = Join-Path $root 'WinRM.Tools.psm1'
$tuiPath = Join-Path $root 'Start-WinRMTui.ps1'

function Assert-True {
    param($Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

foreach ($file in @($managerPath, (Join-Path $root 'WinRM.Manager.psm1'), $toolsPath, $tuiPath)) {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) "Parse $file : $errors"
}
$tuiSource = Get-Content -LiteralPath $tuiPath -Raw
Assert-True ($tuiSource -notmatch '(?m)^\s*Enter-PSSession\b') 'TUI does not invoke Enter-PSSession from script scope'
Assert-True ($tuiSource -match 'function Invoke-TuiRemoteCommandShell') 'Persistent remote command shell is present'
Assert-True ($tuiSource -match 'Out-String -Stream -Width') 'Remote command output is formatted before serialization'
Assert-True ($tuiSource -match 'OEMCodePage') 'Remote native command encoding is initialized'
Assert-True ($tuiSource -match '\$qualifiedUser = "\$computerQualifier\\\$login"') 'Single-host login is qualified with the computed computer name'
Assert-True ($tuiSource -notmatch 'Get-TuiConfiguredUser|EditDefault') 'Saved default credential workflow is absent'
Assert-True ($tuiSource -match "'NAME', 'ADDRESS'") 'Host table displays computer name and address columns'

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('WinRMTui-tests-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($testRoot)
try {
    Import-Module $managerPath -Force
    Assert-True ((ConvertTo-WinRMDiscoveryPattern '10.121.1.10/16') -eq '10.121.1.*') 'VPN profile becomes local /24 wildcard'
    Assert-True ((ConvertTo-WinRMDiscoveryPattern '172.23.0.1/20') -eq '172.23.0.*') 'Virtual switch profile becomes local /24 wildcard'
    Assert-True ((ConvertTo-WinRMDiscoveryPattern '192.168.3.20/24') -eq '192.168.3.*') 'Wireless profile becomes local /24 wildcard'
    Assert-True ((ConvertTo-WinRMDiscoveryPattern '192.168.*.*') -eq '192.168.*.*') 'Broader custom wildcard is preserved'
    $store = Initialize-WinRMStore -StorePath $testRoot
    Assert-True ((Test-Path $store.Config) -and (Test-Path $store.Inventory) -and (Test-Path $store.Scripts)) 'Store initialized'
    $config = Get-WinRMManagerConfig -StorePath $testRoot
    Assert-True ($config.SchemaVersion -eq 1 -and $config.Settings.ThrottleLimit -gt 0) 'Default config'
    $config.Settings | Add-Member -NotePropertyName DefaultUser -NotePropertyValue 'WORKGROUP\FixtureUser'
    $null = Save-WinRMManagerConfig -Config $config -StorePath $testRoot
    $config = Get-WinRMManagerConfig -StorePath $testRoot
    Assert-True (@($config.Settings.PSObject.Properties.Match('DefaultUser')).Count -eq 0) 'Legacy default credential user is removed'

    $discovery = @(
        [pscustomobject]@{ Address = '10.20.30.40'; ComputerName = 'PC40'; Port = 5985; Transport = 'HTTP'; Endpoint = 'http://10.20.30.40:5985/wsman'; DiscoveryStatus = 'WSManConfirmed'; ConnectionStatus = 'NotTested'; Status = 'WSManConfirmed'; Detail = $null },
        [pscustomobject]@{ Address = '10.20.30.40'; ComputerName = 'PC40'; Port = 5986; Transport = 'HTTPS'; Endpoint = 'https://10.20.30.40:5986/wsman'; DiscoveryStatus = 'AuthenticationRequired'; ConnectionStatus = 'NotTested'; Status = 'AuthenticationRequired'; Detail = $null },
        [pscustomobject]@{ Address = '10.20.30.99'; ComputerName = 'SKIP99'; Port = 5985; Transport = 'HTTP'; Endpoint = 'http://10.20.30.99:5985/wsman'; DiscoveryStatus = 'WSManConfirmed'; ConnectionStatus = 'NotTested'; Status = 'WSManConfirmed'; Detail = $null }
    )
    $config = Add-WinRMBlacklistEntry $config '10.20.30.99' 'fixture'
    $hosts = @(Merge-WinRMDiscoveryResult -Current @() -Discovery $discovery -Blacklist $config.Blacklist)
    Assert-True ($hosts.Count -eq 1 -and $hosts[0].Endpoints.Count -eq 2) 'Discovery merge and blacklist'
    Assert-True ((Select-WinRMPreferredEndpoint $hosts[0]).Port -eq 5985) 'Confirmed endpoint preferred'

    $null = Set-WinRMHostGroups $hosts[0] @('Office', 'Servers', 'Office')
    $null = Set-WinRMHostTags $hosts[0] @('prod', 'windows')
    $hosts[0].Status = 'Connected'; $hosts[0].ConnectionStatus = 'Connected'; $hosts[0].OS = 'Windows Server 2025'; $hosts[0].FreeSpaceGB = 8.5
    Assert-True (@(Find-WinRMInventory $hosts 'group:Office tag:prod status:Connected os:Server disk:<10' @()).Count -eq 1) 'Structured filters'
    Assert-True (@(Find-WinRMInventory $hosts '!tag:prod' @()).Count -eq 0) 'Negative filter'
    Assert-True (Test-WinRMBlacklist ([pscustomobject]@{ Address = '192.168.5.10'; ComputerName = 'PC' }) @([pscustomobject]@{ Pattern = '192.168.5.0/24'; Enabled = $true })) 'CIDR blacklist'

    $null = Save-WinRMInventory $hosts -StorePath $testRoot
    $loaded = @(Get-WinRMInventory -StorePath $testRoot)
    Assert-True ($loaded.Count -eq 1 -and @($loaded[0].Groups).Count -eq 2 -and @($loaded[0].Endpoints).Count -eq 2) "Inventory JSON round trip (hosts=$($loaded.Count), groups=$(@($loaded[0].Groups).Count), endpoints=$(@($loaded[0].Endpoints).Count))"
    $csv = Join-Path $testRoot 'inventory.csv'
    $null = Export-WinRMInventoryCsv $loaded $csv
    Assert-True (@(Import-Csv $csv).Count -eq 1) 'CSV export'
    $imported = @(Import-WinRMInventoryCsv $csv @() @())
    Assert-True ($imported.Count -eq 1 -and $imported[0].Address -eq '10.20.30.40' -and @($imported[0].Groups).Count -eq 2 -and @($imported[0].Tags).Count -eq 2) 'CSV import'

    $null = Write-WinRMAuditEvent -StorePath $testRoot -Event 'Fixture' -Data @{ Value = 42 }
    $events = @(Get-WinRMAuditEvent -StorePath $testRoot -Last 10)
    Assert-True ($events.Count -eq 1 -and $events[0].Data.Value -eq 42) 'JSONL audit'

    Import-Module $toolsPath -Force
    $tools = Get-Module WinRM.Tools
    $netBiosResponse = [byte[]]::new(48)
    $netBiosResponse[5] = 1; $netBiosResponse[7] = 1
    $netBiosResponse[12] = 0; $netBiosResponse[13] = 0; $netBiosResponse[14] = 0x21; $netBiosResponse[15] = 0; $netBiosResponse[16] = 1
    $netBiosResponse[17] = 0xC0; $netBiosResponse[18] = 0x0C
    $netBiosResponse[19] = 0; $netBiosResponse[20] = 0x21; $netBiosResponse[21] = 0; $netBiosResponse[22] = 1
    $netBiosResponse[27] = 0; $netBiosResponse[28] = 19; $netBiosResponse[29] = 1
    [Text.Encoding]::ASCII.GetBytes('DESKTOP-FIXTURE').CopyTo($netBiosResponse, 30)
    $netBiosResponse[45] = 0x20
    $netBiosName = & $tools { param($Response) Get-WinRMNetBiosNameFromResponse -Response $Response } $netBiosResponse
    Assert-True ($netBiosName -eq 'DESKTOP-FIXTURE') 'NetBIOS workstation service record yields the computer name'
    $aliasTarget = [pscustomobject]@{ Address = '127.0.0.1'; VerifiedConnectionHost = 'localhost' }
    $aliasResolution = & $tools { param($Target) Resolve-WinRMTargetConnection -Target $Target -TimeoutMs 1000 } $aliasTarget
    Assert-True ($aliasResolution.ConnectionHost -eq 'localhost') 'Verified connection host is preferred'
    $skipResolution = & $tools { param($Target) Resolve-WinRMTargetConnection -Target $Target -TimeoutMs 1000 -SkipDns } $aliasTarget
    Assert-True ($skipResolution.ConnectionHost -eq '127.0.0.1') 'SkipDns ignores connection host alias'
    & $tools {
        function script:New-WinRMTargetSession { param($Target, $Credential, $Authentication, $OpenTimeoutMs, [switch]$SkipDns) 'fixture-session' }
        function script:Copy-Item {
            param($LiteralPath, $Path, $Destination, $ToSession, $FromSession, [switch]$Recurse, [switch]$Force, $ErrorAction)
            $script:copyCall = [pscustomobject]@{ Source = $(if ($LiteralPath) { $LiteralPath } else { $Path }); Destination = $Destination; To = $ToSession; From = $FromSession }
        }
        function script:Remove-PSSession { param($Session, $ErrorAction) $script:removed = $true }
        $script:copyCall = $null; $script:removed = $false
    }
    $localFile = Join-Path $testRoot 'fixture.txt'
    [IO.File]::WriteAllText($localFile, 'fixture')
    $target = [pscustomobject]@{ Address = '10.20.30.40'; ComputerName = 'PC40'; Port = 5985; Transport = 'HTTP' }
    $transfer = Invoke-WinRMFileTransferTarget $target Upload $localFile 'C:\Windows\Temp'
    Assert-True ($transfer.Status -eq 'Succeeded') 'Mocked upload result'
    Assert-True ((& $tools { $null -ne $script:copyCall -and $script:removed })) 'Upload invoked and session removed'

    'PASS: store, merge, preferred endpoints, groups, tags, filters, blacklist, JSON/CSV, audit and file transfer.'
}
finally {
    Remove-Module WinRM.Manager, WinRM.Tools -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) {
        # The target is a unique directory created above under the OS temp path.
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
