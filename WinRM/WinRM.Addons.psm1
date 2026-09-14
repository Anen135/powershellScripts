#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-WinRMAddon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Root,
        [version]$HostVersion = '1.0.0'
    )

    $addons = [ordered]@{}
    foreach ($addonRoot in $Root) {
        if (-not (Test-Path -LiteralPath $addonRoot -PathType Container)) { continue }
        foreach ($manifestPath in @(Get-ChildItem -LiteralPath $addonRoot -Filter 'addon.psd1' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)) {
            $directory = $manifestPath.Directory.FullName
            try {
                $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath.FullName -ErrorAction Stop
                foreach ($required in @('Id', 'Name', 'Version', 'EntryModule', 'EntryCommand')) {
                    if (-not $manifest.ContainsKey($required) -or [string]::IsNullOrWhiteSpace([string]$manifest[$required])) {
                        throw "Missing required manifest field: $required"
                    }
                }
                $entryPath = [IO.Path]::GetFullPath((Join-Path $directory ([string]$manifest.EntryModule)))
                if (-not (Test-Path -LiteralPath $entryPath -PathType Leaf)) { throw "Entry module not found: $entryPath" }
                $minimumVersion = if ($manifest.ContainsKey('MinimumHostVersion')) { [version]$manifest.MinimumHostVersion } else { [version]'1.0.0' }
                $status = if ($minimumVersion -gt $HostVersion) { 'Incompatible' } else { 'Ready' }
                $detail = if ($status -eq 'Incompatible') { "Requires host $minimumVersion; current host is $HostVersion." } else { '' }
                $addon = [pscustomobject][ordered]@{
                    Id = [string]$manifest.Id
                    Name = [string]$manifest.Name
                    Version = [string]$manifest.Version
                    Description = $(if ($manifest.ContainsKey('Description')) { [string]$manifest.Description } else { '' })
                    MinimumHostVersion = $minimumVersion.ToString()
                    EntryModule = [string]$manifest.EntryModule
                    EntryCommand = [string]$manifest.EntryCommand
                    Directory = $directory
                    ManifestPath = $manifestPath.FullName
                    EntryPath = $entryPath
                    Status = $status
                    Detail = $detail
                }
            }
            catch {
                $fallbackId = $manifestPath.Directory.Name
                $addon = [pscustomobject][ordered]@{
                    Id = $fallbackId; Name = $fallbackId; Version = '?'; Description = ''
                    MinimumHostVersion = ''; EntryModule = ''; EntryCommand = ''; Directory = $directory
                    ManifestPath = $manifestPath.FullName; EntryPath = ''; Status = 'Invalid'; Detail = $_.Exception.Message
                }
            }
            # Roots later in the list override bundled add-ons with the same Id.
            $addons[[string]$addon.Id] = $addon
        }
    }
    @($addons.Values | Sort-Object Name, Id)
}

function Import-WinRMAddon {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Addon)

    if ($Addon.Status -ne 'Ready') { throw "Add-on '$($Addon.Name)' is $($Addon.Status): $($Addon.Detail)" }
    $module = Import-Module -Name $Addon.EntryPath -Force -PassThru -DisableNameChecking -ErrorAction Stop
    if (-not $module.ExportedCommands.ContainsKey([string]$Addon.EntryCommand)) {
        throw "Add-on '$($Addon.Name)' does not export command '$($Addon.EntryCommand)'."
    }
    [pscustomobject][ordered]@{
        Addon = $Addon
        Module = $module
        Command = $module.ExportedCommands[[string]$Addon.EntryCommand]
    }
}

Export-ModuleMember -Function Get-WinRMAddon, Import-WinRMAddon
