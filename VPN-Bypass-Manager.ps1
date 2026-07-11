# =============================================
# VPN Bypass Manager
# Author: Anen135
# Version: 1.0
# =============================================

param(
    [switch]$Add,
    [switch]$Remove,
    [switch]$List,
    [string]$Target = ""   # IP or domain
)

$DefaultGateway = ""  # If empty — determines automatically

function Get-DefaultGateway {
    # Primary IPv4 gateway
    $gw = (Get-NetRoute -De stinationPrefix 0.0.0.0/0 -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
    
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
        return
    }
    Write-Host "Automatically detected gateway: $DefaultGateway" -ForegroundColor Cyan
}

function Add-Bypass {
    param([string]$Target)

    $ipObj = $null
    $isIPv4 = [System.Net.IPAddress]::TryParse($Target, [ref]$ipObj) -and $ipObj.AddressFamily -eq 'InterNetwork'

    if ($isIPv4) {
        route -p add $Target mask 255.255.255.255 $DefaultGateway *>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Added: $Target" -ForegroundColor Green
        } else {
            Write-Host "Error adding $Target" -ForegroundColor Red
        }
    } 
    else {
        try {
            $ips = [System.Net.Dns]::GetHostAddresses($Target) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
            
            if ($ips) {
                foreach ($ip in $ips) {
                    $ipStr = $ip.IPAddressToString
                    route -p add $ipStr mask 255.255.255.255 $DefaultGateway *>$null
                    Write-Host "Added: $ipStr  ← $Target" -ForegroundColor Green
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
        route delete $Target *>$null
        Write-Host "Removed: $Target" -ForegroundColor Yellow
    } 
    else {
        try {
            $ips = [System.Net.Dns]::GetHostAddresses($Target) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
            
            if ($ips) {
                foreach ($ip in $ips) {
                    $ipStr = $ip.IPAddressToString
                    route delete $ipStr *>$null
                    Write-Host "Removed: $ipStr  ← $Target" -ForegroundColor Yellow
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
    route print | Select-String "Persistent Routes" -Context 0,20
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
Write-Host "=== VPN Bypass Manager ===" -ForegroundColor Cyan
Write-Host "Examples:" -ForegroundColor White
Write-Host ".\script.ps1 -Add -Target google.com" -ForegroundColor Gray
Write-Host ".\script.ps1 -Add -Target 8.8.8.8" -ForegroundColor Gray
Write-Host ".\script.ps1 -Remove -Target google.com" -ForegroundColor Gray
Write-Host ".\script.ps1 -List" -ForegroundColor Gray