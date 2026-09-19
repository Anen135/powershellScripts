#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Blocks access to a domain through Windows Defender Firewall.

.DESCRIPTION
    Resolves the specified domain to its current IPv4 and IPv6 addresses and
    creates or updates a persistent outbound Windows Defender Firewall rule.
    Run the script again to refresh the rule when the domain addresses change.

    The rule blocks IP addresses, so other domains hosted on the same addresses
    can also become unavailable.

.PARAMETER Domain
    The exact DNS name to block. Do not include a protocol, port, or path.

.EXAMPLE
    .\Block-DomainFirewall.ps1 -Domain "example.com"

    Resolves example.com and blocks outbound traffic to all returned addresses.

.EXAMPLE
    .\Block-DomainFirewall.ps1 -Domain "example.com" -Verbose

    Updates the rule and displays detailed progress information.

.EXAMPLE
    .\Block-DomainFirewall.ps1 -Domain "example.com" -WhatIf

    Shows whether the firewall rule would be created or updated.

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

    Write-Verbose "Resolving '$normalizedDomain'..."
    $addresses = @(
        [System.Net.Dns]::GetHostAddresses($normalizedDomain) |
            Where-Object {
                $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -or
                $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6
            } |
            ForEach-Object IPAddressToString |
            Sort-Object -Unique
    )

    if ($addresses.Count -eq 0) {
        throw "DNS did not return an IPv4 or IPv6 address for '$normalizedDomain'."
    }

    Write-Verbose "Resolved addresses: $($addresses -join ', ')"

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $domainBytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedDomain)
        $hash = [System.BitConverter]::ToString(
            $sha256.ComputeHash($domainBytes)
        ).Replace('-', '').Substring(0, 24)
    }
    finally {
        $sha256.Dispose()
    }

    $ruleName = "Block-Domain-$hash"
    $displayName = "Block domain: $normalizedDomain"
    $existingRule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    $operation = if ($null -eq $existingRule) { 'Create' } else { 'Update' }

    if ($PSCmdlet.ShouldProcess(
            "$normalizedDomain ($($addresses -join ', '))",
            "$operation outbound firewall rule '$displayName'"
        )) {
        if ($null -eq $existingRule) {
            Write-Verbose "Creating firewall rule '$ruleName'."
            $newRuleParameters = @{
                Name          = $ruleName
                DisplayName   = $displayName
                Description   = "Blocks addresses resolved for $normalizedDomain."
                Group         = 'Domain blocks'
                Direction     = 'Outbound'
                Action        = 'Block'
                Enabled       = 'True'
                Profile       = 'Any'
                RemoteAddress = $addresses
                ErrorAction   = 'Stop'
            }
            New-NetFirewallRule @newRuleParameters | Out-Null
        }
        else {
            Write-Verbose "Updating firewall rule '$ruleName'."
            $setRuleParameters = @{
                Name          = $ruleName
                NewDisplayName = $displayName
                Description   = "Blocks addresses resolved for $normalizedDomain."
                Direction     = 'Outbound'
                Action        = 'Block'
                Enabled       = 'True'
                Profile       = 'Any'
                RemoteAddress = $addresses
                ErrorAction   = 'Stop'
            }
            Set-NetFirewallRule @setRuleParameters
        }

        Write-Warning "Firewall rules use IP addresses. Run this script again if the domain's DNS addresses change."

        Write-Output ([PSCustomObject]@{
            Domain    = $normalizedDomain
            Addresses = $addresses -join ', '
            RuleName  = $ruleName
            Status    = if ($operation -eq 'Create') { 'Created' } else { 'Updated' }
        })
    }
}
catch {
    Write-Error "Failed to block domain through Windows Defender Firewall: $($_.Exception.Message)"
    throw
}
