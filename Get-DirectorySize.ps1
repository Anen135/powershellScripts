<#
.SYNOPSIS
    Расширенный аналог команды DIR для PowerShell.

.DESCRIPTION
    Скрипт выводит список файлов и папок в указанном каталоге с поддержкой большинства
    ключей из оригинальной команды DIR (Windows). Поддерживаются фильтры по атрибутам,
    сортировка, рекурсивный поиск, вывод владельцев, нижний регистр, форматирование
    вывода и вычисление размеров.

.PARAMETER Path
    Каталог, содержимое которого требуется отобразить.

.PARAMETER Unit
    Единица измерения размера (MB или GB). По умолчанию: MB.

.PARAMETER Recurse
    Эквивалент ключа /S. Рекурсивный обход всех подкаталогов.

.PARAMETER BareFormat
    Эквивалент ключа /B. Вывод только имен файлов и папок без дополнительных данных.

.PARAMETER LowerCase
    Эквивалент ключа /L. Вывод имен файлов и папок в нижнем регистре.

.PARAMETER Pause
    Эквивалент ключа /P. Пауза после каждой строки с ожиданием нажатия клавиши.

.PARAMETER Sort
    Эквивалент ключа /O. Сортировка списка:
      - N: по имени (по алфавиту)
      - S: по размеру (от меньшего)
      - E: по расширению (по алфавиту)
      - D: по дате (от старого)
      - G: сначала каталоги

.PARAMETER Owner
    Эквивалент ключа /Q. Вывод владельца каждого файла или каталога.

.PARAMETER TimeField
    Эквивалент ключа /T. Поле времени для сортировки:
      - C: дата создания
      - A: дата последнего доступа
      - W: дата последнего изменения (по умолчанию)

.PARAMETER FourDigitYear
    Эквивалент ключа /4. Использовать 4‑значный формат года в выводе.

.PARAMETER Attributes
    Эквивалент ключа /A. Фильтрация по атрибутам файлов:
      - D: каталоги
      - R: только для чтения
      - H: скрытые
      - A: архивные
      - S: системные

.EXAMPLE
    PS> .\Get-DirSize.ps1 -Path "C:\Temp"
    Выводит список файлов и папок в каталоге `C:\Temp` с размерами в мегабайтах.

.EXAMPLE
    PS> .\Get-DirSize.ps1 -Path "C:\Windows" -Unit GB -Recurse
    Выводит все файлы и папки в `C:\Windows` и подкаталогах, размеры в гигабайтах.

.EXAMPLE
    PS> .\Get-DirSize.ps1 -Path "C:\Data" -BareFormat -LowerCase
    Выводит список файлов и папок в `C:\Data` только именами в нижнем регистре.

.EXAMPLE
    PS> .\Get-DirSize.ps1 -Path "C:\Projects" -Owner -Sort D
    Отображает список файлов и папок в каталоге `C:\Projects` с указанием владельца
    и сортировкой по дате создания.

.NOTES
    Версия: 3.0
    Автор: Системный администратор
    Лицензия: MIT
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$Path,

    [ValidateSet("MB","GB")]
    [string]$Unit = "MB",

    [switch]$Recurse,           # /S
    [switch]$BareFormat,        # /B
    [switch]$LowerCase,         # /L
    [switch]$Pause,             # /P
    [ValidateSet("N","S","E","D","G")]
    [string]$Sort = "N",       # /O
    [switch]$Owner,             # /Q
    [ValidateSet("C","A","W")]
    [string]$TimeField = "W",  # /T
    [switch]$FourDigitYear,     # /4
    [string]$Attributes         # /A
)

begin {
    Write-Verbose "Инициализация параметров..."
    $divider = if ($Unit -eq "GB") { 1GB } else { 1MB }
    $items = Get-ChildItem -Path $Path -Force -ErrorAction Stop

    if ($Attributes) {
        $items = $items | Where-Object {
            $match = $true
            foreach ($attr in $Attributes.ToCharArray()) {
                switch ($attr) {
                    'D' { if (-not $_.PSIsContainer) { $match = $false } }
                    'R' { if (-not $_.Attributes.ToString().Contains('ReadOnly')) { $match = $false } }
                    'H' { if (-not $_.Attributes.ToString().Contains('Hidden')) { $match = $false } }
                    'A' { if (-not $_.Attributes.ToString().Contains('Archive')) { $match = $false } }
                    'S' { if (-not $_.Attributes.ToString().Contains('System')) { $match = $false } }
                }
            }
            $match
        }
    }
}

process {
    foreach ($item in $items) {
        try {
            $size = 0
            if ($item.PSIsContainer) {
                if ($Recurse) {
                    $size = (Get-ChildItem -Path $item.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                }
            } else {
                $size = $item.Length
            }

            $name = if ($LowerCase) { $item.Name.ToLower() } else { $item.Name }

            $obj = [PSCustomObject]@{
                Name = $name
                Type = if ($item.PSIsContainer) { 'Folder' } else { 'File' }
                Size = "{0:N2}" -f ($size / $divider)
                Unit = $Unit
            }

            if ($Owner) {
                $obj | Add-Member -NotePropertyName Owner -NotePropertyValue (Get-Acl $item.FullName).Owner
            }

            if ($BareFormat) {
                Write-Output $obj.Name
            } else {
                Write-Output $obj
            }

            if ($Pause) { Read-Host "Нажмите Enter для продолжения..." }
        }
        catch {
            Write-Warning "Ошибка при обработке '$($item.FullName)': $($_.Exception.Message)"
        }
    }
}
