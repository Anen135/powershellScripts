# =============================================
# VPN Bypass Manager
# =============================================

<#
.SYNOPSIS
    Manages persistent network routes to bypass VPN for specific IPs or domains.

.DESCRIPTION
    Adds, removes, or lists persistent network routes using NetTCPIP cmdlets
    (New-NetRoute / Remove-NetRoute) to bypass VPN for specified IP addresses
    or domain names. The default gateway is auto-detected. Requires
    Administrator privileges.

.PARAMETER Add
    Add a bypass route for the specified target.

.PARAMETER Remove
    Remove an existing bypass route for the specified target.

.PARAMETER List
    Display all persistent routes currently configured.

.PARAMETER Target
    IP address (e.g., 8.8.8.8) or domain name (e.g., google.com) to
    bypass VPN for.

.EXAMPLE
    .\VPN-Bypass-Manager.ps1 -Add -Target google.com

.EXAMPLE
    .\VPN-Bypass-Manager.ps1 -Add -Target 8.8.8.8

.EXAMPLE
    .\VPN-Bypass-Manager.ps1 -Remove -Target google.com

.EXAMPLE
    .\VPN-Bypass-Manager.ps1 -List

.NOTES
    Version: 2.1
    Author: Anen
#>
param(
    [Parameter(ParameterSetName='AddSet', Mandatory=$true)]
    [switch]$Add,

    [Parameter(ParameterSetName='RemoveSet', Mandatory=$true)]
    [switch]$Remove,

    [Parameter(ParameterSetName='ListSet')]
    [switch]$List,

    [Parameter(ParameterSetName='AddSet', Mandatory=$true)]
    [Parameter(ParameterSetName='RemoveSet', Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Target
)

# Check for administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as an Administrator."
    throw
}

$DefaultGateway = ""  # If empty — auto-detected

function Get-DefaultRouteInfo {
    $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | 
             Sort-Object RouteMetric | 
             Select-Object -First 1

    if ($route) {
        return [PSCustomObject]@{
            Gateway        = $route.NextHop
            InterfaceIndex = $route.InterfaceIndex
        }
    }
    return $null
}

# Get route information once
$routeInfo = Get-DefaultRouteInfo

if (-not $routeInfo) {
    Write-Error "Could not determine default route. Check your network connection or specify `$DefaultGateway manually."
    throw
}

if (-not $DefaultGateway) {
    $DefaultGateway = $routeInfo.Gateway
    Write-Host "Automatically detected gateway: $DefaultGateway" -ForegroundColor Cyan
}

function Add-Bypass {
    param([string]$Target)

    $ipObj = $null
    $isIPv4 = [System.Net.IPAddress]::TryParse($Target, [ref]$ipObj) -and $ipObj.AddressFamily -eq 'InterNetwork'

    if ($isIPv4) {
        try {
            New-NetRoute -DestinationPrefix "$Target/32" -NextHop $DefaultGateway -InterfaceIndex $routeInfo.InterfaceIndex -ErrorAction Stop | Out-Null
            Write-Host "Added: $Target" -ForegroundColor Green
        } catch {
            Write-Error "Error adding ${Target}: $($_.Exception.Message)"
            throw
        }
    }
    else {
        try {
            $ips = [System.Net.Dns]::GetHostAddresses($Target) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }

            if ($ips) {
                foreach ($ip in $ips) {
                    $ipStr = $ip.IPAddressToString
                    try {
                        New-NetRoute -DestinationPrefix "$ipStr/32" -NextHop $DefaultGateway -InterfaceIndex $routeInfo.InterfaceIndex -ErrorAction Stop | Out-Null
                        Write-Host "Added: $ipStr <== $Target" -ForegroundColor Green
                    } catch {
                        Write-Error "Error adding ${ipStr}: $($_.Exception.Message)"
                        throw "Error adding ${ipStr}"
                    }
                }
            } else {
                Write-Warning "Domain resolved, but no IPv4 addresses found for: $Target"
            }
        } catch {
            Write-Error "Could not resolve domain: $Target"
            throw "Could not resolve domain: $Target"
        }
    }
}

function Remove-Bypass {
    param([string]$Target)

    $ipObj = $null
    $isIPv4 = [System.Net.IPAddress]::TryParse($Target, [ref]$ipObj) -and $ipObj.AddressFamily -eq 'InterNetwork'

    if ($isIPv4) {
        try {
            $route = Get-NetRoute -DestinationPrefix "$Target/32" -PolicyStore PersistentStore -ErrorAction SilentlyContinue
            if ($route) {
                $route | Remove-NetRoute -Confirm:$false -ErrorAction Stop
                Write-Host "Removed: $Target" -ForegroundColor Yellow
            } else {
                Write-Warning "Route for $Target not found in PersistentStore."
            }
        } catch {
            Write-Error "Error removing ${Target}: $($_.Exception.Message)"
            throw
        }
    }
    else {
        try {
            $ips = [System.Net.Dns]::GetHostAddresses($Target) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }

            if ($ips) {
                foreach ($ip in $ips) {
                    $ipStr = $ip.IPAddressToString
                    try {
                        $route = Get-NetRoute -DestinationPrefix "$ipStr/32" -PolicyStore PersistentStore -ErrorAction SilentlyContinue
                        if ($route) {
                            $route | Remove-NetRoute -Confirm:$false -ErrorAction Stop
                            Write-Host "Removed: $ipStr  ← $Target" -ForegroundColor Yellow
                        } else {
                            Write-Warning "Route for $ipStr not found."
                        }
                    } catch {
                        Write-Error "Error removing ${ipStr}: $($_.Exception.Message)"
                        throw
                    }
                }
            } else {
                Write-Warning "Domain resolved, but no IPv4 addresses found for: $Target"
            }
        } catch {
            Write-Error "Could not resolve domain: $Target"
            throw
        }
    }
}

function Show-List {
    Write-Host "Persistent Routes (excluding default routes):" -ForegroundColor Cyan
    $routes = Get-NetRoute -PolicyStore PersistentStore -ErrorAction SilentlyContinue | 
            Where-Object { $_.DestinationPrefix -ne '0.0.0.0/0' -and $_.DestinationPrefix -ne '::/0' }
    
    if ($routes) {
        $routes | Format-Table -Property DestinationPrefix, NextHop, RouteMetric, InterfaceIndex -AutoSize
    } else {
        Write-Warning "No persistent routes found."
    }
}

# ====================== MODES ======================
if ($List) {
    Show-List
    return
}

if ($Add) {
    Add-Bypass -Target $Target
    return
}

if ($Remove) {
    Remove-Bypass -Target $Target
    return
}

# Help
Write-Host "=== VPN Bypass Manager (NetTCPIP) ===" -ForegroundColor Cyan
Write-Host "Examples:" -ForegroundColor White
Write-Host ".\script.ps1 -Add -Target google.com" -ForegroundColor Gray
Write-Host ".\script.ps1 -Add -Target 8.8.8.8" -ForegroundColor Gray
Write-Host ".\script.ps1 -Remove -Target google.com" -ForegroundColor Gray
Write-Host ".\script.ps1 -List" -ForegroundColor Gray