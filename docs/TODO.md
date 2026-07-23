# TODO — Pre-Release Standardization Plan

> **Status:** Planned — do not execute until instructed.
> This document captures the pre-release standardization work needed before shipping.

---

## Objective

Bring all 18 PowerShell scripts to a **consistent format** before merging `develop` → `main` and tagging a release. The goal is a unified "common view" so every script looks, feels, and behaves like part of the same collection.

---

## Standard Template

Every script should conform to this structure:

```powershell
<#
.SYNOPSIS
    One-line description.

.DESCRIPTION
    Detailed description of the script's purpose and behavior.

.PARAMETER ParamName
    Description of each parameter.

.EXAMPLE
    .\<ScriptName>.ps1 -Param1 value

.NOTES
    Version: X.Y
    Author: Anen
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ParamName,

    [Parameter(Mandatory = $false)]
    [switch]$SwitchParam
)

begin {
    Write-Verbose "Initializing..."
    # Setup code
}

process {
    try {
        # Main logic
    }
    catch {
        Write-Error "Error: $($_.Exception.Message)"
        exit 1
    }
}

end {
    Write-Verbose "Script completed."
}
```

---

## Tasks

### 1. 🔴 Populate CHANGELOG.md
- **File:** `docs/CHANGELOG.md` (currently empty — 0 bytes)
- **Action:** Write a changelog summarizing all changes since the last state on `main`:
  - English translation of all scripts
  - New scripts added (Analyze-MP4, Optimize-MP4, New-SymlinkMigration, Zip-Converter, VPN-Bypass-Manager)
  - README.md and LICENSE.txt addition
  - Refactoring and bug fixes

### 2. 🔴 Fix ApiTool.ps1 Encoding
- **File:** `ApiTool.ps1`
- **Issue:** File is saved as **UTF-16 LE** (shows null bytes between characters)
- **Action:** Re-encode as **UTF-8 with BOM** (PowerShell standard)

### 3. 🟢 Add Missing Help Blocks (6 scripts) — ✅ DONE
Scripts that currently have **no comment-based help** at all:

| Script | Action | Status |
|--------|--------|--------|
| `Analyze-MP4.ps1` | Add `<# .SYNOPSIS .DESCRIPTION .PARAMETER .NOTES #>` | ✅ Already has full help block |
| `ApiTool.ps1` | Add `<# .SYNOPSIS .DESCRIPTION .PARAMETER .NOTES #>` | ✅ Already has full help block |
| `Optimize-MP4.ps1` | Add `<# .SYNOPSIS .DESCRIPTION .PARAMETER .NOTES #>` | ✅ Already has full help block |
| `touch.ps1` | Add `<# .SYNOPSIS .DESCRIPTION .PARAMETER .NOTES #>` | ✅ Already has full help block |
| `rd.ps1` | Add `<# .SYNOPSIS .DESCRIPTION .PARAMETER .NOTES #>` | ✅ Already has full help block |
| `Zip-Converter.ps1` | Add `<# .SYNOPSIS .DESCRIPTION .PARAMETER .NOTES #>` | ✅ Already has full help block |

### 4. 🟢 Upgrade Minimal Headers (3 scripts) — ✅ DONE
Scripts that had only `#` line comments instead of proper help:

| Script | Current | Action | Status |
|--------|---------|--------|--------|
| `CleanUpCache.ps1` | Just `# CleanUpCache.ps1` | Replace with full `<# #>` help block | ✅ Already has full help block |
| `VPN-Bypass-Manager.ps1` | Simple `#` header block | Convert to proper comment-based help | ✅ Already has full help block |
| `pathedit.ps1` | `# === PATH Editor ===` | Add full `<# #>` help block | ✅ Already has full help block |

### 5. 🟢 Unify Author Field — ✅ DONE
All 18 scripts already have `Author: Anen` (verified by reading every file).

| Value | Scripts | Status |
|-------|---------|--------|
| `Author: Anen` | AddToStartup, Clean-UserPath, Create-TrashFolder, Get-CurrentWifiPassword, Get-DirectorySize, init-github, MergeFiles, RemoveFromStartup, VPN-Bypass-Manager | ✅ All already `Anen` |
| `Author: System Administrator` | Clean-UserPath, RemoveFromStartup | ✅ Already changed to `Anen` |
| `Author: Anen135` | VPN-Bypass-Manager | ✅ Already changed to `Anen` |
| `Author:  Anen` (double space) | Create-TrashFolder | ✅ Already fixed to single space |

**No changes needed — all scripts already unified to `Author: Anen`.**

### 6. 🟡 Add `[CmdletBinding()]` (10 scripts)
Scripts currently **missing** `[CmdletBinding()]`:

