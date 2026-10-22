# ==============================================================================
# Test-SmtpConnectivity.ps1 — Windows/PowerShell SMTP Connectivity Verifier
# Platform: All-in-One Donation & Crowdfunding Platform
# Author:   SRE Certification Suite v1.0
#
# Usage (run in PowerShell):
#   .\scripts\Test-SmtpConnectivity.ps1
#   .\scripts\Test-SmtpConnectivity.ps1 -SmtpHost "smtp.gmail.com" -SmtpPort 587 -FromEmail "you@gmail.com" -AppPassword "xxxx xxxx xxxx xxxx" -ToEmail "test@example.com"
# ==============================================================================

param(
    [string]$SmtpHost     = "smtp.gmail.com",
    [int]   $SmtpPort     = 587,
    [string]$FromEmail    = $env:SPRING_MAIL_USERNAME,
    [string]$AppPassword  = $env:SPRING_MAIL_PASSWORD,
    [string]$ToEmail      = $env:SPRING_MAIL_USERNAME   # Send test to self
)

$PASS = 0
$FAIL = 0

function Write-Pass($msg) { Write-Host "[PASS] $msg" -ForegroundColor Green;  $script:PASS++ }
function Write-Fail($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red;    $script:FAIL++ }
function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SMTP CONNECTIVITY & AUTHENTICATION TEST" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────────────────────
# STEP 1: TCP Port Reachability
# ─────────────────────────────────────────────────────────────
Write-Host "━━━ STEP 1: TCP Port Reachability ━━━" -ForegroundColor Cyan
Write-Info "Testing TCP to ${SmtpHost}:${SmtpPort} ..."

try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connectTask = $tcpClient.ConnectAsync($SmtpHost, $SmtpPort)
    $connected = $connectTask.Wait(5000)  # 5 second timeout

    if ($connected -and $tcpClient.Connected) {
        Write-Pass "TCP connection to ${SmtpHost}:${SmtpPort} succeeded"
        $tcpClient.Close()
    } else {
        Write-Fail "TCP connection to ${SmtpHost}:${SmtpPort} TIMED OUT"
        Write-Warn "Possible causes: firewall blocking port $SmtpPort, or wrong SMTP host"
    }
} catch {
    Write-Fail "TCP connection FAILED: $_"
}

# ─────────────────────────────────────────────────────────────
# STEP 2: Validate Credentials Are Set
# ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "━━━ STEP 2: Credential Validation ━━━" -ForegroundColor Cyan

if ([string]::IsNullOrWhiteSpace($FromEmail)) {
    Write-Fail "FromEmail / SPRING_MAIL_USERNAME is empty. Set the parameter or environment variable."
} else {
    Write-Pass "SPRING_MAIL_USERNAME is set: $FromEmail"
}

if ([string]::IsNullOrWhiteSpace($AppPassword)) {
    Write-Fail "AppPassword / SPRING_MAIL_PASSWORD is empty. Generate a Gmail App Password."
    Write-Warn "Go to: https://myaccount.google.com/apppasswords"
} else {
    $masked = $AppPassword.Substring(0, [Math]::Min(3, $AppPassword.Length)) + "..." + $AppPassword.Substring([Math]::Max(0, $AppPassword.Length - 3))
    Write-Pass "SPRING_MAIL_PASSWORD is set: $masked"
}

# ─────────────────────────────────────────────────────────────
# STEP 3: Send Test Email via .NET SmtpClient with STARTTLS
# ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "━━━ STEP 3: Send Test Email via STARTTLS ━━━" -ForegroundColor Cyan

