<#
.SYNOPSIS
    Sends HTTP requests with session/cookie persistence and formatted output.

.DESCRIPTION
    A convenience function for sending HTTP requests (GET, POST, PUT, DELETE)
    with automatic cookie session management, request timing, colored output,
    and JSON response formatting. Cookies persist across calls within the same
    PowerShell session.

.PARAMETER Uri
    The request URI.

.PARAMETER Method
    HTTP method to use. Default: GET.

.PARAMETER Body
    Optional request body for POST/PUT requests.

.PARAMETER ShowHeaders
    Display response headers in the output.

.PARAMETER ClearSession
    Clear stored cookies and reset the session.

.EXAMPLE
    req -Uri "https://api.example.com/data"

.EXAMPLE
    req -Uri "https://api.example.com/login" -Method POST -Body @{user="admin"; pass="123"}

.EXAMPLE
    req -Uri "" -ClearSession

.NOTES
    Version: 2.0
    Author: Anen
#>

function Send-ApiRequest {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Uri,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("GET", "POST", "PUT", "DELETE")]
        [string]$Method = "GET",
        
        [Parameter(Mandatory=$false)]
        $Body = $null,

        [Parameter(Mandatory=$false)]
        [switch]$ShowHeaders,

        [Parameter(Mandatory=$false)]
        [switch]$ClearSession
    )

    # Initialize session in global scope if it doesn't exist
    if ($ClearSession) {
        $global:ApiSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        Write-Host "[COOKIE] Session cleared (cookies removed)." -ForegroundColor Magenta
        if ($Uri -eq "") { return } # If called only for clearing
    }

    if ($null -eq $global:ApiSession) {
        $global:ApiSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    }

    $params = @{
        Uri            = $Uri
        Method         = $Method
        WebSession     = $global:ApiSession
        ErrorAction    = "Stop"
    }

    # If body is passed, add it to parameters
    if ($null -ne $Body) { $params.Add("Body", $Body) }

    Write-Host "`n>>> SENDING ${Method}: $Uri" -ForegroundColor Yellow
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $response = Invoke-WebRequest @params
        $stopwatch.Stop()

        Write-Host "<<< RESPONSE RECEIVED in $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor Green
        Write-Host "Status: $([int]$response.StatusCode) $($response.StatusDescription)" -ForegroundColor Green

        $currentCookies = $global:ApiSession.Cookies.GetCookies($Uri)
        if ($currentCookies.Count -gt 0) {
            $cookieNames = $currentCookies | ForEach-Object { "$($_.Name)=$($_.Value)" }
            Write-Host "[COOKIES ACTIVE]: $($cookieNames -join '; ')" -ForegroundColor DarkGray
        }

        if ($ShowHeaders) {
            Write-Host "`n--- HEADERS ---" -ForegroundColor Gray
            $response.Headers | Out-String | Write-Host -ForegroundColor Gray
        }

        # Try to output body as JSON if possible
        Write-Host "--- RESPONSE BODY ---" -ForegroundColor Cyan
        try {
            $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 10
        } catch {
            $response.Content # If not JSON, output as text
        }

    } catch {
        $stopwatch.Stop()
        Write-Host "<<< REQUEST ERROR" -ForegroundColor Red
        
        if ($_.Exception.Response) {
            $errResp = $_.Exception.Response
            Write-Host "Status: $([int]$errResp.StatusCode) $($errResp.StatusDescription)" -ForegroundColor Red
            
            # Try to read JSON error from server
            try {
                $stream = $errResp.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $text = $reader.ReadToEnd()
                if ($text) {
                    Write-Host "Server response:" -ForegroundColor Red
                    $text | ConvertFrom-Json | ConvertTo-Json -Depth 10
                } else {
                    Write-Host "Null response from server." -ForegroundColor Red
                }
            } catch {
                Write-Error "Failed to read error response: $($_.Exception.Message)"
            }
        } else {
            Write-Error $_.Exception.Message
        }
        throw
    }
}

Set-Alias req Send-ApiRequest
