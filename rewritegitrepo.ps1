git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Current directory is not a Git repository."
    exit 1
}

$tmp = New-TemporaryFile

try {
    $files = git ls-files -ci --exclude-standard

    if (-not $files) {
        Write-Host "Nothing to remove."
        exit 0
    }

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($tmp.FullName, $files, $utf8)

    git filter-repo `
        --force `
        --invert-paths `
        --paths-from-file $tmp.FullName

    if ($LASTEXITCODE -ne 0) {
        throw "git filter-repo failed."
    }

    Write-Host "History successfully rewritten."
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Remove-Item $tmp -Force -ErrorAction Ignore
}