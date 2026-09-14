# WinRM Fleet Console add-ons

Add-ons are trusted PowerShell modules. They are not sandboxed and run with all
permissions of the current PowerShell process. An add-on may import modules,
start programs, access the network, install tools, mutate application state and
render any console UI. Install only code you trust.

Bundled add-ons live in this directory. Personal add-ons can be placed under
`%LOCALAPPDATA%\WinRMTui\addons`; a personal add-on with the same `Id` overrides
the bundled one. Press `R` in Fleet to rediscover manifests and refresh the top
tabs. `Tab` and `Shift+Tab` switch tabs without a separate add-on menu.

Each add-on directory contains `addon.psd1`:

```powershell
@{
    Id = 'my-addon'
    Name = 'My Add-on'
    Version = '1.0.0'
    Description = 'Does anything PowerShell can do.'
    MinimumHostVersion = '1.0.0'
    EntryModule = 'MyAddon.psm1'
    EntryCommand = 'Invoke-MyAddon'
}
```

The entry command accepts the unrestricted host context:

```powershell
function Invoke-MyAddon {
    param($Context)

    $targets = @(& $Context.GetTargets)
    $inventory = @(& $Context.GetInventory)
    $rootSessionState = $Context.ApplicationSessionState

    # ConsoleTui is already imported. The add-on owns the screen until return.
    # Use its public frame/input API or restore the TUI and launch another UI.
    # Context.TabText contains the shared top tab bar. Return a Navigation value
    # of Home, NextTab or PreviousTab when handing control back to the host.
}
Export-ModuleMember -Function Invoke-MyAddon
```

The context exposes paths, the live root `SessionState`, current state getters
and setters, selected-target resolution, credential prompting, persistence,
audit, modal prompts and input draining. Access to `ApplicationSessionState`
also allows a trusted add-on to inspect or replace any root application variable.
`Context.State` is a host-owned hashtable that survives tab switches. Store sessions
and UI state there. An optional `State.Dispose` scriptblock is called when the root
application exits, allowing the add-on to close sessions and background resources.
