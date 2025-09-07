<#
.SYNOPSIS
    Объединяет все текстовые файлы из указанной папки в один файл.
.DESCRIPTION
    Скрипт читает все текстовые файлы из указанной папки, добавляет разделитель с именем файла перед содержимым каждого файла и записывает всё в один выходной файл.
.NOTES
    Версия: 1.1
#>
param(
    [string]$InputFolder = ".\merger",
    [string]$OutputFile = ".\main.txt"
)

if (-not (Test-Path $InputFolder -PathType Container)) {
    Write-Host "Ошибка: папка '$InputFolder' не существует!"
    exit
}

# Удаляем выходной файл, если он уже существует
if (Test-Path $OutputFile) {
    Remove-Item $OutputFile
}

Get-ChildItem -Path $InputFolder -File | ForEach-Object {
    if ($_.Name -eq [System.IO.Path]::GetFileName($OutputFile)) {
        return
    }

    # Разделитель
    "%%=============$($_.Name)========%%" | Out-File -FilePath $OutputFile -Encoding UTF8 -Append

    # Содержимое файла
    Get-Content -Path $_.FullName | Out-File -FilePath $OutputFile -Encoding UTF8 -Append
}

Write-Host "Все файлы из '$InputFolder' объединены в '$OutputFile'."
Write-Host "Итоговый файл содержит $(Get-Content $OutputFile | Measure-Object -Line).Lines строк."