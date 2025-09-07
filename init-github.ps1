<#
.SYNOPSIS
    Инициализирует git репозиторий, создает репозиторий на GitHub и пушит изменения.
.DESCRIPTION
    Скрипт инициализирует git в текущем каталоге (если еще не инициализирован), создает репозиторий на GitHub с указанным именем и приватностью, добавляет все файлы, делает коммит и пушит изменения.
.NOTES
    Версия: 1.1
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$RepoName,

    [switch]$Private,
    [switch]$Public
)

# Определение флага приватности
$visibility = "--public"  # Значение по умолчанию

if ($Private.IsPresent) {
    $visibility = "--private"
}

# 1. Инициализация git, если еще не инициализирован
if (-not (Test-Path ".git")) {
    git init
    Write-Output "Git инициализирован."
} else {
    Write-Output "Git уже инициализирован."
}

# 2. Добавление и коммит
git add .
git commit -m "Initial commit" -q
Write-Output "Изменения закоммичены."

# 3. Создание репозитория на GitHub и пуш
gh repo create $RepoName $visibility --source=. --remote=origin --push
