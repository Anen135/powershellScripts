<#
.SYNOPSIS
    Инициализирует git репозиторий, создает репозиторий на GitHub и пушит изменения.

.DESCRIPTION
    Скрипт инициализирует git в текущем каталоге (если еще не инициализирован),
    создает репозиторий на GitHub с указанным именем и приватностью,
    добавляет все файлы, делает коммит и пушит изменения.

.PARAMETER RepoName
    Имя создаваемого репозитория.

.PARAMETER Private
    Создаёт приватный репозиторий.

.PARAMETER Public
    Создаёт публичный репозиторий (по умолчанию).

.NOTES
    Версия: 2.0
    Автор: Anen
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoName,

    [switch]$Private,
    [switch]$Public
)

begin {
    Write-Verbose "Проверка доступности утилит git и gh..."

    function Test-Command($cmd) {
        return $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
    }

    if (-not (Test-Command "git")) {
        Write-Error "Git не установлен или недоступен в PATH."
        exit 1
    }

    if (-not (Test-Command "gh")) {
        Write-Error "GitHub CLI (gh) не установлен или недоступен в PATH."
        exit 1
    }

    # Определение флага приватности
    $visibility = "--public"
    if ($Private.IsPresent) { $visibility = "--private" }

    Write-Verbose "Флаг приватности: $visibility"
}

process {
    try {
        # 1. Инициализация git
        if (-not (Test-Path ".git")) {
            git init 
            Write-Output "Git инициализирован."
        }
        else {
            Write-Output "Git уже инициализирован."
        }

        # 2. Добавление и коммит
        git add . 

        # Проверим, есть ли что коммитить
        $status = git status --porcelain
        if ($status) {
            git commit -m "Initial commit" 
            Write-Output "Изменения закоммичены."
        }
        else {
            Write-Output "Нет изменений для коммита."
        }

        # 3. Создание репозитория на GitHub
        try {
            gh repo create $RepoName $visibility --source=. --remote=origin --push --confirm
            Write-Output "Репозиторий '$RepoName' создан и изменения запушены."
        }
        catch {
            Write-Warning "Не удалось создать репозиторий через gh: $($_.Exception.Message)"
            Write-Warning "Возможно, репозиторий '$RepoName' уже существует. Попробую только пуш..."
            git push -u origin main 2>$null
        }
    }
    catch {
        Write-Error "Ошибка выполнения: $($_.Exception.Message)"
        exit 1
    }
}

end {
    Write-Verbose "Завершение работы скрипта."
}