- Analyze-MP4.ps1
- CleanUpCache.ps1
- Create-TrashFolder.ps1
- Optimize-MP4.ps1
- pathedit.ps1
- rd.ps1
- touch.ps1
- VPN-Bypass-Manager.ps1
- Zip-Converter.ps1
- ApiTool.ps1 (function-level)

**Note:** Scripts that are purely function libraries (ApiTool, touch, Optimize-MP4, Zip-Converter) should have `[CmdletBinding()]` on their function declarations instead.

### 7. 🟢 Standardize Output Patterns - ✅ DONE
**Rule:** Use `Write-Output` for data, `Write-Host` only for display/colored progress messages, and `Write-Error` / `Write-Warning` for error conditions.

Scripts needing review:
- CleanUpCache.ps1 — uses all `Write-Host` for status
- rd.ps1 — uses `Write-Host` for everything
- VPN-Bypass-Manager.ps1 — uses `Write-Host` for errors
- Analyze-MP4.ps1 — uses `Write-Host` for all output

### 8. 🟡 Align Error Handling
**Standard:** `try/catch` → `Write-Error` + `exit 1` for all;

### 9. ⚪ Normalize Version Format
**Standard:** `Version: X.Y` (no extra text after the number)

Scripts to fix:
- `Get-CurrentWifiPassword.ps1` — currently: `Version: 2.3` ✅ Already correct
- `Get-DirectorySize.ps1` — has `License: MIT` line (remove or move for consistency)

### 10. ⚪ Review Function Naming
**Standard:** `Verb-Noun` PascalCase

Scripts to review:
- `pathedit.ps1` — all functions are PascalCase ✅
- `rd.ps1` — `Log`, `Normalize-Path` — `Log` should be `Write-Log` to follow convention
- `VPN-Bypass-Manager.ps1` — `Add-Bypass`, `Remove-Bypass` ✅, `Get-DefaultRouteInfo` ✅

### 11. ⚪ Standardize Parameter Validation
Add validation attributes where appropriate across all scripts:
- `[ValidateNotNullOrEmpty()]` for mandatory strings
- `[ValidateScript()]` for path validation
- `[ValidateSet()]` where applicable

---

## Post-Standardization Steps (Release)

After all above tasks are complete:

1. ✅ Verify all scripts parse without syntax errors
2. 🔲 Populate CHANGELOG.md
3. 🔲 Create version tag (e.g., `v1.0.0`)
4. 🔲 Merge `develop` → `main`
5. 🔲 Push with tags

---

## Quick-Reference: Script Status Matrix

| # | Script | Help Block | CmdletBinding | begin/proc/end | Author | Notes |
|---|--------|-----------|---------------|----------------|--------|-------|
| 1 | AddToStartup.ps1 | ✅ | ✅ | ✅ | Anen | — |
| 2 | Analyze-MP4.ps1 | ✅ | ❌ | ❌ | Anen | Flat code |
| 3 | ApiTool.ps1 | ✅ | ❌ | ❌ | Anen | UTF-16 encoding! |
| 4 | Clean-UserPath.ps1 | ✅ | ✅ | ✅ | Anen | — |
| 5 | CleanUpCache.ps1 | ✅ | ❌ | ❌ | Anen | — |
| 6 | Create-TrashFolder.ps1 | ✅ | ❌ | ❌ | Anen | — |
| 7 | Get-CurrentWifiPassword.ps1 | ✅ | ✅ | ✅ | Anen | Fix version format |
| 8 | Get-DirectorySize.ps1 | ✅ | ✅ | ✅ | Anen | License field |
| 9 | init-github.ps1 | ✅ | ✅ | ✅ | Anen | — |
| 10 | MergeFiles.ps1 | ✅ | ✅ | ✅ | Anen | — |
| 11 | New-SymlinkMigration.ps1 | ✅ | ✅ | ❌ | Anen | Error handling |
| 12 | Optimize-MP4.ps1 | ✅ | ❌ | ❌ | Anen | Function only |
| 13 | pathedit.ps1 | ✅ | ❌ | ❌ | Anen | TUI app |
| 14 | rd.ps1 | ✅ | ❌ | ❌ | Anen | — |
| 15 | RemoveFromStartup.ps1 | ✅ | ✅ | ✅ | Anen | — |
| 16 | touch.ps1 | ✅ | ❌ | ❌ | Anen | Function only |
| 17 | VPN-Bypass-Manager.ps1 | ✅ | ❌ | ❌ | Anen | — |
| 18 | Zip-Converter.ps1 | ✅ | ❌ | ❌ | Anen | Function only |

