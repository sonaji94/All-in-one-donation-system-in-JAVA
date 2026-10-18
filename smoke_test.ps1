# ==============================================================================
# Automated Production Smoke Test Harness (PowerShell for Windows)
# All-in-One Donation & Crowdfunding Platform
# Usage: .\smoke_test.ps1 -BaseUrl "https://donation-platform-api.onrender.com"
# ==============================================================================

param(
    [string]$BaseUrl = "http://localhost:8080"
)

$BaseUrl = $BaseUrl.TrimEnd('/')
$ErrorActionPreference = "Stop"

Write-Host "==============================================================================" -ForegroundColor Blue
Write-Host "   PRODUCTION SMOKE TEST: ALL-IN-ONE DONATION PLATFORM   " -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Blue
Write-Host "Target URL : $BaseUrl"
Write-Host "Started At : $(Get-Date -Format 'o')`n"

$totalTests = 5
$passedTests = 0

function Log-Pass($msg) {
    Write-Host " [PASS] $msg" -ForegroundColor Green
    $script:passedTests++
}

function Log-Fail($msg, $reason) {
    Write-Host " [FAIL] $msg" -ForegroundColor Red
    Write-Host "Reason : $reason" -ForegroundColor Red
    Write-Host "`nSmoke tests aborted." -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------------------------
# TEST 1: Actuator Health Check
# ------------------------------------------------------------------------------
Write-Host "Phase 1: Actuator Health Endpoint Check..." -ForegroundColor Yellow
try {
    $healthResp = Invoke-RestMethod -Uri "$BaseUrl/actuator/health" -Method Get
    if ($healthResp.status -eq "UP") {
        Log-Pass "Health check responded HTTP 200 with status '$($healthResp.status)'"
    } else {
        Log-Fail "Health check returned unexpected status" ($healthResp | ConvertTo-Json)
    }
} catch {
    Log-Fail "Health check failed" $_.Exception.Message
}

# ------------------------------------------------------------------------------
# TEST 2: Register New Donor User
# ------------------------------------------------------------------------------
Write-Host "`nPhase 2: User Registration (POST /api/v1/auth/register)..." -ForegroundColor Yellow
$uniqueId = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$donorEmail = "donor_$uniqueId@smoketest.local"
$donorPassword = "TestPassword@123"
$donorName = "Smoke Test Donor $uniqueId"

$registerBody = @{
    name = $donorName
    email = $donorEmail
    password = $donorPassword
    role = "ROLE_USER"
} | ConvertTo-Json

try {
    $regResp = Invoke-RestMethod -Uri "$BaseUrl/api/v1/auth/register" -Method Post -Body $registerBody -ContentType "application/json"
    if ($regResp.success -eq $true) {
        Log-Pass "User registration succeeded for email: $donorEmail"
    } else {
        Log-Fail "Registration returned success=false" ($regResp | ConvertTo-Json)
    }
} catch {
    Log-Fail "User registration failed" $_.Exception.Message
}

# ------------------------------------------------------------------------------
# TEST 3: User Authentication & JWT Extraction (POST /api/v1/auth/login)
# ------------------------------------------------------------------------------
Write-Host "`nPhase 3: User Authentication (POST /api/v1/auth/login)..." -ForegroundColor Yellow
$loginBody = @{
    email = $donorEmail
    password = $donorPassword
} | ConvertTo-Json

try {
    $loginResp = Invoke-RestMethod -Uri "$BaseUrl/api/v1/auth/login" -Method Post -Body $loginBody -ContentType "application/json"
    $jwtToken = $loginResp.data.token
    if ($jwtToken) {
        Log-Pass "Authentication succeeded. Bearer JWT obtained ($($jwtToken.Length) chars)"
    } else {
        Log-Fail "JWT token missing from login response" ($loginResp | ConvertTo-Json)
    }
} catch {
    Log-Fail "Authentication failed" $_.Exception.Message
}

# ------------------------------------------------------------------------------
# TEST 4: Query Active Campaigns (GET /api/v1/campaigns)
# ------------------------------------------------------------------------------
Write-Host "`nPhase 4: Fetch Active Campaigns (GET /api/v1/campaigns)..." -ForegroundColor Yellow
try {
    $campResp = Invoke-RestMethod -Uri "$BaseUrl/api/v1/campaigns" -Method Get
    if ($campResp.data.Count -gt 0) {
        $campaignId = $campResp.data[0].id
        $campaignTitle = $campResp.data[0].title
        Log-Pass "Retrieved $($campResp.data.Count) active campaign(s). Selected ID: $campaignId ('$campaignTitle')"
    } else {
        Write-Host "   Notice: No active campaign found. Creating a campaign for testing..." -ForegroundColor Cyan
        $newCampBody = @{
            title = "Smoke Test Emergency Initiative"
            description = "Automated campaign generated during deployment smoke test execution."
            targetAmount = 100000.00
        } | ConvertTo-Json
        $headers = @{ Authorization = "Bearer $jwtToken" }
        $newCampResp = Invoke-RestMethod -Uri "$BaseUrl/api/v1/campaigns" -Method Post -Headers $headers -Body $newCampBody -ContentType "application/json"
        $campaignId = $newCampResp.data.id
        Log-Pass "Dynamically created test campaign ID: $campaignId"
    }
} catch {
    Log-Fail "Failed to query active campaigns" $_.Exception.Message
}

# ------------------------------------------------------------------------------
# TEST 5: Create Razorpay Donation Order (POST /api/v1/donations/order)
# ------------------------------------------------------------------------------
Write-Host "`nPhase 5: Create Razorpay Donation Order (POST /api/v1/donations/order)..." -ForegroundColor Yellow
$orderBody = @{
    campaignId = $campaignId
    amount = 250.00
    donorName = $donorName
    donorEmail = $donorEmail
    isAnonymous = $false
} | ConvertTo-Json

try {
    $headers = @{ Authorization = "Bearer $jwtToken" }
    $orderResp = Invoke-RestMethod -Uri "$BaseUrl/api/v1/donations/order" -Method Post -Headers $headers -Body $orderBody -ContentType "application/json"
    $rzpOrderId = $orderResp.data.razorpayOrderId
    $amount = $orderResp.data.amount
    $currency = $orderResp.data.currency
    $keyId = $orderResp.data.keyId

    if ($rzpOrderId) {
        Log-Pass "Donation order created successfully! Razorpay Order ID: $rzpOrderId ($currency $amount, Key: $keyId)"
    } else {
        Log-Fail "Razorpay order ID missing from response payload" ($orderResp | ConvertTo-Json)
    }
} catch {
    Log-Fail "Failed to create donation order" $_.Exception.Message
}

# ------------------------------------------------------------------------------
# SUMMARY REPORT
# ------------------------------------------------------------------------------
Write-Host "`n==============================================================================" -ForegroundColor Blue
Write-Host "   ALL SMOKE TESTS COMPLETED SUCCESSFULLY! ($passedTests/$totalTests PASSED)   " -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Blue
Write-Host "Platform is live, healthy, authenticated, and ready to accept live transactions."
