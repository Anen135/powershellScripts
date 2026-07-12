function touch {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string[]]$Path,
        [datetime]$ReferenceTime = (Get-Date)
    )
    
    try {
        foreach ($p in $Path) {
            if (Test-Path $p) {
                $item = Get-Item $p
                $item.LastWriteTime = $ReferenceTime
                $item.LastAccessTime = $ReferenceTime
            } else {
                New-Item -Path $p -ItemType File -Force | Out-Null
            }
        }
    } catch {
        Write-Error "An error occurred while processing the path: $_"
    }
}