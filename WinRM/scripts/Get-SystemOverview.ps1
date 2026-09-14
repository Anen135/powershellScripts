$ErrorActionPreference = 'Stop'
$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    [pscustomobject]@{
        Drive = $_.DeviceID
        SizeGB = [math]::Round($_.Size / 1GB, 2)
        FreeGB = [math]::Round($_.FreeSpace / 1GB, 2)
    }
})
[pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Manufacturer = $computer.Manufacturer
    Model = $computer.Model
    SerialNumber = $bios.SerialNumber
    OS = $os.Caption
    Version = $os.Version
    LastBoot = $os.LastBootUpTime
    MemoryGB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
    LoggedOnUser = $computer.UserName
    IPv4 = @((Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object PrefixOrigin -ne WellKnown).IPAddress)
    Disks = $disks
}
