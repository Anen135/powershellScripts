# PowerShell Scripts Collection

A collection of useful PowerShell scripts for Windows system administration, file management, development workflows, and daily productivity.

[![GitHub](https://img.shields.io/badge/GitHub-Anen135/powershellScripts-blue?logo=github)](https://github.com/Anen135/powershellScripts)

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

This project is licensed under the GPL3 License.

## Author

**Anen** — [GitHub](https://github.com/Anen135)

---

⭐ If you find these scripts useful, consider giving the repo a star!