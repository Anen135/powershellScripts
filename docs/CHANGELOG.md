# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-09-06

### Changed
- `disable-keyboard.ps1` renamed to `Set-KeyboardState.ps1` and rewritten into
  a full-featured utility:
  - Added comment-based help block and `#Requires -RunAsAdministrator`
  - Now disables both keyboard kernel drivers (`i8042prt` — PS/2 and
    `kbdhid` — USB/HID), not only `i8042prt`
  - New parameters: `-Driver` (driver selection), `-Devices` (immediate PnP
    device mode), `-Enable` (restore), `-List` (status view)
  - Original driver startup values are persisted to a JSON state file
    (`%ProgramData%\Set-KeyboardState\state.json`) so `-Enable` restores them
    exactly
  - Supports `-Verbose`, `-WhatIf`, `-Confirm`
  - Standard error handling (`try/catch` + `Write-Error` + `throw`) and
    English-only output
## [1.2.0] - 2026-09-04

### Added
- New WinRM management scripts:
  - `Init-WinRM.ps1` — Configures WinRM for PowerShell Remoting (disables the
    blank-password restriction for local accounts, sets network profiles to
    Private, enables PowerShell Remoting, and configures the WinRM service to
    start automatically)
  - `RemoveWinRmLimit.ps1` — Standalone utility that disables the blank-password
    restriction for local accounts used for remote logon
- Both new scripts follow the current standards: comment-based help, `-Verbose`
  support, and `Write-Verbose` output throughout

## [1.1.0] - 2026-08-08

### Changed
- `Select-File.ps1`: Refactored and standardized:
  - Added comment-based help block
  - Added `[ValidateScript()]` for path validation
  - Removed redundant `Resolve-Path` in `Get-TargetFiles` (path already resolved by caller)
  - Removed redundant `-Force:$false` on `Copy-Item`
  - Replaced `exit 0`/`exit 1` with `return`/`throw` pattern
  - Added `Write-Verbose` support throughout the script
  - Translated all Russian output messages and comments to English

## [1.0.0] - 2026-07-23

### Added
- **New scripts**: `Optimize-MP4.ps1`, `Zip-Converter.ps1`, `New-SymlinkMigration.ps1`
- Parameter validation for mandatory inputs across multiple scripts
- `-Content` and `-Override` parameters to `touch.ps1`
- Documentation files: `docs/README.md`, `docs/LICENSE.txt`, `docs/CHANGELOG.md`, `docs/TODO.md`, `docs/NOTE.md`, `docs/STANDART.md`
- `v1.0.0` version tag (see `docs/TODO.md`)

### Changed
- **Full standardization** of all 18 PowerShell scripts to a consistent format:
  - Unified comment-based help blocks at the start of every script
  - Consistent header section with description, parameters, examples, notes
- **Error handling overhaul** across all scripts:
  - Replaced `exit 1` with `Write-Error` + `throw` pattern for non-terminating errors
  - Replaced `Write-Host` for errors with proper `Write-Error` calls
  - Standardized try/catch blocks with `Write-Error` + `throw`
- **Translation**: Converted all Russian-language comments and output messages to English
- `Analyze-MP4.ps1`: Renamed `Run-Probe` to `Start-Probe` for clarity; updated output formatting
- `New-SymlinkMigration.ps1`: Renamed logging function to `Write-Log`; improved error messages
- `Get-DirectorySize.ps1`: Removed License line for standardization
- `VPN-Bypass-Manager.ps1`: Refactored to use `NETTCPIP` module (`New-NetRoute`) instead of legacy `route.exe`
- `pathedit.ps1`: Enhanced interactive TUI editor with search/find capabilities

### Fixed
- Corrected error messages in `New-SymlinkMigration.ps1`
- `touch.ps1`: Hotfix for edge cases
- Consistent `-Verbose` support now available across all scripts

### Security
- Validation attributes (`[ValidateNotNullOrEmpty()]`, `[ValidateScript()]`, `[ValidateSet()]`) added where appropriate

## [0.1.0] - 2025-01-01

### Added
- Initial collection of PowerShell utility scripts:
  - `AddToStartup.ps1` / `RemoveFromStartup.ps1` — Startup management
  - `Clean-UserPath.ps1` — PATH environment variable cleaner
  - `pathedit.ps1` — Interactive PATH editor
  - `Get-DirectorySize.ps1` — Enhanced `DIR` replacement
  - `touch.ps1` — Unix-like file creation
  - `MergeFiles.ps1` — Text file merger
  - `Create-TrashFolder.ps1` — Test junk data generator
  - `CleanUpCache.ps1` — Cache file cleaner
  - `rd.ps1` — Robocopy-based directory mover
  - `init-github.ps1` — One-command GitHub repo init
  - `ApiTool.ps1` — HTTP request utility
  - `DirNav.ps1` — Interactive directory navigator
  - `Get-CurrentWifiPassword.ps1` — Wi-Fi password viewer
  - `VPN-Bypass-Manager.ps1` — VPN route manager
  - `Analyze-MP4.ps1` — MP4 file analyzer
  - `StartUp.ps1` — Auto-load script
  - `program.ps1` — Utility runner
  - `cache.txt` — Cache paths list