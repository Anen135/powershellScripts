# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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