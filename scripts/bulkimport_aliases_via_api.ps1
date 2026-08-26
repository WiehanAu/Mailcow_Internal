#requires -Version 5.1

<#
.SYNOPSIS
    Bulk import email aliases into Mailcow via API

.DESCRIPTION
    This script reads a CSV file containing email aliases and imports them into Mailcow
    using the API v1 add alias endpoint.

.PARAMETER CsvPath
    Path to the CSV file with 'address' and 'goto' columns

.PARAMETER MailcowUrl
    Base URL of the Mailcow instance (e.g., https://mail.example.com)

.PARAMETER ApiKey
    Mailcow API key with alias creation permissions

.PARAMETER Active
    Whether the alias should be active (default: 1)

.EXAMPLE
    .\bulkimport_aliases_via_api.ps1 -CsvPath .\aliases.csv -MailcowUrl "https://mail.example.com" -ApiKey "your-api-key"

.EXAMPLE
    .\bulkimport_aliases_via_api.ps1 -CsvPath .\aliases.csv -MailcowUrl "https://mail.example.com" -ApiKey "your-api-key" -Active 0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$CsvPath,

    [Parameter(Mandatory = $true)]
    [string]$MailcowUrl,

    [Parameter(Mandatory = $true)]
    [string]$ApiKey,

    [Parameter(Mandatory = $false)]
    [ValidateSet("0", "1")]
    [string]$Active = "1"
)

# Set error handling
$ErrorActionPreference = "Stop"

# Validate MailcowUrl format
if (-not ($MailcowUrl -match '^https?://')) {
    Write-Error "MailcowUrl must start with http:// or https://"
}

# Remove trailing slash from MailcowUrl
$MailcowUrl = $MailcowUrl.TrimEnd('/')

# Read CSV file
Write-Host "Reading CSV file: $CsvPath" -ForegroundColor Cyan
try {
    $aliases = Import-Csv -Path $CsvPath
} catch {
    Write-Error "Failed to read CSV file: $_"
    exit 1
}

if ($aliases.Count -eq 0) {
    Write-Warning "No aliases found in CSV file"
    exit 0
}

Write-Host "Found $($aliases.Count) aliases to import" -ForegroundColor Cyan

# Set up API endpoint
$apiEndpoint = "$MailcowUrl/api/v1/add/alias"

# Set up headers
$headers = @{
    "Content-Type" = "application/json"
    "X-API-Key"    = $ApiKey
}

# Track results
$successCount = 0
$failCount = 0
$skippedCount = 0
$results = @()

# Process each alias
foreach ($alias in $aliases) {
    # Validate required fields
    if (-not $alias.address -or -not $alias.goto) {
        Write-Warning "Skipping row: Missing required fields (address or goto)"
        $skippedCount++
        continue
    }

    # Build request body
    $body = @{
        active  = $Active
        address = $alias.address
        goto    = $alias.goto
    }

    # Convert to JSON
    $jsonBody = $body | ConvertTo-Json -Depth 2

    Write-Host "Processing: $($alias.address) -> $($alias.goto)" -ForegroundColor Yellow

    try {
        # Make API call
        $response = Invoke-RestMethod -Uri $apiEndpoint -Method POST -Headers $headers -Body $jsonBody

        # Check response
        if ($response.type -eq "success") {
            Write-Host "  Success: $($response.msg[1])" -ForegroundColor Green
            $successCount++
        } else {
            Write-Warning "  Failed: $($response.msg -join ', ')"
            $failCount++
        }

        $results += [PSCustomObject]@{
            Address = $alias.address
            Goto    = $alias.goto
            Status  = $response.type
            Message = ($response.msg -join ', ')
        }

    } catch {
        Write-Error "  Error processing $($alias.address): $_"
        if ($_.ErrorDetails) {
            Write-Error "  Response: $($_.ErrorDetails)"
        }
        $failCount++
    }

    # Pause between API calls to avoid DB corruption from rapid requests
    if ($aliases.IndexOf($alias) -lt ($aliases.Count - 1)) {
        Start-Sleep -Seconds 1
    }
}

# Summary
Write-Host "`n=== Import Summary ===" -ForegroundColor Cyan
Write-Host "Total processed: $($aliases.Count)" -ForegroundColor White
Write-Host "Successful:      $successCount" -ForegroundColor Green
Write-Host "Failed:          $failCount" -ForegroundColor Red
Write-Host "Skipped:         $skippedCount" -ForegroundColor Yellow

# Output results as table
Write-Host "`nDetailed Results:" -ForegroundColor Cyan
$results | Format-Table -AutoSize
