#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Adds or removes a domain block in the Windows hosts file.

.DESCRIPTION
    Removes existing mappings for the exact DNS name, adds IPv4 and IPv6 block
    entries to the Windows hosts file, and clears the DNS client cache. Existing
    aliases on the same hosts-file line are preserved. A timestamped backup is
    created beside the hosts file before it is changed.

    Only the exact name is blocked. Run the script separately for subdomains
    such as www.example.com.

    Use -Remove to delete the managed block and any matching orphaned
    0.0.0.0 or :: entries.

.PARAMETER Domain
    The exact DNS name to block. Do not include a protocol, port, or path. If
    omitted, the script prompts for it. This supports execution through
    Invoke-RestMethod and Invoke-Expression.

.PARAMETER Remove
    Removes the hosts-file block for the domain.

.EXAMPLE
    .\Block-DomainHosts.ps1 -Domain "example.com"

    Blocks example.com through both IPv4 and IPv6 hosts-file entries.

.EXAMPLE
    .\Block-DomainHosts.ps1 -Domain "example.com" -Verbose

    Blocks the domain and displays detailed progress information.

.EXAMPLE
    .\Block-DomainHosts.ps1 -Domain "example.com" -Remove

    Removes the hosts-file block for example.com.

.EXAMPLE
    .\Block-DomainHosts.ps1 -Domain "example.com" -WhatIf

    Shows the hosts-file change without applying it.

.NOTES
    Version: 1.2
    Author: Anen
    Requires Administrator privileges.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Position = 0)]
    [string]$Domain,

    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-DomainHostsShouldProcess {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [string]$Action
    )

    return $PSCmdlet.ShouldProcess($Target, $Action)
}

$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole(
        [System.Security.Principal.WindowsBuiltInRole]::Administrator
    )) {
    throw 'Run PowerShell as Administrator.'
}

if ([string]::IsNullOrWhiteSpace($Domain)) {
    $Domain = Read-Host 'Domain'
}
if ([string]::IsNullOrWhiteSpace($Domain)) {
    throw 'Domain cannot be empty.'
}

try {
    $domainValue = $Domain.Trim().TrimEnd('.')

    if ($domainValue -match '^[a-z][a-z0-9+.-]*://' -or
        $domainValue.IndexOfAny([char[]]'/\\:') -ge 0) {
        throw "Specify only a DNS name, without a protocol, port, or path."
    }

    $idn = [System.Globalization.IdnMapping]::new()
    $normalizedDomain = $idn.GetAscii($domainValue).ToLowerInvariant()

    if ([System.Uri]::CheckHostName($normalizedDomain) -ne
        [System.UriHostNameType]::Dns) {
        throw "'$Domain' is not a valid DNS name."
    }

    $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    if (-not (Test-Path -LiteralPath $hostsPath -PathType Leaf)) {
        throw "Hosts file was not found at '$hostsPath'."
    }

    Write-Verbose "Reading '$hostsPath'."
    $originalHostsContents = [System.IO.File]::ReadAllText($hostsPath)
    $hostsContents = $originalHostsContents
    $beginMarker = "# BEGIN Block-DomainHosts: $normalizedDomain"
    $endMarker = "# END Block-DomainHosts: $normalizedDomain"

    # Remove a managed block created by an earlier run.
    $blockPattern = '(?ms)^' + [regex]::Escape($beginMarker) +
        '\r?$\n.*?^' + [regex]::Escape($endMarker) + '\r?$(?:\n)?'
    $hostsContents = [regex]::Replace($hostsContents, $blockPattern, '')
    $managedBlockRemoved = $hostsContents -cne $originalHostsContents

    $updatedLines = [System.Collections.Generic.List[string]]::new()
    $mappingRemoved = $false
    foreach ($line in ($hostsContents -split '\r?\n')) {
        $commentIndex = $line.IndexOf('#')
        if ($commentIndex -ge 0) {
            $dataPart = $line.Substring(0, $commentIndex)
            $commentPart = $line.Substring($commentIndex)
        }
        else {
            $dataPart = $line
            $commentPart = ''
        }

        $tokens = @(
            [regex]::Split($dataPart.Trim(), '\s+') |
                Where-Object { $_.Length -gt 0 }
        )

        if ($tokens.Count -ge 2) {
            $removeMapping = -not $Remove -or
                $tokens[0] -eq '0.0.0.0' -or
                $tokens[0] -eq '::'

            if ($removeMapping) {
                $remainingNames = @(
                    $tokens[1..($tokens.Count - 1)] |
                        Where-Object { $_ -ine $normalizedDomain }
                )

                if ($remainingNames.Count -ne ($tokens.Count - 1)) {
                    Write-Verbose "Removing an existing mapping for '$normalizedDomain'."
                    $mappingRemoved = $true

                    if ($remainingNames.Count -gt 0) {
                        $rebuiltLine = "$($tokens[0])$([char]9)$($remainingNames -join ' ')"
                        if ($commentPart.Length -gt 0) {
                            $rebuiltLine += " $commentPart"
                        }
                        $updatedLines.Add($rebuiltLine)
                    }
                    elseif ($commentPart.Length -gt 0) {
                        $updatedLines.Add($commentPart)
                    }

                    continue
                }
            }
        }

        $updatedLines.Add($line)
    }

    if ($Remove -and -not $managedBlockRemoved -and -not $mappingRemoved) {
        Write-Output ([PSCustomObject]@{
            Domain     = $normalizedDomain
            HostsPath  = $hostsPath
            BackupPath = $null
            Status     = 'NotFound'
        })
        return
    }

    while ($updatedLines.Count -gt 0 -and
        [string]::IsNullOrWhiteSpace($updatedLines[$updatedLines.Count - 1])) {
        $updatedLines.RemoveAt($updatedLines.Count - 1)
    }

    if (-not $Remove) {
        $updatedLines.Add('')
        $updatedLines.Add($beginMarker)
        $updatedLines.Add("0.0.0.0$([char]9)$normalizedDomain")
        $updatedLines.Add("::$([char]9)$normalizedDomain")
        $updatedLines.Add($endMarker)
    }

    $newContents = ($updatedLines -join [Environment]::NewLine) +
        [Environment]::NewLine
    $action = if ($Remove) { 'Remove block for' } else { 'Block' }
    $status = if ($Remove) { 'Removed' } else { 'Blocked' }

    $shouldProcessParameters = @{
        Target = $hostsPath
        Action = "$action '$normalizedDomain' and clear the DNS client cache"
    }
    if (Test-DomainHostsShouldProcess @shouldProcessParameters) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
        $backupPath = "$hostsPath.block-domain-backup-$timestamp"

        Write-Verbose "Creating backup '$backupPath'."
        Copy-Item -LiteralPath $hostsPath -Destination $backupPath -ErrorAction Stop

        Write-Verbose "Writing updated hosts file for '$normalizedDomain'."
        $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($hostsPath, $newContents, $utf8WithoutBom)

        Write-Verbose 'Clearing the DNS client cache.'
        Clear-DnsClientCache -ErrorAction Stop

        Write-Output ([PSCustomObject]@{
            Domain     = $normalizedDomain
            HostsPath  = $hostsPath
            BackupPath = $backupPath
            Status     = $status
        })
    }
}
catch {
    Write-Error "Failed to manage the hosts-file domain block: $($_.Exception.Message)"
    throw
}
