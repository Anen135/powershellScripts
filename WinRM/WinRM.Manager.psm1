#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-WinRMDefaultStorePath {
    [CmdletBinding()]
    param()

    $base = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    }
    else { $env:LOCALAPPDATA }
    Join-Path $base 'WinRMTui'
}

function Get-WinRMConfigDefaults {
    $networks = @()
    try {
        $networks = @(Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred -ErrorAction Stop |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
            ForEach-Object {
                $prefix = [Math]::Max(16, [int]$_.PrefixLength)
                [pscustomobject][ordered]@{
                    Name = if ([string]::IsNullOrWhiteSpace($_.InterfaceAlias)) { $_.IPAddress } else { $_.InterfaceAlias }
                    Range = '{0}/{1}' -f $_.IPAddress, $prefix
                    HttpPort = 5985; HttpsPort = 5986; Enabled = $true
                }
            } | Sort-Object Range -Unique)
    }
    catch { $networks = @() }
    if ($networks.Count -eq 0) {
        $networks = @([pscustomobject][ordered]@{ Name = 'Local /24'; Range = '192.168.1.0/24'; HttpPort = 5985; HttpsPort = 5986; Enabled = $true })
    }
    [pscustomobject][ordered]@{
        SchemaVersion = 1
        Networks = $networks
        Blacklist = @()
        SmartGroups = @(
            [pscustomobject][ordered]@{ Name = 'Online'; Filter = 'status:Connected' },
            [pscustomobject][ordered]@{ Name = 'Low disk'; Filter = 'disk:<10' }
        )
        Settings = [pscustomobject][ordered]@{
            DiscoveryTimeoutMs = 900
            OpenTimeoutMs = 5000
            CommandTimeoutSec = 120
            ThrottleLimit = 24
            SkipDns = $false
        }
    }
}

function Write-WinRMJsonFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value, [int]$Depth = 12)

    $parent = [IO.Path]::GetDirectoryName($Path)
    if (-not [string]::IsNullOrWhiteSpace($parent)) { $null = [IO.Directory]::CreateDirectory($parent) }
    $temporary = Join-Path $parent ([IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $json = ConvertTo-Json -InputObject $Value -Depth $Depth
        [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) {
            try { [IO.File]::Replace($temporary, $Path, $null) }
            catch {
                [IO.File]::Copy($temporary, $Path, $true)
                [IO.File]::Delete($temporary)
            }
        }
        else { [IO.File]::Move($temporary, $Path) }
    }
    finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Initialize-WinRMStore {
    [CmdletBinding()]
    param([string]$StorePath = (Get-WinRMDefaultStorePath))

    $resolved = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StorePath))
    $null = [IO.Directory]::CreateDirectory($resolved)
    foreach ($directory in @('logs', 'downloads', 'scripts')) {
        $null = [IO.Directory]::CreateDirectory((Join-Path $resolved $directory))
    }
    $configPath = Join-Path $resolved 'config.json'
    $inventoryPath = Join-Path $resolved 'inventory.json'
    if (-not (Test-Path -LiteralPath $configPath)) { Write-WinRMJsonFile -Path $configPath -Value (Get-WinRMConfigDefaults) }
    if (-not (Test-Path -LiteralPath $inventoryPath)) { Write-WinRMJsonFile -Path $inventoryPath -Value @() }
    [pscustomobject][ordered]@{
        Root = $resolved
        Config = $configPath
        Inventory = $inventoryPath
        Audit = Join-Path $resolved 'logs\audit.jsonl'
        Downloads = Join-Path $resolved 'downloads'
        Scripts = Join-Path $resolved 'scripts'
    }
}

