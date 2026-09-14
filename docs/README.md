PowerShell scripts for:
- Windows system administration
- automation
- developer workflows
- CLI utilities
- file management
- network troubleshooting

# PowerShell Scripts Collection

A collection of useful PowerShell scripts for Windows system administration, file management, development workflows, and daily productivity.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)
![Platform](https://img.shields.io/badge/platform-Windows-blue)
![License](https://img.shields.io/github/license/Anen135/powershellScripts)
![Stars](https://img.shields.io/github/stars/Anen135/powershellScripts)

## 📋 Table of Contents

- [System Utilities](#system-utilities)
- [File Operations](#file-operations)
- [Development Tools](#development-tools)
- [Navigation & UI](#navigation--ui)
- [Network](#network)
- [Getting Started](#getting-started)
- [Usage Examples](#usage-examples)

---

## System Utilities

### WinRM Fleet Console
Full-screen fleet manager with network discovery, persistent inventory,
groups/tags, filtering, blacklist rules, parallel PowerShell execution,
interactive sessions, upload/download collection, power actions and JSONL
audit. Credentials are retained in memory only.

```powershell
.\WinRM\Start-WinRMTui.ps1
```

See [`WinRM/README.md`](../WinRM/README.md) for the keyboard map, storage
layout, filters, security model and non-interactive module API.

### Find-WinRM.ps1
Find reachable WinRM endpoints using an IPv4 wildcard or CIDR range. Probes HTTP/HTTPS in parallel without requiring ping or administrator privileges.

```powershell
.\WinRM\Find-WinRM.ps1 -IpMask '192.168.1.*' | Format-Table -AutoSize
.\WinRM\Find-WinRM.ps1 '10.0.0.0/24' -TimeoutMs 1500 -ThrottleLimit 32 |
    Export-Csv .\winrm.csv -NoTypeInformation -Encoding UTF8
```

`WSManConfirmed` means the endpoint returned a WS-Management Identify response; it does not verify login permissions. `AuthenticationRequired` and `TcpOpenUnverified` indicate candidates, not confirmed WinRM services. HTTPS certificate errors appear in `Detail`. Default ports are 5985/5986; override with `-HttpPort` / `-HttpsPort`. Closed ports are omitted. CIDR excludes network/broadcast addresses except for /31 and /32; wildcards include all matching addresses. Ranges are limited to 65,536 addresses by default (`-MaxAddresses`).

Use `-CheckConnection` to open a real PSSession and collect inventory. `ConnectAs` is the requested account (the current Windows account by default); `AuthenticatedAs` is the identity reported by the remote session. `LoggedOnUser` is the primary interactive user from `Win32_ComputerSystem`, not a list of all RDP sessions. DNS names are provisional; after login, `ComputerName` is read from the remote computer. `NameSource` identifies the source.

```powershell
$cred = Get-Credential 'OFFICE\admin'
$pcs = .\WinRM\Find-WinRM.ps1 '192.168.1.*' -CheckConnection -Credential $cred -SavePath .\office.csv
$pcs | Format-Table Address, ComputerName, ConnectAs, AuthenticatedAs, Status, UptimeDays, FreeSpaceGB -AutoSize
```

Inventory also includes `OS`, `OSVersion`, `LastBootTime` (UTC), and free space on C: in GiB (`FreeSpaceGB`). `ConnectionStatus` records login separately from `DiscoveryStatus`; `Status` reports the overall result. Login/inventory statuses include `Connected`, `AccessDenied`, `AuthenticationError`, `CertificateError`, `Timeout`, `ConnectionFailed`, and `InventoryFailed`. The last means login succeeded but inventory collection failed. `Detail` retains the underlying error. Unrecognized/localized connection errors fall back to `ConnectionFailed`.

Keep `WinRM.Tools.psm1` beside both scripts. `-TimeoutMs` controls discovery I/O; `-OpenTimeoutMs` controls session opening; `-CommandTimeoutSec` limits each remote identity/inventory/command job. These are separate stages, not a total scan deadline. `-SkipDns` uses IP addresses directly. Otherwise a DNS name is used for authentication only if a forward lookup contains the scanned IP, and saved names are re-resolved before connection.

No passwords are written to the CSV. Pass `-Credential` again when using saved inventory; a saved `ConnectAs` does not select credentials. The scripts preserve TLS validation and do not edit TrustedHosts. Windows imposes additional authentication requirements for [remoting by IP address or in a workgroup](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_remote_troubleshooting); failures are reported in the result.

### Invoke-OfficeComputer.ps1
Use saved inventory or pipeline objects to select computers and run inventory, a PowerShell command, a restart, or a shutdown. CSV input requires `-ComputerName` (exact name/IP), `-Select` (numbered console picker), or explicit `-All`. Pipeline input can be filtered with `Where-Object`. One endpoint per IP is selected: previously connected first, then confirmed WS-Management, then HTTPS. Commands are not retried on another endpoint.

```powershell
# Select computers interactively and collect fresh inventory, without scanning.
.\Invoke-OfficeComputer.ps1 -InventoryPath .\office.csv -Select -Credential $cred `
    -Action Inventory -SavePath .\office-updated.csv

# Run a command on selected machines. Use arguments for local values.
$results = .\Invoke-OfficeComputer.ps1 -InventoryPath .\office.csv `
    -ComputerName PC01,PC02 -Credential $cred -Action Command `
    -ScriptBlock { param($ServiceName) Get-Service -Name $ServiceName } -ArgumentList Spooler
$results | Format-Table ComputerName, Status, Detail -AutoSize
$results | ForEach-Object { $_.Output }

# Preview the exact restart targets, then run with a separate confirmation.
.\Invoke-OfficeComputer.ps1 -InventoryPath .\office.csv -ComputerName PC01,PC02 -Action Restart -WhatIf
.\Invoke-OfficeComputer.ps1 -InventoryPath .\office.csv -ComputerName PC01,PC02 `
    -Action Restart -Credential $cred -DelaySeconds 60

# Shutdown uses the same selection and confirmation flow.
.\Invoke-OfficeComputer.ps1 -InventoryPath .\office.csv -Select -Action Shutdown -Credential $cred

# Refresh all saved computers explicitly, without repeating discovery.
.\Invoke-OfficeComputer.ps1 -InventoryPath .\office.csv -All -Action Inventory `
    -Credential $cred -ThrottleLimit 16 -SavePath .\office-updated.csv
```

`-WhatIf` opens no sessions and creates no log files. Built-in Restart/Shutdown always require interactive confirmation with the complete target list, even with `-Confirm:$false`. The default delay is 60 seconds (minimum 30). Windows [forces applications to close when a nonzero shutdown delay expires](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/shutdown); the confirmation explains this. `Scheduled` means Windows accepted the request, not that the restart/shutdown completed. Arbitrary `-ScriptBlock` commands execute as supplied and are not inspected for power actions. Local variables and `$using:` are not supported inside these script blocks; use `param(...)` with `-ArgumentList`.

Every management run writes JSON Lines to `./winrm-logs/<timestamp>-<run-id>.jsonl`, or `-LogPath`. The log is opened before remote work and contains the selected targets, requested/actual identities, one result per computer, command output, errors, and run start/end events. Credentials and script text are not serialized; command output itself may contain sensitive data. Interrupted runs record unfinished targets with unknown outcomes. A command timeout stops the local job and closes the session, but cannot roll back effects already produced remotely. Native command exit codes must be checked explicitly inside your script block (as the built-in power actions do).

`-SavePath` on the manager writes a new CSV containing only the selected, refreshed computers. It does not merge them into the original inventory. `Output` contains structured command results; the JSON log limits serialization depth to 12.

Regression checks (loopback fixtures and mocked remote actions; no office computers are changed):

```powershell
.\tests\Test-OfficeWinRM.ps1
```

### AddToStartup.ps1
Add an application to Windows startup (HKCU registry).

```
.\AddToStartup.ps1 -AppName "MyApp" -AppPath "C:\Path\to\app.exe"
```

### RemoveFromStartup.ps1
Remove an application from Windows startup.

```
.\RemoveFromStartup.ps1 -AppName "MyApp"
```

### Clean-UserPath.ps1
Cleans the user `PATH` environment variable by removing non-existent directory entries. Creates a JSON backup on the Desktop before applying changes.

```
.\Clean-UserPath.ps1 -Verbose
```

### pathedit.ps1
Interactive TUI editor for viewing and modifying `PATH` environment variables. Supports:
- Navigating entries with arrow keys
- Editing individual entries with `Enter`
- Deleting entries with `Delete` (with confirmation)
- Saving changes to User scope with `S`
- Adding current directory with `-Current` switch
- Searching for a path with `-Find` switch

```
.\pathedit.ps1                  # Open interactive editor
.\pathedit.ps1 -Current         # Add current dir to PATH
.\pathedit.ps1 -Find "C:\Tools" # Check if path is in PATH
```

### Get-DirectorySize.ps1
Enhanced `DIR` command replacement with rich features:
- Recursive scanning (`-Recurse` / `/S`)
- Sort by name, size, extension, date, or folders first (`-Sort`)
- Bare format output (`-BareFormat` / `/B`)
- Owner display (`-Owner` / `/Q`)
- Attribute filtering (`-Attributes` / `/A`)
- Unit selection (MB/GB)

```
.\Get-DirectorySize.ps1 -Path "C:\Temp" -Unit GB -Sort S -Recurse
```
### Set-KeyboardState.ps1
Disables or re-enables keyboard input on the local machine. Disarms the PS/2
(`i8042prt`) and USB/HID (`kbdhid`) keyboard kernel drivers (persistent, effective after
reboot) or the connected keyboard PnP devices immediately. Requires Administrator
privileges.

```powershell
.\Set-KeyboardState.ps1                      # Disable keyboard drivers (after reboot)
.\Set-KeyboardState.ps1 -Driver kbdhid       # Disable only the USB/HID keyboard driver
.\Set-KeyboardState.ps1 -Devices             # Disable keyboard devices immediately
.\Set-KeyboardState.ps1 -Enable              # Restore keyboard input
.\Set-KeyboardState.ps1 -List                # Show current status
```

---

## File Operations

### touch.ps1
Unix-like `touch` command — creates empty files or updates timestamps on existing ones.

```powershell
touch newfile.txt
touch file1.txt, file2.txt
```

### Zip-Converter.ps1
Converts ZIP archives to RAR format using WinRAR with maximum compression (m5).

```powershell
Convert-ZipToRar -ZipFile "archive.zip"
Convert-ZipToRar -ZipFile "archive.zip" -OutputFile "output.rar"
```

### MergeFiles.ps1
Merges all text files from a folder into a single output file, with filename delimiters. Supports wildcard and regex filtering.

```
.\MergeFiles.ps1 -InputFolder ".\logs" -Filter "*.log" -OutputFile ".\all_logs.txt"
.\MergeFiles.ps1 -InputFolder ".\data" -RegexFilter "^2024-.*\.txt$" -OutputFile ".\2024_data.txt"
```

### Create-TrashFolder.ps1
Generates test junk data — creates folders filled with random binary files of configurable sizes. Useful for testing disk space, backup tools, or performance.

```
.\Create-TrashFolder.ps1                                   # Default: 50 folders, 100 files each, 512KB max
.\Create-TrashFolder.ps1 -FoldersCount 20 -FilesPerFolder 200 -MaxFileSizeKB 1024
.\Create-TrashFolder.ps1 -Path "D:\TestData" -Recreate
```

### CleanUpCache.ps1
Deletes files and folders listed in a text file (`cache.txt` by default). Supports `-WhatIf` for dry-run preview.

```
.\CleanUpCache.ps1                                    # Use paths from cache.txt
.\CleanUpCache.ps1 -PathsFile "my_cache.txt" -WhatIf  # Preview only
```

### rd.ps1
Robocopy-based directory mover. Moves the contents of a source folder to a destination, then replaces the source with a symbolic link. Includes rollback support.

```
.\rd.ps1 -Source "D:\LargeData" -Destination "E:\Archive"
.\rd.ps1 -Source "D:\LargeData" -Destination "E:\Archive" -DryRun
.\rd.ps1 -Source "D:\LargeData" -Destination "E:\Archive" -Rollback
```

---

## Development Tools

### init-github.ps1
One-command GitHub repository initialization: creates a local git repo, stages files, commits, creates a GitHub repo via `gh` CLI, and pushes.

```
.\init-github.ps1 -RepoName "my-new-project"
.\init-github.ps1 -RepoName "private-project" -Private
```

### ApiTool.ps1
Convenience function for sending HTTP requests with session/cookie persistence and formatted output.

```powershell
# Load the function
. .\ApiTool.ps1

# Usage
req -Uri "https://api.example.com/data"
req -Uri "https://api.example.com/login" -Method POST -Body @{user="admin"; pass="123"}
req -Uri "https://api.example.com/data" -ShowHeaders
req -Uri "" -ClearSession              # Clear session cookies
```

---

## Navigation & UI

### DirNav.ps1
Interactive console-based directory navigator with keyboard controls.
- **Arrow keys**: Navigate (cyclic scrolling)
- **Enter**: Open file/folder
- **S / Backspace**: Go to parent directory
- **Del** (×2): Delete empty folder or file
- **Q**: Search files by mask (recursive)
- **Esc**: Exit (or exit search mode)

```
.\DirNav.ps1
```

---

## Network

### Get-CurrentWifiPassword.ps1
Displays the SSID and password of the currently connected Wi-Fi network using `netsh` without admin rights.

```
.\Get-CurrentWifiPassword.ps1
```

### VPN-Bypass-Manager.ps1
Manages persistent network routes to bypass VPN for specific IPs/domains. Uses `New-NetRoute` instead of legacy `route.exe`. Requires Administrator privileges.

```
.\VPN-Bypass-Manager.ps1 -Add -Target google.com
.\VPN-Bypass-Manager.ps1 -Add -Target 8.8.8.8
.\VPN-Bypass-Manager.ps1 -Remove -Target google.com
.\VPN-Bypass-Manager.ps1 -List
```

### Init-WinRM.ps1
Prepares a Windows machine for PowerShell Remoting: disables the blank-password restriction for local accounts, sets all active network profiles to Private, enables PowerShell Remoting, and configures the WinRM service to start automatically. Requires Administrator privileges.

```
.\Init-WinRM.ps1
.\Init-WinRM.ps1 -Verbose          # Detailed progress output
```

### RemoveWinRmLimit.ps1
Disables the blank-password restriction for local accounts used for remote logon (WinRM). Standalone version of the first step of `Init-WinRM.ps1`. Requires Administrator privileges.

```
.\RemoveWinRmLimit.ps1
.\RemoveWinRmLimit.ps1 -Verbose    # Detailed progress output
```
---

## Getting Started

### Prerequisites
- Windows 10 / 11 or Windows Server 2016+
- PowerShell 5.1 or higher (PowerShell 7+ recommended)
- Some scripts require Administrator privileges
- `Zip-Converter.ps1` requires WinRAR installed
- `init-github.ps1` requires Git and GitHub CLI (`gh`)

### Installation

Clone the repository or copy the scripts to your preferred location:

```powershell
git clone https://github.com/Anen135/powershellScripts.git
```

To auto-load scripts on PowerShell startup, add the following lines to your PowerShell profile (`$PROFILE`):

```powershell
. "C:\Program Files\WindowsPowerShell\Scripts\StartUp.ps1"
```

Or selectively dot-source only the scripts you need:

```powershell
. "C:\path\to\scripts\ApiTool.ps1"
. "C:\path\to\scripts\touch.ps1"
```

### Execution Policy
If you encounter execution policy restrictions, run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

---

## Usage Examples

```powershell
# Quick file creation
touch mynotes.txt

# Send an API request
req -Uri "https://api.github.com/repos/Anen135/powershellScripts"

# Merge log files
.\MergeFiles.ps1 -InputFolder ".\logs" -Filter "*.log" -OutputFile ".\all_logs.txt"

# Get current Wi-Fi password
.\Get-CurrentWifiPassword.ps1

# Clean up non-existent PATH entries
.\Clean-UserPath.ps1

# Browse directories interactively
.\DirNav.ps1

# Init and push a new GitHub repo
.\init-github.ps1 -RepoName "my-project"

# Generate 1GB of test junk data
.\Create-TrashFolder.ps1 -FoldersCount 10 -FilesPerFolder 200 -MaxFileSizeKB 1024
```

---

## License

This project is licensed under the GNU General Public License v3.0.

## Author

**Anen** — [GitHub](https://github.com/Anen135)

---

⭐ If you find these scripts useful, consider giving the repo a star!
