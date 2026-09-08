#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Disables or re-enables keyboard input on the local machine.

.DESCRIPTION
    Manages keyboard availability through two complementary mechanisms:

    Driver mode (default):
      Sets the startup type of the keyboard kernel driver services
      ('i8042prt' - PS/2 keyboards, 'kbdhid' - USB/HID keyboards) to
      Disabled (Start = 4). The change persists across reboots and takes
      effect after the next restart. The original startup value of each
      driver is saved to a JSON state file, so '-Enable' restores it exactly.

    Device mode (-Devices):
      Disables / re-enables the currently connected keyboard PnP devices.
      Takes effect immediately.

    Requires Administrator privileges.

    WARNING: Disabling the physical keyboard can lock you out of the local
    machine. Keep an alternative input method ready (touch screen, remote
    session, or the on-screen keyboard 'osk.exe'), or run
    '.\Set-KeyboardState.ps1 -Enable' to restore input.

.PARAMETER Driver
    The keyboard driver service to manage: 'i8042prt' (PS/2), 'kbdhid'
    (USB/HID), or 'All'. Default: 'All'.

.PARAMETER Devices
    Operate on keyboard PnP devices instead of driver services. Takes effect
    immediately and persists until re-enabled with '-Enable'.

.PARAMETER Enable
    Restore keyboard input. Restores the previously saved driver startup
    values and re-enables any disabled keyboard devices.

.PARAMETER List
    Display the current status of keyboard drivers and devices without
    changing anything.

.EXAMPLE
    .\Set-KeyboardState.ps1

    Disables the 'i8042prt' and 'kbdhid' keyboard drivers. Takes effect after
    the next restart.

.EXAMPLE
    .\Set-KeyboardState.ps1 -Driver kbdhid -Verbose

    Disables only the USB/HID keyboard driver.

.EXAMPLE
    .\Set-KeyboardState.ps1 -Devices

    Immediately disables all connected keyboard PnP devices.

.EXAMPLE
    .\Set-KeyboardState.ps1 -Enable

    Restores keyboard drivers and re-enables any disabled keyboard devices.

.EXAMPLE
    .\Set-KeyboardState.ps1 -List

    Shows the current keyboard driver and device status.

