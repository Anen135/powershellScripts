<#
.SYNOPSIS
    Объединяет все текстовые файлы из указанной папки в один файл.

.DESCRIPTION
    Скрипт читает все текстовые файлы из указанной папки,
    добавляет разделитель с именем файла перед содержимым каждого файла
    и записывает всё в один выходной файл.
    Работает только с текстовыми файлами (кодировка UTF-8).

.PARAMETER InputFolder
    Путь к папке с файлами, которые нужно объединить.

.PARAMETER OutputFile
    Путь к итоговому файлу, куда будет записан результат.

.EXAMPLE
    PS> .\Merge-Files.ps1 -InputFolder ".\merger" -OutputFile ".\main.txt"

.NOTES
    Версия: 2.0
    Автор: Системный администратор
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$InputFolder = ".\merger",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputFile = ".\main.txt"
)

begin {
    Write-Verbose "Инициализация параметров..."
    try {
        if (-not (Test-Path $InputFolder -PathType Container)) {
            throw "Папка '$InputFolder' не существует."
        }

        if (Test-Path $OutputFile) {
            Write-Verbose "Удаление существующего файла '$OutputFile'..."
            Remove-Item -Path $OutputFile -Force -ErrorAction Stop
        }
    }
    catch {
        Write-Error "Ошибка инициализации: $($_.Exception.Message)"
        exit 1
    }
}

process {
    try {
        $Files = Get-ChildItem -Path $InputFolder -File -ErrorAction Stop |
                 Where-Object { $_.Name -ne [System.IO.Path]::GetFileName($OutputFile) }

        if (-not $Files) {
            Write-Warning "В папке '$InputFolder' не найдено файлов для объединения."
            return
        }

        foreach ($File in $Files) {
            try {
                # Разделитель
                "%%=============$($File.Name)========%%" | Out-File -FilePath $OutputFile -Encoding UTF8 -Append -ErrorAction Stop

                # Содержимое файла
                Get-Content -Path $File.FullName -ErrorAction Stop | 
                    Out-File -FilePath $OutputFile -Encoding UTF8 -Append -ErrorAction Stop

                Write-Verbose "Файл '$($File.Name)' добавлен."
            }
            catch {
                Write-Warning "Ошибка при обработке файла '$($File.FullName)': $($_.Exception.Message)"
                continue
            }
        }

        Write-Output "Все файлы из '$InputFolder' объединены в '$OutputFile'."
    }
    catch {
        Write-Error "Ошибка обработки: $($_.Exception.Message)"
        exit 1
    }
}

end {
    Write-Verbose "Завершение работы скрипта."
}
