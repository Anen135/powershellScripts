---
name: console-tui
description: Build or modify full-screen PowerShell interfaces in this repository with the local ConsoleTui module. Use for TUI rendering, keyboard navigation, modal prompts, or cancelable console operations; not for ordinary non-interactive scripts.
---

# ConsoleTui in this repository

Read `modules/ConsoleTu1/README.md` when changing a TUI. Import
`modules/ConsoleTu1/ConsoleTui.psd1` by a path relative to the entry script;
the directory spelling is intentionally `ConsoleTu1`.

Keep application state, domain operations and key bindings outside the module.
The module owns console state, differential frames, prompts and the input queue.

Preserve these invariants:

- Wrap every initialized UI loop in `try/finally` and call
  `Restore-ConsoleTui` in `finally`.
- Build a frame with `Start-ConsoleTuiFrame`, only exported formatting/write
  functions, and `Complete-ConsoleTuiFrame`.
- Derive page sizes from `Get-ConsoleTuiHeight`; the renderer reserves the
  last row and avoids the final physical column.
- Poll `Get-ConsoleTuiKey` with a short sleep when it returns `$null`.
- Use `Read-ConsoleTuiPrompt`, `Confirm-ConsoleTui`, or
  `Show-ConsoleTuiMessage` for modals. They invalidate the frame cache.
- Call `Restore-ConsoleTui` before handing the console to an interactive
  external command, then initialize again afterward.
- Keep credentials and backend-specific serialization out of ConsoleTui.

If the module public API changes, update both `FunctionsToExport` in the
manifest and `Export-ModuleMember` in the implementation, increment the module
version, validate the manifest, and parse/test with Windows PowerShell 5.1.
