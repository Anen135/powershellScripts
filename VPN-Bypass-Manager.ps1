# =============================================
# VPN Bypass Manager
# Author: Anen135
# Version: 2.1 — Rewritten using NetTCPIP (no route.exe)
# =============================================
# TODO:
# 1. Add an editor for saved addresses.
# 2. Add Refresh of saved domains (Note: Windows routing requires IPs, so this needs a background resolver).
# 3. Test operation in a system with multiple interfaces (Including Ethernet).
# NOTE: 
# 1. I switched to using NETTCPIP, there may be errors related to this
# 2. New-NetRoute may require to specify the interface ID

param(
    [Parameter(ParameterSetName='AddSet', Mandatory=$true)]
    [switch]$Add,

    [Parameter(ParameterSetName='RemoveSet', Mandatory=$true)]
    [switch]$Remove,

    [Parameter(ParameterSetName='ListSet')]
    [switch]$List,

    [Parameter(ParameterSetName='AddSet', Mandatory=$true)]
    [Parameter(ParameterSetName='RemoveSet', Mandatory=$true)]
    [string]$Target
)

# Check for administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as an Administrator."
    exit 1
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
    exit 1
}

if (-not $DefaultGateway) {
    $DefaultGateway = $routeInfo.Gateway
    Write-Host "Automatically detected gateway: $DefaultGateway" -ForegroundColor Cyan
}

$InterfaceIndex = $routeInfo.InterfaceIndex

function Add-Bypass {
    param([string]$Target)

    $ipObj = $null
    $isIPv4 = [System.Net.IPAddress]::TryParse($Target, [ref]$ipObj) -and $ipObj.AddressFamily -eq 'InterNetwork'

    if ($isIPv4) {
        try {
            New-NetRoute -DestinationPrefix "$Target/32" -NextHop $DefaultGateway -ErrorAction Stop | Out-Null
            Write-Host "Added: $Target" -ForegroundColor Green
        } catch {
            Write-Host "Error adding $Target : $_" -ForegroundColor Red
        }
    }
    else {
        try {
            $ips = [System.Net.Dns]::GetHostAddresses($Target) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }

            if ($ips) {
                foreach ($ip in $ips) {
                    $ipStr = $ip.IPAddressToString
                    try {
                        New-NetRoute -DestinationPrefix "$ipStr/32" -NextHop $DefaultGateway -ErrorAction Stop | Out-Null
                        Write-Host "Added: $ipStr <== $Target" -ForegroundColor Green
                    } catch {
                        Write-Host "Error adding $ipStr : $_" -ForegroundColor Red
                    }
                }
            } else {
                Write-Host "Domain resolved, but no IPv4 addresses found for: $Target" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Could not resolve domain: $Target" -ForegroundColor Red
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
                Write-Host "Route for $Target not found in PersistentStore." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Error removing $Target : $_" -ForegroundColor Red
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
                            Write-Host "Route for $ipStr not found." -ForegroundColor Yellow
                        }
                    } catch {
                        Write-Host "Error removing $ipStr : $_" -ForegroundColor Red
                    }
                }
            } else {
                Write-Host "Domain resolved, but no IPv4 addresses found for: $Target" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Could not resolve domain: $Target" -ForegroundColor Red
        }
    }
}

# ====================== MODES ======================
if ($List) {
    Write-Host "Persistent Routes (excluding default routes):" -ForegroundColor Cyan
    $routes = Get-NetRoute -PolicyStore PersistentStore -ErrorAction SilentlyContinue | 
              Where-Object { $_.DestinationPrefix -ne '0.0.0.0/0' -and $_.DestinationPrefix -ne '::/0' }
    
    if ($routes) {
        $routes | Format-Table -Property DestinationPrefix, NextHop, RouteMetric, InterfaceIndex -AutoSize
    } else {
        Write-Host "No persistent routes found." -ForegroundColor Yellow
    }
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