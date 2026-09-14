Get-Process |
    Sort-Object WorkingSet64 -Descending |
    Select-Object -First 20 Name, Id, CPU, @{ Name = 'MemoryMB'; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 1) } }
