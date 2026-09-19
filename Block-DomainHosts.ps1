#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Blocks a domain through the Windows hosts file.

.DESCRIPTION
    Removes existing mappings for the exact DNS name, adds IPv4 and IPv6 block
    entries to the Windows hosts file, and clears the DNS client cache. Existing
    aliases on the same hosts-file line are preserved. A timestamped backup is
    created beside the hosts file before it is changed.

    Only the exact name is blocked. Run the script separately for subdomains
    such as www.example.com.

.PARAMETER Domain
    The exact DNS name to block. Do not include a protocol, port, or path.

.EXAMPLE
    .\Block-DomainHosts.ps1 -Domain "example.com"

    Blocks example.com through both IPv4 and IPv6 hosts-file entries.

.EXAMPLE
    .\Block-DomainHosts.ps1 -Domain "example.com" -Verbose

    Blocks the domain and displays detailed progress information.

.EXAMPLE
    .\Block-DomainHosts.ps1 -Domain "example.com" -WhatIf

    Shows the hosts-file change without applying it.

.NOTES
    Version: 1.0
    Author: Anen
    Requires Administrator privileges.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Domain
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    $hostsContents = [System.IO.File]::ReadAllText($hostsPath)
    $beginMarker = "# BEGIN Block-DomainHosts: $normalizedDomain"
    $endMarker = "# END Block-DomainHosts: $normalizedDomain"

    # Remove a block created by an earlier run before rebuilding it.
    $blockPattern = '(?ms)^' + [regex]::Escape($beginMarker) +
        '\r?$\n.*?^' + [regex]::Escape($endMarker) + '\r?$(?:\n)?'
    $hostsContents = [regex]::Replace($hostsContents, $blockPattern, '')

    $updatedLines = [System.Collections.Generic.List[string]]::new()
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
            $remainingNames = @(
                $tokens[1..($tokens.Count - 1)] |
                    Where-Object { $_ -ine $normalizedDomain }
            )

            if ($remainingNames.Count -ne ($tokens.Count - 1)) {
                Write-Verbose "Removing an existing mapping for '$normalizedDomain'."

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

        $updatedLines.Add($line)
    }

    while ($updatedLines.Count -gt 0 -and
        [string]::IsNullOrWhiteSpace($updatedLines[$updatedLines.Count - 1])) {
        $updatedLines.RemoveAt($updatedLines.Count - 1)
    }

    $updatedLines.Add('')
    $updatedLines.Add($beginMarker)
    $updatedLines.Add("0.0.0.0$([char]9)$normalizedDomain")
    $updatedLines.Add("::$([char]9)$normalizedDomain")
    $updatedLines.Add($endMarker)
    $newContents = ($updatedLines -join [Environment]::NewLine) +
        [Environment]::NewLine

    if ($PSCmdlet.ShouldProcess(
            $hostsPath,
            "Block '$normalizedDomain' and clear the DNS client cache"
        )) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
        $backupPath = "$hostsPath.block-domain-backup-$timestamp"

        Write-Verbose "Creating backup '$backupPath'."
        Copy-Item -LiteralPath $hostsPath -Destination $backupPath -ErrorAction Stop

        Write-Verbose "Writing block entries for '$normalizedDomain'."
        $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($hostsPath, $newContents, $utf8WithoutBom)

        Write-Verbose 'Clearing the DNS client cache.'
        Clear-DnsClientCache -ErrorAction Stop

        Write-Output ([PSCustomObject]@{
            Domain     = $normalizedDomain
            HostsPath  = $hostsPath
            BackupPath = $backupPath
            Status     = 'Blocked'
        })
    }
}
catch {
    Write-Error "Failed to block domain through the hosts file: $($_.Exception.Message)"
    throw
}
