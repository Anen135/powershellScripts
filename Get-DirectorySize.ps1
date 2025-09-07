<#
.SYNOPSIS
    Получает размер файлов и папок в указанном пути.
.DESCRIPTION
    Выводит размер в мегабайтах для каждого файла и папки в указанном каталоге.
.NOTES
    Версия: 1.1
#>
param (
    [Parameter(Mandatory=$true)]
    [string]$Path
)

# Проверка существования пути
if (-Not (Test-Path -Path $Path)) {
    Write-Error "Путь '$Path' не существует."
    exit 1
}

# Получение размера для файлов и папок
Get-ChildItem -Path $Path -Force | ForEach-Object {
    if ($_.PSIsContainer) {
        $folderSize = (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        [PSCustomObject]@{
            Name   = $_.Name
            Type   = "Folder"
            SizeMB = "{0:N2}" -f ($folderSize / 1MB)
        }
    } else {
        [PSCustomObject]@{
            Name   = $_.Name
            Type   = "File"
            SizeMB = "{0:N2}" -f ($_.Length / 1MB)
        }
    }
} | Sort-Object {[double]$_.SizeMB} -Descending | Format-Table -AutoSize
