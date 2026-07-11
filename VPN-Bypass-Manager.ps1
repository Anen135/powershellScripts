# =============================================
# VPN Bypass Manager
# Author: Anen135
# Version: 2.0 — Rewritten using NETTCPIP (no route.exe)
# =============================================
# TODO:
# 1. Add an editor for saved addresses.
# 2. Add Refresh of saved domains
# 3. Test operation in a system with multiple interfaces (Including Ethernet)

param(
    [switch]$Add,
    [switch]$Remove,
    [switch]$List,
    [string]$Target = ""   # IP or domain
)

if (-not (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run PowerShell as an administrator"
    exit 1
}

$DefaultGateway = ""  # If empty — determines automatically

function Get-DefaultGateway {
    $gw = (Get-NetRoute -DestinationPrefix 0.0.0.0/0 -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop

    if (-not $gw) {
        $gw = (Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object IPv4DefaultGateway | Select-Object -First 1).IPv4DefaultGateway.NextHop
    }
    if (-not $gw) {
        $gw = (Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object IPv6DefaultGateway | Select-Object -First 1).IPv6DefaultGateway.NextHop 
    }
    return $gw
}

if (-not $DefaultGateway) {
    $DefaultGateway = Get-DefaultGateway
    if (-not $DefaultGateway) {
        Write-Error "Could not determine default gateway. Specify it manually in the `$DefaultGateway variable"
        exit 1
    }
    Write-Host "Automatically detected gateway: $DefaultGateway" -ForegroundColor Cyan
}

function Add-Bypass {
    param([string]$Target)

    $ipObj = $null
    $isIPv4 = [System.Net.IPAddress]::TryParse($Target, [ref]$ipObj) -and $ipObj.AddressFamily -eq 'InterNetwork'

    if ($isIPv4) {
        try {
            New-NetRoute -DestinationPrefix "$Target/32" -NextHop $DefaultGateway -PolicyStore PersistentStore -ErrorAction Stop | Out-Null
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
                        New-NetRoute -DestinationPrefix "$ipStr/32" -NextHop $DefaultGateway -PolicyStore PersistentStore -ErrorAction Stop | Out-Null
                        Write-Host "Added: $ipStr <=== $Target" -ForegroundColor Green
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
            Get-NetRoute -DestinationPrefix "$Target/32" -PolicyStore PersistentStore -ErrorAction Stop |
                Remove-NetRoute -Confirm:$false -ErrorAction Stop | Out-Null
            Write-Host "Removed: $Target" -ForegroundColor Yellow
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
                        Get-NetRoute -DestinationPrefix "$ipStr/32" -PolicyStore PersistentStore -ErrorAction Stop |
                            Remove-NetRoute -Confirm:$false -ErrorAction Stop | Out-Null
                        Write-Host "Removed: $ipStr  ← $Target" -ForegroundColor Yellow
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
    Write-Host "Persistent Routes:" -ForegroundColor Cyan
    $routes = Get-NetRoute -PolicyStore PersistentStore -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -ne '0.0.0.0/0' -and $_.DestinationPrefix -ne '::/0' }
    if ($routes) {
        $routes | Format-Table -Property DestinationPrefix, NextHop, RouteMetric, ifIndex -AutoSize
    } else {
        Write-Host "No persistent routes found." -ForegroundColor Yellow
    }
    return
}

if ($Add -and $Target) {
    Add-Bypass -Target $Target
    return
}

if ($Remove -and $Target) {
    Remove-Bypass -Target $Target
    return
}

# Help
Write-Host "=== VPN Bypass Manager (NETTCPIP) ===" -ForegroundColor Cyan
Write-Host "Examples:" -ForegroundColor White
Write-Host ".\script.ps1 -Add -Target google.com" -ForegroundColor Gray
Write-Host ".\script.ps1 -Add -Target 8.8.8.8" -ForegroundColor Gray
Write-Host ".\script.ps1 -Remove -Target google.com" -ForegroundColor Gray
Write-Host ".\script.ps1 -List" -ForegroundColor Gray