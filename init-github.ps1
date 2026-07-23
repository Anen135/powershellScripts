<#
.SYNOPSIS
    Initializes a git repository, creates a repository on GitHub, and pushes changes.

.DESCRIPTION
    The script initializes git in the current directory (if not already initialized),
    creates a repository on GitHub with the specified name and visibility,
    adds all files, commits, and pushes changes.

.PARAMETER RepoName
    Name of the repository to create.

.PARAMETER Private
    Creates a private repository.

.PARAMETER Public
    Creates a public repository (default).

.NOTES
    Version: 2.0
    Author: Anen
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
    Write-Verbose "Checking availability of git and gh utilities..."

    function Test-Command($cmd) {
        return $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
    }

    if (-not (Test-Command "git")) {
        Write-Error "Git is not installed or not available in PATH."
        throw
    }

    if (-not (Test-Command "gh")) {
        Write-Error "GitHub CLI (gh) is not installed or not available in PATH."
        throw
    }

    # Determine visibility flag
    $visibility = "--public"
    if ($Private.IsPresent) { $visibility = "--private" }

    Write-Verbose "Visibility flag: $visibility"
}

process {
    try {
        # 1. Initialize git
        if (-not (Test-Path ".git")) {
            git init 
            Write-Output "Git initialized."
        }
        else {
            Write-Output "Git already initialized."
        }

        # 2. Add and commit
        git add . 

        # Check if there is anything to commit
        $status = git status --porcelain
        if ($status) {
            git commit -m "Initial commit" 
            Write-Output "Changes committed."
        }
        else {
            Write-Output "No changes to commit."
        }

        # 3. Create repository on GitHub
        try {
            gh repo create $RepoName $visibility --source=. --remote=origin --push --confirm
            Write-Output "Repository '$RepoName' created and changes pushed."
        }
        catch {
            Write-Warning "Failed to create repository via gh: $($_.Exception.Message)"
            Write-Warning "Repository '$RepoName' may already exist. Trying to push only..."
            git push -u origin main 2>$null
        }
    }
    catch {
        Write-Error "Execution error: $($_.Exception.Message)"
        throw
    }
}

end {
    Write-Verbose "Script execution completed."
}