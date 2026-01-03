param([string]$Path)
$target = $Path 
$empty = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "Empty_$(Get-Random)")

robocopy $empty.FullName $target /MIR /MT:16 /R:1 /W:1

Remove-Item $empty -Force
Remove-Item $target -Force