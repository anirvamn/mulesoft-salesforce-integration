<#
.SYNOPSIS
    Operational Monitoring & DLQ / Failure Alert Script
.DESCRIPTION
    Performs read-only health and failure checks across sf-listener, order-system-api,
    and PostgreSQL orders_db. Returns standard operational exit codes:
      0 = HEALTHY (All services active, zero active failure alerts)
      1 = WARNING (Services active, but unresolved exceptions or pending retries detected)
      2 = CRITICAL (One or more services unreachable or connectivity failed)
#>

[CmdletBinding()]
param (
    [int]$ListenerPort = 8081,
    [int]$SystemApiPort = 8082,
    [string]$DbHost = "localhost",
    [int]$DbPort = 5432,
    [string]$DbName = "orders_db"
)

$ErrorActionPreference = "Continue"
$scriptExitCode = 0
$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  MuleSoft Operational Health & Failure Monitor ($timestamp)" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Check sf-listener Health Endpoint
Write-Host "`n[1/3] Checking Process & Experience Layer (sf-listener :$ListenerPort)..." -NoNewline
try {
    $healthUri = "http://localhost:$ListenerPort/health"
    $response = Invoke-RestMethod -Uri $healthUri -Method Get -TimeoutSec 5 -ErrorAction Stop

    if ($response.status -eq "UP") {
        Write-Host " [OK] Status: UP" -ForegroundColor Green
        Write-Host "      Database Link: $($response.monitoring.database.status)"
        Write-Host "      Recent 24h Exceptions: $($response.monitoring.database.recentExceptions24h)"
        Write-Host "      Failed Orders: $($response.monitoring.database.failedOrders)"
        Write-Host "      Pending Email Retries: $($response.monitoring.database.pendingEmailRetries)"
    } elseif ($response.status -eq "WARNING") {
        Write-Host " [WARNING] Status: WARNING (Failures Detected)" -ForegroundColor Yellow
        Write-Host "      Recent 24h Exceptions: $($response.monitoring.database.recentExceptions24h)" -ForegroundColor Yellow
        Write-Host "      Failed Orders: $($response.monitoring.database.failedOrders)" -ForegroundColor Yellow
        Write-Host "      Pending Email Retries: $($response.monitoring.database.pendingEmailRetries)" -ForegroundColor Yellow
        if ($scriptExitCode -lt 1) { $scriptExitCode = 1 }
    } else {
        Write-Host " [DEGRADED] Status: $($response.status)" -ForegroundColor Red
        if ($response.error) { Write-Host "      Error: $($response.error)" -ForegroundColor Red }
        $scriptExitCode = 2
    }
} catch {
    Write-Host " [DOWN] Unable to reach sf-listener at http://localhost:$ListenerPort/health" -ForegroundColor Red
    Write-Host "      Detail: $($_.Exception.Message)" -ForegroundColor DarkGray
    $scriptExitCode = 2
}

# 2. Check order-system-api Port & Connectivity
Write-Host "`n[2/3] Checking System Layer (order-system-api :$SystemApiPort)..." -NoNewline
try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connectTask = $tcpClient.ConnectAsync("localhost", $SystemApiPort)
    if ($connectTask.Wait(3000) -and $tcpClient.Connected) {
        Write-Host " [OK] Port $SystemApiPort Active & Listening" -ForegroundColor Green
        $tcpClient.Close()
    } else {
        Write-Host " [DOWN] Port $SystemApiPort Unreachable (Connection Timeout)" -ForegroundColor Red
        $scriptExitCode = 2
    }
} catch {
    Write-Host " [DOWN] Port $SystemApiPort Connection Failed: $($_.Exception.Message)" -ForegroundColor Red
    $scriptExitCode = 2
}

# 3. Check PostgreSQL orders_db Port
Write-Host "`n[3/3] Checking PostgreSQL Database (${DbHost}:${DbPort})..." -NoNewline
try {
    $dbTcpClient = New-Object System.Net.Sockets.TcpClient
    $dbConnectTask = $dbTcpClient.ConnectAsync($DbHost, $DbPort)
    if ($dbConnectTask.Wait(3000) -and $dbTcpClient.Connected) {
        Write-Host " [OK] PostgreSQL Port $DbPort Listening" -ForegroundColor Green
        $dbTcpClient.Close()
    } else {
        Write-Host " [DOWN] PostgreSQL Port $DbPort Unreachable" -ForegroundColor Red
        $scriptExitCode = 2
    }
} catch {
    Write-Host " [DOWN] Database Socket Failed: $($_.Exception.Message)" -ForegroundColor Red
    $scriptExitCode = 2
}

# 4. Summary & Exit Code
Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Cyan
if ($scriptExitCode -eq 0) {
    Write-Host "OVERALL STATUS: HEALTHY (Exit Code 0)" -ForegroundColor Green
} elseif ($scriptExitCode -eq 1) {
    Write-Host "OVERALL STATUS: WARNING - Active Failures Logged (Exit Code 1)" -ForegroundColor Yellow
} else {
    Write-Host "OVERALL STATUS: CRITICAL - One or More Services Down (Exit Code 2)" -ForegroundColor Red
}
Write-Host "Note: Real-time orders-dlq depth is tracked via Runtime Manager / Anypoint Monitoring." -ForegroundColor DarkGray
Write-Host "=================================================================`n" -ForegroundColor Cyan

exit $scriptExitCode
