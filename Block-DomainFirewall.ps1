#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Adds or removes a domain block in Windows Defender Firewall.

.DESCRIPTION
    Resolves the specified domain to its current IPv4 and IPv6 addresses and
    creates or updates a persistent outbound Windows Defender Firewall rule.
    Run the script again to refresh the rule when the domain addresses change.

    The rule blocks IP addresses, so other domains hosted on the same addresses
    can also become unavailable.

    Use -Remove to delete the firewall rule without resolving the domain.

.PARAMETER Domain
    The exact DNS name to block. Do not include a protocol, port, or path. If
    omitted, the script prompts for it. This supports execution through
    Invoke-RestMethod and Invoke-Expression.

.PARAMETER Remove
    Removes the firewall rule created for the domain.

.EXAMPLE
    .\Block-DomainFirewall.ps1 -Domain "example.com"

    Resolves example.com and blocks outbound traffic to all returned addresses.

.EXAMPLE
    .\Block-DomainFirewall.ps1 -Domain "example.com" -Verbose

    Updates the rule and displays detailed progress information.

.EXAMPLE
    .\Block-DomainFirewall.ps1 -Domain "example.com" -Remove

    Removes the firewall rule for example.com.

.EXAMPLE
    .\Block-DomainFirewall.ps1 -Domain "example.com" -WhatIf

    Shows the firewall rule change without applying it.

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

function Test-DomainFirewallShouldProcess {
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

    if ($Remove) {
        if ($null -eq $existingRule) {
            Write-Output ([PSCustomObject]@{
                Domain   = $normalizedDomain
                RuleName = $ruleName
                Status   = 'NotFound'
            })
            return
        }

        $shouldProcessParameters = @{
            Target = $normalizedDomain
            Action = "Remove outbound firewall rule '$displayName'"
        }
        if (Test-DomainFirewallShouldProcess @shouldProcessParameters) {
            Write-Verbose "Removing firewall rule '$ruleName'."
            Remove-NetFirewallRule -Name $ruleName -ErrorAction Stop

            Write-Output ([PSCustomObject]@{
                Domain   = $normalizedDomain
                RuleName = $ruleName
                Status   = 'Removed'
            })
        }
        return
    }

    Write-Verbose "Resolving '$normalizedDomain'..."
    $addressList = [System.Collections.Generic.List[string]]::new()
    foreach ($address in [System.Net.Dns]::GetHostAddresses($normalizedDomain)) {
        if ($address.AddressFamily -eq
                [System.Net.Sockets.AddressFamily]::InterNetwork -or
            $address.AddressFamily -eq
                [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
            $addressList.Add($address.IPAddressToString)
        }
    }
    $addresses = @($addressList | Sort-Object -Unique)

    if ($addresses.Count -eq 0) {
        throw "DNS did not return an IPv4 or IPv6 address for '$normalizedDomain'."
    }

    Write-Verbose "Resolved addresses: $($addresses -join ', ')"

    $operation = if ($null -eq $existingRule) { 'Create' } else { 'Update' }

    $shouldProcessParameters = @{
        Target = "$normalizedDomain ($($addresses -join ', '))"
        Action = "$operation outbound firewall rule '$displayName'"
    }
    if (Test-DomainFirewallShouldProcess @shouldProcessParameters) {
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
                Name           = $ruleName
                NewDisplayName = $displayName
                Description    = "Blocks addresses resolved for $normalizedDomain."
                Direction      = 'Outbound'
                Action         = 'Block'
                Enabled        = 'True'
                Profile        = 'Any'
                RemoteAddress  = $addresses
                ErrorAction    = 'Stop'
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
    Write-Error "Failed to manage the Windows Defender Firewall domain block: $($_.Exception.Message)"
    throw
}
