# ConsoleTui 1.0

`ConsoleTui` is a reusable PowerShell 5.1 console UI module. It owns console
state, differential frame rendering, non-blocking keyboard input, prompts and
cancelable background-process screens. It has no dependency on Windows
Restore Manager, its catalog, JSON protocol or backend.

## Moving it to another project

Copy the whole `modules/ConsoleTui` directory into the target project. Keep
`ConsoleTui.psm1`, `ConsoleTui.psd1` and this document together. The module is
distributed under GPL-3.0-or-later; when distributing copied or modified code,
include the applicable license and preserve the notices in the source files.

A typical target layout is:

```text
MyUtility/
|-- modules/
|   `-- ConsoleTui/
|       |-- ConsoleTui.psd1
|       |-- ConsoleTui.psm1
|       `-- README.md
`-- Start-MyUtility.ps1
```

Import the manifest by a path relative to the calling script:

```powershell
$modulePath = Join-Path $PSScriptRoot 'modules\ConsoleTui\ConsoleTui.psd1'
Import-Module $modulePath -Force
```

Do not dot-source `ConsoleTui.psm1`. Importing the manifest keeps private
implementation functions out of the caller's command scope and validates the
minimum PowerShell version.

## Minimal application

The application owns its data, navigation state and key bindings. The module
owns the physical console and input queue.

```powershell
#requires -Version 5.1

$modulePath = Join-Path $PSScriptRoot 'modules\ConsoleTui\ConsoleTui.psd1'
Import-Module $modulePath -Force

$items = @('Diagnostics', 'Backups', 'Updates')
$cursor = 0

try {
    Initialize-ConsoleTui -Title 'My Utility'
    $running = $true
    $redraw = $true

    while ($running) {
        if ($redraw) {
            $width = Get-ConsoleTuiWidth
            Start-ConsoleTuiFrame
            Write-ConsoleTuiLine `
                -Text (Format-ConsoleTuiText ' My Utility ' $width) `
                -Foreground Black `
                -Background Cyan
            Write-ConsoleTuiLine

            for ($index = 0; $index -lt $items.Count; $index++) {
                $line = Format-ConsoleTuiText ("  " + $items[$index]) $width
                if ($index -eq $cursor) {
                    Write-ConsoleTuiLine $line Black Cyan
                }
                else {
                    Write-ConsoleTuiLine $line Gray Black
                }
            }

            Write-ConsoleTuiLine
            Write-ConsoleTuiLine ' Up/Down = navigate, Q = quit' DarkGray
            Complete-ConsoleTuiFrame
            $redraw = $false
        }

        $key = Get-ConsoleTuiKey
        if ($null -eq $key) {
            Start-Sleep -Milliseconds 10
            continue
        }

        switch ($key.Key) {
            'UpArrow'   { if ($cursor -gt 0) { $cursor-- } }
            'DownArrow' { if ($cursor -lt ($items.Count - 1)) { $cursor++ } }
            'Q'         { $running = $false }
        }
        $redraw = $true
    }
}
finally {
    Restore-ConsoleTui
}
```

Always call `Restore-ConsoleTui` from `finally`. Removing the module also
restores captured console state, but `finally` covers errors before normal
module cleanup.

## Public API

| Command | Purpose |
| --- | --- |
| `Initialize-ConsoleTui` | Capture console state, set the title and prepare input/render state. |
| `Restore-ConsoleTui` | Restore title, colors, cursor visibility and Ctrl+C handling. |
| `Get-ConsoleTuiWidth` | Return a safe drawing width that avoids the wrapping last column. |
| `Get-ConsoleTuiHeight` | Return the current console window height. |
| `Format-ConsoleTuiText` | Flatten, truncate and pad text to an exact width. |
| `Format-ConsoleTuiColumns` | Format values into fixed-width columns. |
| `Start-ConsoleTuiFrame` | Begin collecting a frame in memory. |
| `Write-ConsoleTuiLine` | Add a colored line to a frame, or write directly outside a frame. |
| `Complete-ConsoleTuiFrame` | Draw only rows that changed since the previous frame. |
| `Clear-ConsoleTuiSurface` | Clear the physical surface and invalidate the frame cache. |
| `Get-ConsoleTuiKey` | Poll for a key without blocking and coalesce navigation autorepeat. |
| `Clear-ConsoleTuiInputBacklog` | Drain queued navigation repeats before a modal operation. |
| `Read-ConsoleTuiPrompt` | Temporarily switch to a normal `Read-Host` prompt. |
| `Confirm-ConsoleTui` | Display a default-no confirmation prompt. |
| `Show-ConsoleTuiMessage` | Display a modal message using the configured application title. |
| `Invoke-ConsoleTuiProcess` | Run a child process with a spinner, elapsed time and Esc cancellation. |

`Complete-ConsoleTuiFrame` reserves the final console row and final physical
column. Build page sizes from `Get-ConsoleTuiHeight` with enough space for your
header and footer.

## Background processes

The process runner is deliberately transport-neutral:

```powershell
$result = Invoke-ConsoleTuiProcess `
    -FilePath 'powershell.exe' `
    -ArgumentList @('-NoProfile', '-File', '.\Do-Work.ps1') `
    -Title 'Refreshing data' `
    -Detail 'Inventory'

if ($result.Cancelled) {
    # Esc was pressed. On Windows the complete process tree is terminated.
}
elseif ($result.ExitCode -ne 0) {
    throw $result.StdErr
}
else {
    $data = $result.StdOut | ConvertFrom-Json
}
```

The returned object contains `Cancelled`, `ExitCode`, `StdOut` and `StdErr`.
The runner does not interpret output and does not treat a nonzero exit code as
an exception. Parsing JSON, checking an application protocol and deciding
which exit codes are successful remain responsibilities of the calling tool.

Arguments are passed as an array and quoted for `ProcessStartInfo`. Do not
assemble a single command line with user input. Standard output and error are
read asynchronously so a verbose child process cannot deadlock on a full pipe.

## Prompts and full-screen previews

`Read-ConsoleTuiPrompt`, `Confirm-ConsoleTui` and
`Show-ConsoleTuiMessage` invalidate the saved frame. The next normal frame is
therefore drawn completely. For a custom preview, call
`Clear-ConsoleTuiSurface`, write the preview, wait for a key, and let the normal
loop render again.

## Updating a copied module

Treat `ConsoleTui.psd1` as the module's public contract. When changing exported
commands, update both `FunctionsToExport` in the manifest and the
`Export-ModuleMember` list in `ConsoleTui.psm1`. Increment `ModuleVersion`, run
`Test-ModuleManifest`, parse the files with Windows PowerShell 5.1 and retest
the target utility's resize, prompt and Esc-cancellation flows.

The WRM integration in `tui/RestoreTui.ps1` is a working example of keeping an
application-specific adapter above the generic module. `Invoke-RestoreCliTui`
adds WRM command-line arguments and parses its JSON response; none of that
logic belongs in `ConsoleTui`.