function Add-WinRMNoteProperty {
    param($Object, [string]$Name, $Value)
    $propertyNames = @($Object.PSObject.Properties | ForEach-Object { $_.Name })
    if ($propertyNames -notcontains $Name) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Get-WinRMManagerConfig {
    [CmdletBinding()]
    param([string]$StorePath = (Get-WinRMDefaultStorePath))

    $store = Initialize-WinRMStore -StorePath $StorePath
    $config = Get-Content -LiteralPath $store.Config -Raw -Encoding UTF8 | ConvertFrom-Json
    $defaults = Get-WinRMConfigDefaults
    foreach ($property in $defaults.PSObject.Properties) { Add-WinRMNoteProperty $config $property.Name $property.Value }
    foreach ($property in $defaults.Settings.PSObject.Properties) { Add-WinRMNoteProperty $config.Settings $property.Name $property.Value }
    # DefaultUser existed in an earlier UI revision. Credentials are now requested
    # for every operation, so do not keep or expose a stale saved account name.
    $config.Settings.PSObject.Properties.Remove('DefaultUser')
    $config
}

function Save-WinRMManagerConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config, [string]$StorePath = (Get-WinRMDefaultStorePath))

    $store = Initialize-WinRMStore -StorePath $StorePath
    Write-WinRMJsonFile -Path $store.Config -Value $Config
    $Config
}

function Normalize-WinRMHost {
    param([Parameter(Mandatory)]$HostRecord)

    $address = if (@($HostRecord.PSObject.Properties.Match('Address')).Count -gt 0) { [string]$HostRecord.Address } else { '' }
    $data = [ordered]@{
        Id = $address; Address = $address; ComputerName = $address
        Groups = @(); Tags = @(); Note = ''; Favorite = $false; Endpoints = @()
        FirstSeen = [DateTime]::UtcNow.ToString('o'); LastSeen = $null
        ConnectionStatus = 'NotTested'; Status = 'Unknown'
        OS = $null; OSVersion = $null; LastBootTime = $null; UptimeDays = $null
        FreeSpaceGB = $null; LoggedOnUser = $null
    }
    foreach ($property in $HostRecord.PSObject.Properties) { $data[$property.Name] = $property.Value }
    $data.Groups = @($data.Groups | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
    $data.Tags = @($data.Tags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
    $data.Endpoints = @($data.Endpoints)
    [pscustomobject]$data
}

function Get-WinRMInventory {
    [CmdletBinding()]
    param([string]$StorePath = (Get-WinRMDefaultStorePath))

    $store = Initialize-WinRMStore -StorePath $StorePath
    $text = Get-Content -LiteralPath $store.Inventory -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    $parsed = $text | ConvertFrom-Json
    @(foreach ($item in @($parsed)) { Normalize-WinRMHost $item })
}

function Save-WinRMInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$HostRecord, [string]$StorePath = (Get-WinRMDefaultStorePath))

    $store = Initialize-WinRMStore -StorePath $StorePath
    $normalized = @($HostRecord | ForEach-Object { Normalize-WinRMHost $_ } | Sort-Object ComputerName, Address)
    Write-WinRMJsonFile -Path $store.Inventory -Value $normalized
    $normalized
}

