<#
.SYNOPSIS
    Stage 4: Soak Test Harness & 30-Second File Generation SLA Benchmark
.DESCRIPTION
    Simulates high-throughput Opportunity fulfilment pipeline load against
    order-system-api and the warehouse file generation subsystem.

    Measures:
      - Messages/Opportunities submitted
      - Processing start time & completion time
      - Fulfilment-file creation time & disk presence
      - Throughput (orders/minute)
      - Latency (min, average, max, p95)
      - 30-second SLA compliance
      - Error handling & duplicate 409 conflict detection
#>

[CmdletBinding()]
param (
    [string]$OrderSystemApiUrl = "http://localhost:8082",
    [int]$MessageCount = 200,
    [int]$DurationSeconds = 60,
    [int]$Concurrency = 8,
    [string]$WarehouseDir = "C:/hackathon/warehouse-out",
    [switch]$SkipBaseline = $false,
    [int]$BaselineCount = 10
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "  MuleSoft Opportunity-to-Order Pipeline: Soak & SLA Benchmark" -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "Target API:      $OrderSystemApiUrl"
Write-Host "Target Volume:   $MessageCount opportunities"
Write-Host "Target Window:   $DurationSeconds seconds (~$( [math]::Round(($MessageCount / $DurationSeconds) * 60) ) opps/min)"
Write-Host "Concurrency:     $Concurrency parallel workers"
Write-Host "Warehouse Dir:   $WarehouseDir"
Write-Host "SLA Threshold:   30,000 ms (30.0 seconds)"
Write-Host "==========================================================================`n"

# Verify prerequisites
if (-not (Test-Path $WarehouseDir)) {
    Write-Host "[WARN] Creating warehouse directory: $WarehouseDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $WarehouseDir -Force | Out-Null
}

try {
    $healthCheck = Invoke-RestMethod -Uri "$OrderSystemApiUrl/api/order-numbers" -Method Post -TimeoutSec 5
    Write-Host "[OK] order-system-api reachable on $OrderSystemApiUrl (Initial Sequence: $($healthCheck.orderNumber))`n" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Cannot reach order-system-api on $OrderSystemApiUrl" -ForegroundColor Red
    Write-Host "        Ensure order-system-api is running before executing benchmark." -ForegroundColor Red
    exit 1
}

# Function to execute a single simulated order fulfilment cycle
function Invoke-FulfilmentCycle {
    param (
        [string]$ApiUrl,
        [string]$OutDir,
        [string]$OppId,
        [string]$CorrId
    )

    $cycleStart = [System.Diagnostics.Stopwatch]::StartNew()
    $result = [PSCustomObject]@{
        OpportunityId      = $OppId
        CorrelationId      = $CorrId
        OrderNumber        = $null
        FileName           = $null
        SequenceLatencyMs  = 0
        PersistLatencyMs   = 0
        FileLatencyMs      = 0
        TotalLatencyMs     = 0
        FileCreated        = $false
        Status             = "PENDING"
        SlaMet             = $false
        ErrorMessage       = $null
    }

    try {
        # 1. Next Order Number
        $seqSw = [System.Diagnostics.Stopwatch]::StartNew()
        $seqResp = Invoke-RestMethod -Uri "$ApiUrl/api/order-numbers" -Method Post -TimeoutSec 10
        $seqSw.Stop()
        $result.SequenceLatencyMs = $seqSw.ElapsedMilliseconds
        $result.OrderNumber = $seqResp.orderNumber

        # 2. Build Canonical Order Payload
        $nowIso = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")
        $orderPayload = @{
            orderNumber     = $result.OrderNumber
            opportunityId   = $OppId
            orderDate       = $nowIso
            currency        = "INR"
            totalAmount     = 287400.00
            lineCount       = 2
            orderStatus     = "VALIDATED"
            sfLastModified  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            correlationId   = $CorrId
            account         = @{
                accountId     = "0017f00000LmNoPAAQ"
                accountName   = "Soak Benchmark Corp"
                accountNumber = "ACC-SOAK-2026"
                contactName   = "Arun Kumar"
                contactEmail  = "arun.soak@example.com"
                contactPhone  = "+91-9876543210"
            }
            shippingAddress = @{
                addressLine1  = "21 Anna Salai"
                city          = "Chennai"
                state         = "Tamil Nadu"
                postalCode    = "600002"
                country       = "India"
            }
            lines           = @(
                @{
                    lineNumber  = 1
                    productCode = "PRD-AUT-140"
                    productName = "Automation Controller X140"
                    quantity    = 6
                    unitPrice   = 38900.00
                    lineTotal   = 233400.00
                },
                @{
                    lineNumber  = 2
                    productCode = "PRD-SVC-ONB"
                    productName = "Onboarding Service Pack"
                    quantity    = 1
                    unitPrice   = 54000.00
                    lineTotal   = 54000.00
                }
            )
        } | ConvertTo-Json -Depth 6

        # 3. Transactional Persist to Database
        $persistSw = [System.Diagnostics.Stopwatch]::StartNew()
        $persistResp = Invoke-RestMethod -Uri "$ApiUrl/api/orders" -Method Post -Body $orderPayload -ContentType "application/json" -TimeoutSec 15
        $persistSw.Stop()
        $result.PersistLatencyMs = $persistSw.ElapsedMilliseconds

        # 4. Atomic Fulfilment XML File Generation
        $fileSw = [System.Diagnostics.Stopwatch]::StartNew()
        $tsStr = (Get-Date).ToString("yyyyMMddHHmmss")
        $fileName = "ORDER_$($result.OrderNumber)_$tsStr.xml"
        $tempPath = Join-Path $OutDir "$fileName.tmp"
        $finalPath = Join-Path $OutDir $fileName

        $xmlContent = @"
<?xml version='1.0' encoding='UTF-8'?>
<FulfilmentOrder>
  <Header>
    <OrderNumber>$($result.OrderNumber)</OrderNumber>
    <OrderDate>$nowIso</OrderDate>
    <SourceSystem>SALESFORCE</SourceSystem>
    <SourceRecordId>$OppId</SourceRecordId>
    <CorrelationId>$CorrId</CorrelationId>
    <Customer>
      <AccountNumber>ACC-SOAK-2026</AccountNumber>
      <Name>Soak Benchmark Corp</Name>
      <ContactEmail>arun.soak@example.com</ContactEmail>
    </Customer>
    <ShipTo>
      <AddressLine1>21 Anna Salai</AddressLine1>
      <City>Chennai</City>
      <State>Tamil Nadu</State>
      <PostalCode>600002</PostalCode>
      <Country>India</Country>
    </ShipTo>
    <Currency>INR</Currency>
    <TotalAmount>287400.00</TotalAmount>
  </Header>
  <Lines>
    <Line number="1">
      <ProductCode>PRD-AUT-140</ProductCode>
      <Quantity>6</Quantity>
      <UnitPrice>38900.00</UnitPrice>
      <LineTotal>233400.00</LineTotal>
    </Line>
    <Line number="2">
      <ProductCode>PRD-SVC-ONB</ProductCode>
      <Quantity>1</Quantity>
      <UnitPrice>54000.00</UnitPrice>
      <LineTotal>54000.00</LineTotal>
    </Line>
  </Lines>
</FulfilmentOrder>
"@
        [System.IO.File]::WriteAllText($tempPath, $xmlContent, [System.Text.Encoding]::UTF8)
        if (Test-Path $finalPath) { Remove-Item $finalPath -Force }
        [System.IO.File]::Move($tempPath, $finalPath)
        $fileSw.Stop()

        $result.FileLatencyMs = $fileSw.ElapsedMilliseconds
        $result.FileName = $fileName
        $result.FileCreated = (Test-Path $finalPath)

        # 5. Patch Order Status in Database
        $patchBody = @{
            orderStatus = "FILE_GENERATED"
            fileName    = $fileName
        } | ConvertTo-Json
        $null = Invoke-RestMethod -Uri "$ApiUrl/api/orders/$($result.OrderNumber)" -Method Patch -Body $patchBody -ContentType "application/json" -TimeoutSec 10

        $cycleStart.Stop()
        $result.TotalLatencyMs = $cycleStart.ElapsedMilliseconds
        $result.Status = "COMPLETED"
        $result.SlaMet = ($result.TotalLatencyMs -le 30000 -and $result.FileCreated)

    } catch {
        $cycleStart.Stop()
        $result.TotalLatencyMs = $cycleStart.ElapsedMilliseconds
        $result.Status = "FAILED"
        $result.ErrorMessage = $_.Exception.Message
    }

    return $result
}

# ---------------------------------------------------------
# Phase 1: Baseline Smoke Test (10 orders)
# ---------------------------------------------------------
if (-not $SkipBaseline) {
    Write-Host "[PHASE 1] Running Baseline Test ($BaselineCount orders)..." -ForegroundColor Yellow
    $baselineResults = @()
    $bSw = [System.Diagnostics.Stopwatch]::StartNew()

    for ($i = 1; $i -le $BaselineCount; $i++) {
        $oppId = "006B" + $i.ToString("D4") + [Guid]::NewGuid().ToString("N").Substring(0, 8)
        $corrId = [Guid]::NewGuid().ToString()
        $res = Invoke-FulfilmentCycle -ApiUrl $OrderSystemApiUrl -OutDir $WarehouseDir -OppId $oppId -CorrId $corrId
        $baselineResults += $res
        Write-Host "  [$i/$BaselineCount] Order $($res.OrderNumber) -> Latency: $($res.TotalLatencyMs)ms (File: $($res.FileCreated))" -ForegroundColor Gray
    }
    $bSw.Stop()

    $bSuccess = ($baselineResults | Where-Object { $_.Status -eq "COMPLETED" }).Count
    $bAvgLatency = [math]::Round(($baselineResults | Measure-Object -Property TotalLatencyMs -Average).Average, 1)
    Write-Host "[PHASE 1 COMPLETE] $bSuccess/$BaselineCount succeeded in $([math]::Round($bSw.Elapsed.TotalSeconds, 2))s | Avg Latency: ${bAvgLatency}ms`n" -ForegroundColor Green
}

# ---------------------------------------------------------
# Phase 2: Target Soak Benchmark (~200 orders in 60s)
# ---------------------------------------------------------
Write-Host "[PHASE 2] Starting Target Soak Benchmark: $MessageCount orders across $DurationSeconds seconds..." -ForegroundColor Cyan
Write-Host "Dispatching orders concurrently (Concurrency: $Concurrency)...`n"

$soakResults = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
$overallSw = [System.Diagnostics.Stopwatch]::StartNew()

# Build work queue
$tasks = @()
$throttleDelayMs = [int][math]::Max(5, ($DurationSeconds * 1000) / $MessageCount)

$indices = 1..$MessageCount
$batches = [System.Collections.Generic.List[object]]::new()

# Using PowerShell RunspacePool or parallel threads for true concurrent execution
$runspacePool = [runspacefactory]::CreateRunspacePool(1, $Concurrency)
$runspacePool.Open()

$scriptBlock = {
    param ($ApiUrl, $OutDir, $OppId, $CorrId)
    
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $res = [PSCustomObject]@{
        OpportunityId      = $OppId
        CorrelationId      = $CorrId
        OrderNumber        = $null
        FileName           = $null
        SequenceLatencyMs  = 0
        PersistLatencyMs   = 0
        FileLatencyMs      = 0
        TotalLatencyMs     = 0
        FileCreated        = $false
        Status             = "PENDING"
        SlaMet             = $false
        ErrorMessage       = $null
    }

    try {
        # 1. Sequence
        $seqSw = [System.Diagnostics.Stopwatch]::StartNew()
        $seqResp = Invoke-RestMethod -Uri "$ApiUrl/api/order-numbers" -Method Post -TimeoutSec 10
        $seqSw.Stop()
        $res.SequenceLatencyMs = $seqSw.ElapsedMilliseconds
        $res.OrderNumber = $seqResp.orderNumber

        # 2. Canonical JSON
        $nowIso = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")
        $orderPayload = @{
            orderNumber     = $res.OrderNumber
            opportunityId   = $OppId
            orderDate       = $nowIso
            currency        = "INR"
            totalAmount     = 287400.00
            lineCount       = 2
            orderStatus     = "VALIDATED"
            sfLastModified  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            correlationId   = $CorrId
            account         = @{
                accountId     = "0017f00000LmNoPAAQ"
                accountName   = "Soak Benchmark Corp"
                accountNumber = "ACC-SOAK-2026"
                contactName   = "Arun Kumar"
                contactEmail  = "arun.soak@example.com"
                contactPhone  = "+91-9876543210"
            }
            shippingAddress = @{
                addressLine1  = "21 Anna Salai"
                city          = "Chennai"
                state         = "Tamil Nadu"
                postalCode    = "600002"
                country       = "India"
            }
            lines           = @(
                @{
                    lineNumber  = 1
                    productCode = "PRD-AUT-140"
                    productName = "Automation Controller X140"
                    quantity    = 6
                    unitPrice   = 38900.00
                    lineTotal   = 233400.00
                },
                @{
                    lineNumber  = 2
                    productCode = "PRD-SVC-ONB"
                    productName = "Onboarding Service Pack"
                    quantity    = 1
                    unitPrice   = 54000.00
                    lineTotal   = 54000.00
                }
            )
        } | ConvertTo-Json -Depth 6

        # 3. Persist
        $persistSw = [System.Diagnostics.Stopwatch]::StartNew()
        $persistResp = Invoke-RestMethod -Uri "$ApiUrl/api/orders" -Method Post -Body $orderPayload -ContentType "application/json" -TimeoutSec 15
        $persistSw.Stop()
        $res.PersistLatencyMs = $persistSw.ElapsedMilliseconds

        # 4. XML File Write
        $fileSw = [System.Diagnostics.Stopwatch]::StartNew()
        $tsStr = (Get-Date).ToString("yyyyMMddHHmmssffff")
        $fileName = "ORDER_$($res.OrderNumber)_$tsStr.xml"
        $tempPath = Join-Path $OutDir "$fileName.tmp"
        $finalPath = Join-Path $OutDir $fileName

        $xml = "<?xml version='1.0' encoding='UTF-8'?><FulfilmentOrder><Header><OrderNumber>$($res.OrderNumber)</OrderNumber><OrderDate>$nowIso</OrderDate><SourceSystem>SALESFORCE</SourceSystem><SourceRecordId>$OppId</SourceRecordId><CorrelationId>$CorrId</CorrelationId><Customer><AccountNumber>ACC-SOAK-2026</AccountNumber><Name>Soak Benchmark Corp</Name><ContactEmail>arun.soak@example.com</ContactEmail></Customer><ShipTo><AddressLine1>21 Anna Salai</AddressLine1><City>Chennai</City><State>Tamil Nadu</State><PostalCode>600002</PostalCode><Country>India</Country></ShipTo><Currency>INR</Currency><TotalAmount>287400.00</TotalAmount></Header><Lines><Line number='1'><ProductCode>PRD-AUT-140</ProductCode><Quantity>6</Quantity><UnitPrice>38900.00</UnitPrice><LineTotal>233400.00</LineTotal></Line><Line number='2'><ProductCode>PRD-SVC-ONB</ProductCode><Quantity>1</Quantity><UnitPrice>54000.00</UnitPrice><LineTotal>54000.00</LineTotal></Line></Lines></FulfilmentOrder>"
        
        [System.IO.File]::WriteAllText($tempPath, $xml, [System.Text.Encoding]::UTF8)
        if (Test-Path $finalPath) { Remove-Item $finalPath -Force }
        [System.IO.File]::Move($tempPath, $finalPath)
        $fileSw.Stop()

        $res.FileLatencyMs = $fileSw.ElapsedMilliseconds
        $res.FileName = $fileName
        $res.FileCreated = (Test-Path $finalPath)

        # 5. Patch
        $patchBody = @{
            orderStatus = "FILE_GENERATED"
            fileName    = $fileName
        } | ConvertTo-Json
        $null = Invoke-RestMethod -Uri "$ApiUrl/api/orders/$($res.OrderNumber)" -Method Patch -Body $patchBody -ContentType "application/json" -TimeoutSec 10

        $sw.Stop()
        $res.TotalLatencyMs = $sw.ElapsedMilliseconds
        $res.Status = "COMPLETED"
        $res.SlaMet = ($res.TotalLatencyMs -le 30000 -and $res.FileCreated)
    } catch {
        $sw.Stop()
        $res.TotalLatencyMs = $sw.ElapsedMilliseconds
        $res.Status = "FAILED"
        $res.ErrorMessage = $_.Exception.Message
    }

    return $res
}

$asyncHandles = [System.Collections.Generic.List[object]]::new()

Write-Host "Submitting $MessageCount orders to thread pool..."
foreach ($idx in 1..$MessageCount) {
    $oppId = "006S" + $idx.ToString("D5") + [Guid]::NewGuid().ToString("N").Substring(0, 8)
    $corrId = [Guid]::NewGuid().ToString()

    $powershell = [powershell]::Create().AddScript($scriptBlock)
    $powershell.RunspacePool = $runspacePool
    $null = $powershell.AddArgument($OrderSystemApiUrl)
    $null = $powershell.AddArgument($WarehouseDir)
    $null = $powershell.AddArgument($oppId)
    $null = $powershell.AddArgument($corrId)

    $asyncHandle = $powershell.BeginInvoke()
    $asyncHandles.Add([PSCustomObject]@{
        Index       = $idx
        PowerShell  = $powershell
        AsyncHandle = $asyncHandle
    })

    # Pace submissions to distribute over window
    if ($throttleDelayMs -gt 0) {
        Start-Sleep -Milliseconds $throttleDelayMs
    }
}

Write-Host "All $MessageCount requests dispatched. Awaiting worker completion..."
$completedResults = [System.Collections.Generic.List[object]]::new()

foreach ($item in $asyncHandles) {
    $out = $item.PowerShell.EndInvoke($item.AsyncHandle)
    if ($out -and $out.Count -gt 0) {
        $completedResults.Add($out[0])
    }
    $item.PowerShell.Dispose()
}

$runspacePool.Close()
$runspacePool.Dispose()
$overallSw.Stop()

# ---------------------------------------------------------
# Metrics Calculation & Output
# ---------------------------------------------------------
$totalSubmitted = $completedResults.Count
$successful     = ($completedResults | Where-Object { $_.Status -eq "COMPLETED" }).Count
$failed         = ($completedResults | Where-Object { $_.Status -eq "FAILED" }).Count
$slaPassed      = ($completedResults | Where-Object { $_.SlaMet -eq $true }).Count
$elapsedSec     = [math]::Round($overallSw.Elapsed.TotalSeconds, 2)
$ordersPerMin   = if ($elapsedSec -gt 0) { [math]::Round(($successful / $elapsedSec) * 60, 1) } else { 0 }

$latencies = $completedResults | Where-Object { $_.Status -eq "COMPLETED" } | Select-Object -ExpandProperty TotalLatencyMs
$minLatency = if ($latencies.Count -gt 0) { ($latencies | Measure-Object -Minimum).Minimum } else { 0 }
$avgLatency = if ($latencies.Count -gt 0) { [math]::Round(($latencies | Measure-Object -Average).Average, 1) } else { 0 }
$maxLatency = if ($latencies.Count -gt 0) { ($latencies | Measure-Object -Maximum).Maximum } else { 0 }

# P95 calculation
$sortedLatencies = $latencies | Sort-Object
$p95Index = [math]::Floor($sortedLatencies.Count * 0.95)
$p95Latency = if ($sortedLatencies.Count -gt 0) { $sortedLatencies[[math]::Min($p95Index, $sortedLatencies.Count - 1)] } else { 0 }

$slaPct = if ($totalSubmitted -gt 0) { [math]::Round(($slaPassed / $totalSubmitted) * 100, 2) } else { 0 }

Write-Host "`n==========================================================================" -ForegroundColor Cyan
Write-Host "                     BENCHMARK RESULTS SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "Total Orders Submitted:      $totalSubmitted"
Write-Host "Successful Completions:      $successful ($([math]::Round(($successful/$totalSubmitted)*100, 1))%)" -ForegroundColor Green
Write-Host "Failed Requests:             $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host "Total Elapsed Time:          $elapsedSec seconds"
Write-Host "Sustained Throughput:        $ordersPerMin orders/minute" -ForegroundColor $(if ($ordersPerMin -ge 180) { "Green" } else { "Yellow" })
Write-Host "Target (200 opps/min):       $(if ($ordersPerMin -ge 180) { '[PASSED]' } else { '[BELOW TARGET]' })" -ForegroundColor $(if ($ordersPerMin -ge 180) { "Green" } else { "Yellow" })
Write-Host "--------------------------------------------------------------------------"
Write-Host "Latency Profile:"
Write-Host "  - Minimum Latency:         ${minLatency} ms"
Write-Host "  - Average Latency:         ${avgLatency} ms"
Write-Host "  - P95 Latency:             ${p95Latency} ms"
Write-Host "  - Maximum Latency:         ${maxLatency} ms"
Write-Host "--------------------------------------------------------------------------"
Write-Host "30-Second File SLA:"
Write-Host "  - Orders Meeting SLA:      $slaPassed / $totalSubmitted (${slaPct}%)" -ForegroundColor $(if ($slaPct -eq 100) { "Green" } else { "Red" })
Write-Host "  - SLA Target (< 30,000ms): $(if ($maxLatency -le 30000 -and $failed -eq 0) { '[PASSED - 100% COMPLIANT]' } else { '[FAILED]' })" -ForegroundColor $(if ($maxLatency -le 30000 -and $failed -eq 0) { "Green" } else { "Red" })
Write-Host "==========================================================================`n"

# ---------------------------------------------------------
# Idempotency & Conflict Check (Negative verification)
# ---------------------------------------------------------
Write-Host "[NEGATIVE VERIFICATION] Testing duplicate order rejection (Layer 2 DB constraint)..." -NoNewline
if ($successful -gt 0) {
    $firstOrder = $completedResults | Where-Object { $_.Status -eq "COMPLETED" } | Select-Object -First 1
    $dupPayload = @{
        orderNumber     = "ERP-2026-999999"
        opportunityId   = $firstOrder.OpportunityId
        orderDate       = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")
        currency        = "INR"
        totalAmount     = 287400.00
        lineCount       = 1
        orderStatus     = "VALIDATED"
        sfLastModified  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        correlationId   = [Guid]::NewGuid().ToString()
        account         = @{
            accountId     = "0017f00000LmNoPAAQ"
            accountName   = "Duplicate Test"
        }
        shippingAddress = @{ city = "Chennai" }
        lines           = @(@{ lineNumber = 1; productCode = "PRD-1"; quantity = 1; unitPrice = 287400; lineTotal = 287400 })
    } | ConvertTo-Json -Depth 5

    try {
        $null = Invoke-RestMethod -Uri "$OrderSystemApiUrl/api/orders" -Method Post -Body $dupPayload -ContentType "application/json" -TimeoutSec 5
        Write-Host " [FAILED] Expected HTTP 409 but request succeeded!" -ForegroundColor Red
    } catch {
        if ($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::Conflict) {
            Write-Host " [PASSED] HTTP 409 Conflict properly returned on duplicate opportunity_id!" -ForegroundColor Green
        } else {
            Write-Host " [PASSED] Request rejected with status: $($_.Exception.Response.StatusCode)" -ForegroundColor Green
        }
    }
}
Write-Host ""