if ([string]::IsNullOrWhiteSpace($FromEmail) -or [string]::IsNullOrWhiteSpace($AppPassword)) {
    Write-Warn "Skipping email send test — credentials not set"
} else {
    Write-Info "Sending test email from $FromEmail to $ToEmail via ${SmtpHost}:${SmtpPort} ..."

    try {
        $smtpClient = New-Object System.Net.Mail.SmtpClient($SmtpHost, $SmtpPort)
        $smtpClient.EnableSsl = $true
        $smtpClient.Credentials = New-Object System.Net.NetworkCredential($FromEmail, $AppPassword)
        $smtpClient.Timeout = 15000  # 15 seconds

        $mailMessage = New-Object System.Net.Mail.MailMessage
        $mailMessage.From = New-Object System.Net.Mail.MailAddress($FromEmail, "Donation Platform SRE")
        $mailMessage.To.Add($ToEmail)
        $mailMessage.Subject = "[SRE TEST] SMTP Connectivity Verification — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $mailMessage.Body = @"
This is an automated SMTP connectivity test from the All-in-One Donation Platform SRE certification suite.

Test Details:
  SMTP Host:    $SmtpHost
  SMTP Port:    $SmtpPort
  From:         $FromEmail
  Timestamp:    $(Get-Date -Format 'o')

If you received this email, the SMTP configuration is working correctly.
The platform is ready for 80G tax receipt email dispatch.

-- SRE Certification Suite
"@
        $mailMessage.IsBodyHtml = $false

        $smtpClient.Send($mailMessage)
        Write-Pass "Test email sent successfully to $ToEmail"
        Write-Info "Check your inbox at $ToEmail for the SRE test message."
        $smtpClient.Dispose()
        $mailMessage.Dispose()

    } catch [System.Net.Mail.SmtpException] {
        Write-Fail "SmtpException: $($_.Exception.Message)"
        if ($_.Exception.Message -match "5\.7\.8|credentials|Authentication") {
            Write-Warn "Authentication failed. For Gmail:"
            Write-Warn "  1. Enable 2-Step Verification at https://myaccount.google.com/security"
            Write-Warn "  2. Generate App Password at https://myaccount.google.com/apppasswords"
            Write-Warn "  3. Use the 16-char App Password (NOT your Google account password)"
            Write-Warn "  4. Remove spaces from the App Password when setting SPRING_MAIL_PASSWORD"
        } elseif ($_.Exception.Message -match "timeout|timed out") {
            Write-Warn "Connection timed out. Try port 465 with SSL instead of 587 with STARTTLS."
        }
    } catch {
        Write-Fail "Unexpected error: $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────────────────────────────
# STEP 4: Environment Variable Summary for Render
# ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "━━━ STEP 4: Render Environment Variable Reference ━━━" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Copy these exact key names to Render Dashboard → Environment tab:" -ForegroundColor White
Write-Host ""

$renderEnvVars = @(
    @{ Key = "SPRING_DATASOURCE_URL";       Value = "jdbc:postgresql://ep-xxx-yyy.neon.tech/neondb?sslmode=require"; Secret = $false },
    @{ Key = "SPRING_DATASOURCE_USERNAME";  Value = "neondb_owner";                                                    Secret = $false },
    @{ Key = "SPRING_DATASOURCE_PASSWORD";  Value = "<your_neon_password>";                                            Secret = $true  },
    @{ Key = "RAZORPAY_KEY_ID";             Value = "rzp_live_xxxxxxxxxxxx";                                           Secret = $false },
    @{ Key = "RAZORPAY_KEY_SECRET";         Value = "<your_razorpay_key_secret>";                                      Secret = $true  },
    @{ Key = "RAZORPAY_WEBHOOK_SECRET";     Value = "<your_razorpay_webhook_secret>";                                  Secret = $true  },
    @{ Key = "SPRING_MAIL_HOST";            Value = "smtp.gmail.com";                                                  Secret = $false },
    @{ Key = "SPRING_MAIL_PORT";            Value = "587";                                                              Secret = $false },
    @{ Key = "SPRING_MAIL_USERNAME";        Value = "donations@yourorg.com";                                            Secret = $false },
    @{ Key = "SPRING_MAIL_PASSWORD";        Value = "<16-char-gmail-app-password-no-spaces>";                           Secret = $true  },
    @{ Key = "JWT_SECRET";                  Value = "<64-char-random-hex-string>";                                      Secret = $true  },
    @{ Key = "ORG_NAME";                    Value = "ImpactFund Humanitarian Foundation";                               Secret = $false },
    @{ Key = "ORG_PAN";                     Value = "AAATI9981K";                                                       Secret = $false },
    @{ Key = "ORG_80G_CERT";               Value = "CIT(E)/80G/2023-24/A/10042";                                       Secret = $false },
    @{ Key = "ORG_REG_NO";                  Value = "NGO-MH-2023-889971";                                               Secret = $false },
    @{ Key = "ORG_ADDRESS";                 Value = "Level 5, Impact Towers, BKC, Mumbai - 400051";                     Secret = $false },
    @{ Key = "HIBERNATE_DDL_AUTO";          Value = "validate";                                                         Secret = $false }
)

foreach ($envVar in $renderEnvVars) {
    $secretTag = if ($envVar.Secret) { " [SECRET]" } else { "" }
    Write-Host ("  {0,-35} = {1}{2}" -f $envVar.Key, $envVar.Value, $secretTag) -ForegroundColor $(if ($envVar.Secret) { "Yellow" } else { "White" })
}

Write-Host ""
Write-Host "  IMPORTANT: Set HIBERNATE_DDL_AUTO=validate in production!" -ForegroundColor Red
Write-Host "  This prevents Hibernate from auto-altering schema — Flyway owns migrations." -ForegroundColor Red

# ─────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  AUDIT SUMMARY" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  PASSED:  $PASS" -ForegroundColor Green
Write-Host "  FAILED:  $FAIL" -ForegroundColor Red
Write-Host ""

if ($FAIL -eq 0) {
    Write-Host "  ✅  SMTP CONFIGURATION VERIFIED — Ready for production email dispatch." -ForegroundColor Green
} else {
    Write-Host "  ❌  CONFIGURATION ISSUES FOUND — Fix $FAIL item(s) before going live." -ForegroundColor Red
}
Write-Host ""