function Select-WinRMPreferredEndpoint {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$HostRecord)

    $endpoints = @($HostRecord.Endpoints)
    if ($endpoints.Count -eq 0 -and @($HostRecord.PSObject.Properties.Match('Port')).Count -gt 0) {
        $endpoints = @($HostRecord)
    }
    @($endpoints | Sort-Object `
        @{ Expression = { $_.ConnectionStatus -eq 'Connected' }; Descending = $true }, `
        @{ Expression = { $_.DiscoveryStatus -eq 'WSManConfirmed' }; Descending = $true }, `
        @{ Expression = { $_.Transport -eq 'HTTPS' }; Descending = $true }, Port | Select-Object -First 1)[0]
}

function ConvertTo-WinRMIPv4Number {
    param([string]$Address)
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($Address, [ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { return $null }
    $bytes = $parsed.GetAddressBytes()
    [uint32](([uint32]$bytes[0] -shl 24) -bor ([uint32]$bytes[1] -shl 16) -bor ([uint32]$bytes[2] -shl 8) -bor [uint32]$bytes[3])
}

function ConvertTo-WinRMDiscoveryPattern {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Range)

    $value = $Range.Trim()
    $addressPart = @($value.Split('/', 2))[0]
    if ($addressPart.Contains('*') -and $addressPart -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\*$') {
        return $value
    }

    $probeAddress = $addressPart.Replace('*', '0')
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($probeAddress, [ref]$parsed) -or
        $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        return $value
    }

    $bytes = $parsed.GetAddressBytes()
    '{0}.{1}.{2}.*' -f $bytes[0], $bytes[1], $bytes[2]
}

function Test-WinRMCidrMatch {
    param([string]$Address, [string]$Cidr)
    $parts = $Cidr.Split('/')
    if ($parts.Count -ne 2) { return $false }
    $prefix = 0
    if (-not [int]::TryParse($parts[1], [ref]$prefix) -or $prefix -lt 0 -or $prefix -gt 32) { return $false }
    $candidate = ConvertTo-WinRMIPv4Number $Address
    $network = ConvertTo-WinRMIPv4Number $parts[0]
    if ($null -eq $candidate -or $null -eq $network) { return $false }
    [uint32]$mask = if ($prefix -eq 0) { 0 } else { [uint32]::MaxValue -shl (32 - $prefix) }
    (($candidate -band $mask) -eq ($network -band $mask))
}

function Test-WinRMBlacklist {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$HostRecord, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Blacklist)

    foreach ($entry in $Blacklist) {
        $enabled = if (@($entry.PSObject.Properties.Match('Enabled')).Count -eq 0) { $true } else { [bool]$entry.Enabled }
        if (-not $enabled) { continue }
        $pattern = if ($entry -is [string]) { [string]$entry } else { [string]$entry.Pattern }
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        if ($pattern.Contains('/') -and (Test-WinRMCidrMatch -Address ([string]$HostRecord.Address) -Cidr $pattern)) { return $true }
        if ([string]$HostRecord.Address -like $pattern -or [string]$HostRecord.ComputerName -like $pattern) { return $true }
    }
    $false
}

function Merge-WinRMDiscoveryResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Current,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Discovery,
        [AllowEmptyCollection()][object[]]$Blacklist = @()
    )

    $map = @{}
    foreach ($item in $Current) {
        $hostItem = Normalize-WinRMHost $item
        $map[[string]$hostItem.Address] = $hostItem
    }
    foreach ($set in @($Discovery | Group-Object Address)) {
        $sample = @($set.Group | Sort-Object @{ Expression = { $_.DiscoveryStatus -eq 'WSManConfirmed' }; Descending = $true }, @{ Expression = { $_.Transport -eq 'HTTPS' }; Descending = $true })[0]
        if (Test-WinRMBlacklist -HostRecord $sample -Blacklist $Blacklist) { continue }
        $address = [string]$sample.Address
        $now = [DateTime]::UtcNow.ToString('o')
        if ($map.ContainsKey($address)) { $hostItem = $map[$address] }
        else {
            $sampleGroups = if (@($sample.PSObject.Properties.Match('Groups')).Count -gt 0) { @([string]$sample.Groups -split ';' | Where-Object { $_ }) } else { @() }
            $sampleTags = if (@($sample.PSObject.Properties.Match('Tags')).Count -gt 0) { @([string]$sample.Tags -split ';' | Where-Object { $_ }) } else { @() }
            $sampleNote = if (@($sample.PSObject.Properties.Match('Note')).Count -gt 0) { [string]$sample.Note } else { '' }
            $hostItem = [pscustomobject][ordered]@{
                Id = $address; Address = $address; ComputerName = $sample.ComputerName
                Groups = $sampleGroups; Tags = $sampleTags; Note = $sampleNote; Favorite = $false; Endpoints = @()
                FirstSeen = $now; LastSeen = $now; ConnectionStatus = 'NotTested'; Status = $sample.Status
                OS = $null; OSVersion = $null; LastBootTime = $null; UptimeDays = $null
                FreeSpaceGB = $null; LoggedOnUser = $null
            }
        }
        $hostItem.ComputerName = $sample.ComputerName
        $hostItem.LastSeen = $now
        $hostItem.Status = $sample.Status
        $hostItem.Endpoints = @($set.Group | ForEach-Object {
            $endpointValue = if (@($_.PSObject.Properties.Match('Endpoint')).Count -gt 0) { $_.Endpoint } else { '{0}://{1}:{2}/wsman' -f ([string]$_.Transport).ToLowerInvariant(), $_.Address, $_.Port }
            $discoveryStatus = if (@($_.PSObject.Properties.Match('DiscoveryStatus')).Count -gt 0) { $_.DiscoveryStatus } else { 'Imported' }
            $connectionStatus = if (@($_.PSObject.Properties.Match('ConnectionStatus')).Count -gt 0) { $_.ConnectionStatus } else { 'NotTested' }
            $detailValue = if (@($_.PSObject.Properties.Match('Detail')).Count -gt 0) { $_.Detail } else { $null }
            [pscustomobject][ordered]@{
                Address = $_.Address; Port = [int]$_.Port; Transport = $_.Transport
                Endpoint = $endpointValue; DiscoveryStatus = $discoveryStatus
                ConnectionStatus = $connectionStatus; Detail = $detailValue
            }
        })
        $map[$address] = Normalize-WinRMHost $hostItem
    }
    @($map.Values | Sort-Object ComputerName, Address)
}

function Test-WinRMHostToken {
    param($HostRecord, [string]$Token)
    $negate = $Token.StartsWith('!')
    if ($negate) { $Token = $Token.Substring(1) }
    $match = $false
    $colon = $Token.IndexOf(':')
    if ($colon -gt 0) {
        $field = $Token.Substring(0, $colon).ToLowerInvariant()
        $value = $Token.Substring($colon + 1)
        switch ($field) {
            'group' { $match = @($HostRecord.Groups | Where-Object { $_ -like $value }).Count -gt 0 }
            'tag' { $match = @($HostRecord.Tags | Where-Object { $_ -like $value }).Count -gt 0 }
            'status' { $match = ([string]$HostRecord.Status -like $value -or [string]$HostRecord.ConnectionStatus -like $value) }
            'os' { $match = [string]$HostRecord.OS -like ('*' + $value + '*') }
            'name' { $match = [string]$HostRecord.ComputerName -like $value }
            'ip' { $match = [string]$HostRecord.Address -like $value }
            'disk' {
                if ($value -match '^(?<op><=|>=|<|>|=)?(?<number>\d+(?:[.,]\d+)?)$' -and $null -ne $HostRecord.FreeSpaceGB) {
                    $number = [double]($Matches.number -replace ',', '.')
                    switch ($Matches.op) { '<' { $match = $HostRecord.FreeSpaceGB -lt $number }; '<=' { $match = $HostRecord.FreeSpaceGB -le $number }; '>' { $match = $HostRecord.FreeSpaceGB -gt $number }; '>=' { $match = $HostRecord.FreeSpaceGB -ge $number }; default { $match = $HostRecord.FreeSpaceGB -eq $number } }
                }
            }
            default { $match = $false }
        }
    }
    else {
        $haystack = @($HostRecord.ComputerName, $HostRecord.Address, $HostRecord.OS, $HostRecord.Status, $HostRecord.Note) + @($HostRecord.Groups) + @($HostRecord.Tags)
        $match = @($haystack | Where-Object { [string]$_ -like ('*' + $Token + '*') }).Count -gt 0
    }
    if ($negate) { -not $match } else { $match }
}

function Find-WinRMInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$HostRecord,
        [string]$Filter,
        [AllowEmptyCollection()][object[]]$Blacklist = @(),
        [switch]$IncludeBlacklisted
    )

    $tokens = @($Filter -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    @($HostRecord | Where-Object {
        $hostItem = $_
        if (-not $IncludeBlacklisted -and (Test-WinRMBlacklist -HostRecord $hostItem -Blacklist $Blacklist)) { return $false }
        foreach ($token in $tokens) { if (-not (Test-WinRMHostToken -HostRecord $hostItem -Token $token)) { return $false } }
        $true
    })
}

function Set-WinRMHostGroups {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$HostRecord, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Group)
    $HostRecord.Groups = @($Group | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    $HostRecord
}

function Set-WinRMHostTags {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$HostRecord, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Tag)
    $HostRecord.Tags = @($Tag | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    $HostRecord
}

function Add-WinRMBlacklistEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$Pattern, [string]$Reason = '')
    if ([string]::IsNullOrWhiteSpace($Pattern)) { throw 'Blacklist pattern must not be empty.' }
    if (@($Config.Blacklist | Where-Object { $_.Pattern -eq $Pattern }).Count -eq 0) {
        $Config.Blacklist = @($Config.Blacklist) + [pscustomobject][ordered]@{
            Pattern = $Pattern; Reason = $Reason; Enabled = $true; AddedAt = [DateTime]::UtcNow.ToString('o')
        }
    }
    $Config
}

function Write-WinRMAuditEvent {
    [CmdletBinding()]
    param([string]$StorePath = (Get-WinRMDefaultStorePath), [Parameter(Mandatory)][string]$Event, $Data)
    $store = Initialize-WinRMStore -StorePath $StorePath
    $record = [ordered]@{ Time = [DateTime]::UtcNow.ToString('o'); Event = $Event }
    if ($null -ne $Data) { $record.Data = $Data }
    $line = $record | ConvertTo-Json -Depth 12 -Compress
    [IO.File]::AppendAllText($store.Audit, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    [pscustomobject]$record
}

function Get-WinRMAuditEvent {
    [CmdletBinding()]
    param([string]$StorePath = (Get-WinRMDefaultStorePath), [ValidateRange(1, 10000)][int]$Last = 100)
    $store = Initialize-WinRMStore -StorePath $StorePath
    if (-not (Test-Path -LiteralPath $store.Audit)) { return @() }
    @(Get-Content -LiteralPath $store.Audit -Tail $Last -Encoding UTF8 | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { Write-Warning "Invalid audit line: $_" }
    })
}

function Import-WinRMInventoryCsv {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [AllowEmptyCollection()][object[]]$Current = @(), [AllowEmptyCollection()][object[]]$Blacklist = @())
    $rows = @(Import-Csv -LiteralPath $Path)
    Merge-WinRMDiscoveryResult -Current $Current -Discovery $rows -Blacklist $Blacklist
}

function Export-WinRMInventoryCsv {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$HostRecord, [Parameter(Mandatory)][string]$Path)
    $HostRecord | ForEach-Object {
        $endpoint = Select-WinRMPreferredEndpoint $_
        [pscustomobject][ordered]@{
            Address = $_.Address; ComputerName = $_.ComputerName
            Port = if ($null -ne $endpoint) { $endpoint.Port } else { $null }
            Transport = if ($null -ne $endpoint) { $endpoint.Transport } else { $null }
            DiscoveryStatus = if ($null -ne $endpoint) { $endpoint.DiscoveryStatus } else { $null }
            ConnectionStatus = $_.ConnectionStatus; Status = $_.Status
            OS = $_.OS; OSVersion = $_.OSVersion; UptimeDays = $_.UptimeDays
            FreeSpaceGB = $_.FreeSpaceGB; LoggedOnUser = $_.LoggedOnUser
            Groups = @($_.Groups) -join ';'; Tags = @($_.Tags) -join ';'; Note = $_.Note
            FirstSeen = $_.FirstSeen; LastSeen = $_.LastSeen
        }
    } | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    Get-Item -LiteralPath $Path
}

Export-ModuleMember -Function @(
    'Get-WinRMDefaultStorePath', 'Initialize-WinRMStore', 'Get-WinRMManagerConfig',
    'Save-WinRMManagerConfig', 'Get-WinRMInventory', 'Save-WinRMInventory',
    'Merge-WinRMDiscoveryResult', 'Select-WinRMPreferredEndpoint', 'Test-WinRMBlacklist',
    'ConvertTo-WinRMDiscoveryPattern',
    'Find-WinRMInventory', 'Set-WinRMHostGroups', 'Set-WinRMHostTags',
    'Add-WinRMBlacklistEntry', 'Write-WinRMAuditEvent', 'Get-WinRMAuditEvent',
    'Import-WinRMInventoryCsv', 'Export-WinRMInventoryCsv'
)