.NOTES
    Version: 2.0
    Author: Anen
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('i8042prt', 'kbdhid', 'All')]
    [string]$Driver = 'All',

    [switch]$Devices,
    [switch]$Enable,
    [switch]$List
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $ServicesPath = 'HKLM:\SYSTEM\CurrentControlSet\Services'
    $StateDir     = Join-Path $env:ProgramData 'Set-KeyboardState'
    $StateFile    = Join-Path $StateDir 'state.json'

    $DriverList = @('i8042prt', 'kbdhid')
    if ($Driver -ne 'All') { $DriverList = @($Driver) }

    Write-Verbose "State file: $StateFile"
    Write-Verbose "Target drivers: $($DriverList -join ', ')"

    function Read-KeyboardState {
    if (-not (Test-Path -Path $StateFile)) { return @() }

    try {
        return @(Get-Content -Path $StateFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        Write-Warning "State file '$StateFile' is invalid: $($_.Exception.Message)"
        return @()
    }
}

function Write-KeyboardState {
    param([object[]]$State)

    if (-not (Test-Path -Path $StateDir)) {
        New-Item -Path $StateDir -ItemType Directory -Force | Out-Null
    }

    if ($State.Count -eq 0) {
        Remove-Item -Path $StateFile -Force -ErrorAction SilentlyContinue
        return
    }

    $State | ConvertTo-Json -Depth 5 | Set-Content -Path $StateFile -Encoding UTF8
}

function Save-OriginalStart {
    param([string]$ServiceName, [int]$StartValue)

    $state = @()
    $state += Read-KeyboardState
    $isSaved = $state | Where-Object { $_.Service -eq $ServiceName }
    if ($isSaved) {
        Write-Verbose "Original start value for '$ServiceName' is already saved."
        return
    }

    $state += [PSCustomObject]@{
        Service       = $ServiceName
        OriginalStart = $StartValue
    }
    Write-KeyboardState -State $state
    Write-Verbose "Saved original start value ($StartValue) for '$ServiceName'."
}

function Set-DriverStartRegister {
    param([string]$ServiceName, [int]$Value)

    $keyPath = "$ServicesPath\$ServiceName"
    Write-Verbose "Setting '$keyPath\Start' to $Value"
    Set-ItemProperty -Path $keyPath -Name Start -Value $Value -Type DWord -ErrorAction Stop
}

function Disable-KeyboardDrivers {
    foreach ($name in $DriverList) {
        $prop = Get-ItemProperty -Path "$ServicesPath\$name" -Name Start -ErrorAction SilentlyContinue
        if ($null -eq $prop) {
            Write-Warning "Driver service '$name' is not installed. Skipped."
            continue
        }

        $current = [int]$prop.Start
        if ($current -eq 4) {
            Write-Verbose "Driver '$name' is already disabled. Skipped."
            continue
        }

        Save-OriginalStart -ServiceName $name -StartValue $current
        Set-DriverStartRegister -ServiceName $name -Value 4
        Write-Output "Driver '$name' disabled (start type 4). Restart required to take effect."
    }
}

function Enable-KeyboardDrivers {
    $state = @()
    $state += Read-KeyboardState

    if ($state.Count -eq 0) {
        Write-Output "No saved driver state found. Nothing to restore."
        return
    }

    foreach ($item in $state) {
        $name   = $item.Service
        $target = [int]$item.OriginalStart

        if (Test-Path -Path "$ServicesPath\$name") {
            Set-DriverStartRegister -ServiceName $name -Value $target
            Write-Output "Driver '$name' restored to start type $target. Restart required to take effect."
        }
        else {
            Write-Warning "Driver service '$name' no longer exists; state entry removed."
        }
    }

    Write-KeyboardState -State @()
}

function Get-KeyboardDevices {
    return @(Get-PnpDevice -Class Keyboard -PresentOnly -ErrorAction SilentlyContinue)
}

function Disable-KeyboardDevices {
    $devices = @()
    $devices += Get-KeyboardDevices

    if ($devices.Count -eq 0) {
        Write-Warning "No keyboard PnP devices found."
        return
    }

    foreach ($device in $devices) {
        if ($device.Status -eq 'Disabled') {
            Write-Verbose "Device '$($device.FriendlyName)' is already disabled. Skipped."
            continue
        }

        Write-Verbose "Disabling keyboard device '$($device.FriendlyName)'..."
        Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction Stop
        Write-Output "Device '$($device.FriendlyName)' disabled (takes effect immediately)."
    }
}

function Enable-KeyboardDevices {
    $devices  = @(Get-PnpDevice -Class Keyboard -ErrorAction SilentlyContinue)
    $restored = $false

    if ($devices.Count -eq 0) {
        Write-Warning "No keyboard PnP devices found."
        return
    }

    foreach ($device in $devices) {
        if ($device.Status -ne 'Disabled') {
            Write-Verbose "Device '$($device.FriendlyName)' is already enabled ($($device.Status)). Skipped."
            continue
        }

        $restored = $true
        Write-Verbose "Enabling keyboard device '$($device.FriendlyName)'..."
        Enable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction Stop
        Write-Output "Device '$($device.FriendlyName)' re-enabled."
    }

    if (-not $restored) {
        Write-Output "No disabled keyboard devices found. Nothing to re-enable."
    }
}

function Show-KeyboardStatus {
    Write-Host ""
    Write-Host "=== Keyboard drivers ===" -ForegroundColor Cyan

    foreach ($name in @('i8042prt', 'kbdhid')) {
        $prop = Get-ItemProperty -Path "$ServicesPath\$name" -Name Start -ErrorAction SilentlyContinue
        if ($null -eq $prop) {
            Write-Host ("  {0,-10}: not installed" -f $name) -ForegroundColor DarkGray
            continue
        }

        $startValue = [int]$prop.Start
        $label = switch ($startValue) {
            0 { 'Boot' }
            1 { 'System' }
            2 { 'Automatic' }
            3 { 'Manual' }
            4 { 'Disabled' }
            default { "Unknown ($startValue)" }
        }

        $color = if ($startValue -eq 4) { 'Yellow' } else { 'Green' }
        Write-Host ("  {0,-10}: {1} (Start={2})" -f $name, $label, $startValue) -ForegroundColor $color
    }

    $state = @()
    $state += Read-KeyboardState
    if ($state.Count -gt 0) {
        $summary = ($state | ForEach-Object { "$($_.Service)=$($_.OriginalStart)" }) -join ', '
        Write-Host ("  Restore state : {0}" -f $summary) -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "=== Keyboard devices ===" -ForegroundColor Cyan

    $devices = @()
    $devices += Get-KeyboardDevices
    if ($devices.Count -eq 0) {
        Write-Host '  No keyboard PnP devices found.' -ForegroundColor DarkGray
    }

    foreach ($device in $devices) {
        $color = if ($device.Status -eq 'Disabled') { 'Yellow' } else { 'Green' }
        Write-Host ("  {0} : {1}" -f $device.FriendlyName, $device.Status) -ForegroundColor $color
    }

    Write-Host ""
}
}

process {
    try {
        if ($List) {
            Show-KeyboardStatus
            return
        }

        $target = if ($Devices) { 'keyboard PnP devices' } else { 'keyboard driver services' }
        $action = if ($Enable) { 'restore' } else { 'disable' }

        $confirmed = $PSCmdlet.ShouldProcess($target, $action)
        if ($confirmed) {
            if (-not $WhatIfPreference) {
                $header = if ($Enable) { '=== Restoring keyboard ===' } else { '=== Disabling keyboard ===' }
                Write-Host $header -ForegroundColor Cyan
                Write-Host "Target: $target" -ForegroundColor Gray
                Write-Host ""

                if ($Devices) {
                    if ($Enable) {
                        Enable-KeyboardDevices
                    }
                    else {
                        Disable-KeyboardDevices
                    }
                }
                else {
                    if ($Enable) {
                        Enable-KeyboardDrivers
                        Enable-KeyboardDevices
                    }
                    else {
                        Disable-KeyboardDrivers
                    }
                }
            }
        }

        if ($confirmed -and -not $WhatIfPreference -and -not $Enable -and -not $Devices) {
            Write-Warning "Keyboard drivers are now disabled. The change takes effect after the next restart."
            Write-Warning "To restore input later, run: .\Set-KeyboardState.ps1 -Enable"
        }
    }
    catch {
        $operation = if ($List) { 'showing keyboard status' } elseif ($Enable) { 'restoring keyboard' } else { 'disabling keyboard' }
        Write-Error "Error ${operation}: $($_.Exception.Message)"
        throw
    }
}

end {
    Write-Verbose "Script execution completed."
}