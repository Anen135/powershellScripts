<#
.SYNOPSIS
    Publishes the domain-blocking scripts to Cloudflare Pages.

.DESCRIPTION
    Builds a temporary static site containing the firewall and hosts scripts
    under their full and short names, then deploys it with Cloudflare Wrangler.
    The generated Pages site includes response headers suitable for downloading
    PowerShell source through Invoke-RestMethod.

.PARAMETER ProjectName
    Cloudflare Pages project name. The default is anen-powershell-scripts.

.PARAMETER Branch
    Production branch attached to the deployment. The default is main.

.EXAMPLE
    .\Publish-DomainBlockPages.ps1

    Publishes both scripts to the default Cloudflare Pages project.

.EXAMPLE
    .\Publish-DomainBlockPages.ps1 -ProjectName "my-powershell-scripts" -Verbose

    Publishes both scripts to a specified Cloudflare Pages project.

.NOTES
    Version: 1.0
    Author: Anen
    Requires Node.js, npm, and an authenticated Cloudflare Wrangler session.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$')]
    [string]$ProjectName = 'anen-powershell-scripts',

    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string]$Branch = 'main'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceFiles = @(
    @{
        Source = Join-Path $PSScriptRoot 'Block-DomainFirewall.ps1'
        Names  = @('Block-DomainFirewall.ps1', 'firewall.ps1')
    },
    @{
        Source = Join-Path $PSScriptRoot 'Block-DomainHosts.ps1'
        Names  = @('Block-DomainHosts.ps1', 'hosts.ps1')
    }
)

foreach ($sourceFile in $sourceFiles) {
    if (-not (Test-Path -LiteralPath $sourceFile.Source -PathType Leaf)) {
        throw "Required source file was not found: $($sourceFile.Source)"
    }
}

if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    throw 'npx was not found. Install Node.js and npm before publishing.'
}

$publishRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) ("domain-block-pages-" + [guid]::NewGuid().ToString('N'))

try {
    Write-Verbose "Preparing static assets in '$publishRoot'."
    $null = [System.IO.Directory]::CreateDirectory($publishRoot)

    foreach ($sourceFile in $sourceFiles) {
        foreach ($name in $sourceFile.Names) {
            [System.IO.File]::Copy(
                $sourceFile.Source,
                (Join-Path $publishRoot $name)
            )
        }
    }

    $headers = @'
/*.ps1
  Content-Type: text/plain; charset=utf-8
  Cache-Control: no-cache

/*
  X-Content-Type-Options: nosniff
'@

    $index = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>PowerShell domain blocking scripts</title>
  <style>
    body { max-width: 760px; margin: 48px auto; padding: 0 20px;
      color: #18212b; font: 16px/1.55 system-ui, sans-serif; }
    h1 { line-height: 1.15; }
    section { margin: 28px 0; padding: 20px; border: 1px solid #d9e0e7;
      border-radius: 12px; }
    code { display: block; margin-top: 10px; padding: 12px;
      overflow-wrap: anywhere; background: #f4f6f8; border-radius: 8px; }
  </style>
</head>
<body>
  <h1>PowerShell domain blocking scripts</h1>
  <p>Run PowerShell as Administrator. Each command downloads the script and
    prompts for the domain name.</p>
  <section>
    <h2>Windows Defender Firewall</h2>
    <code data-script="/firewall.ps1"></code>
  </section>
  <section>
    <h2>Windows hosts file</h2>
    <code data-script="/hosts.ps1"></code>
  </section>
  <script>
    document.querySelectorAll("[data-script]").forEach(function (element) {
      element.textContent = "irm " + location.origin +
        element.dataset.script + " | iex";
    });
  </script>
</body>
</html>
'@

    $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText(
        (Join-Path $publishRoot '_headers'),
        $headers,
        $utf8WithoutBom
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $publishRoot 'index.html'),
        $index,
        $utf8WithoutBom
    )

    $commitHash = $null
    $gitStatus = (& git -C $PSScriptRoot status --porcelain 2>$null)
    if ($LASTEXITCODE -eq 0 -and [string]::IsNullOrWhiteSpace($gitStatus)) {
        $commitHash = (& git -C $PSScriptRoot rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commitHash)) {
            $commitHash = $null
        }
    }

    if ($PSCmdlet.ShouldProcess(
            $ProjectName,
            "Deploy domain-blocking scripts to Cloudflare Pages"
        )) {
        Write-Verbose "Deploying project '$ProjectName' from '$publishRoot'."
        $wranglerArguments = @(
            '--yes'
            'wrangler@latest'
            'pages'
            'deploy'
            '.'
            "--cwd=$publishRoot"
            "--project-name=$ProjectName"
            "--branch=$Branch"
            '--commit-message=Publish domain-blocking scripts'
        )
        if ($null -ne $commitHash) {
            $wranglerArguments += "--commit-hash=$commitHash"
        }
        & npx @wranglerArguments

        if ($LASTEXITCODE -ne 0) {
            throw "Wrangler exited with code $LASTEXITCODE."
        }
    }
}
finally {
    if (Test-Path -LiteralPath $publishRoot) {
        $resolvedPublishRoot = [System.IO.Path]::GetFullPath($publishRoot)
        $resolvedTempRoot = [System.IO.Path]::GetFullPath(
            [System.IO.Path]::GetTempPath()
        )

        if (-not $resolvedPublishRoot.StartsWith(
                $resolvedTempRoot,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            throw "Refusing to remove path outside temp: $resolvedPublishRoot"
        }

        [System.IO.Directory]::Delete($resolvedPublishRoot, $true)
    }
}
