#!/usr/bin/env bash
# ==============================================================================
# audit_render_env.sh — Render Environment Variable Configuration Audit
# Platform: All-in-One Donation & Crowdfunding Platform
# Author:   SRE Certification Suite v1.0
#
# Usage:
#   chmod +x audit_render_env.sh
#   ./audit_render_env.sh
#
# Run this INSIDE the Render container (via Shell tab) or locally before deploy.
# It validates required env vars are set and tests SMTP connectivity.
# ==============================================================================

set -uo pipefail

# ─────────────────────────────────────────────────────────────
# TERMINAL COLORS
# ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

log_pass() { echo -e "${GREEN}[PASS]${RESET} $1"; ((PASS_COUNT++)); }
log_fail() { echo -e "${RED}[FAIL]${RESET} $1"; ((FAIL_COUNT++)); }
log_warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; ((WARN_COUNT++)); }
log_info() { echo -e "${CYAN}[INFO]${RESET} $1"; }
log_header() {
    echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${CYAN}  $1${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}"
}

mask_secret() {
    local val="$1"
    local len="${#val}"
    if [[ $len -le 4 ]]; then
        echo "****"
    else
        echo "${val:0:3}...${val: -3}"
    fi
}

log_header "RENDER ENVIRONMENT VARIABLE AUDIT"
echo -e "  Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo ""

# ==============================================================================
# SECTION 1: Required Environment Variable Audit
# ==============================================================================
log_header "1. Required Environment Variables"

# Define: var_name|description|is_secret|example_value
declare -a ENV_CHECKS=(
    "SPRING_DATASOURCE_URL|Neon PostgreSQL JDBC connection URL|true|jdbc:postgresql://ep-xxx.neon.tech/neondb?sslmode=require"
    "SPRING_DATASOURCE_USERNAME|Neon DB username|false|neondb_owner"
    "SPRING_DATASOURCE_PASSWORD|Neon DB password|true|your_neon_password"
    "RAZORPAY_KEY_ID|Razorpay API Key ID (rzp_live_... or rzp_test_...)|false|rzp_live_xxxxxxxxxxxx"
    "RAZORPAY_KEY_SECRET|Razorpay API Key Secret|true|your_razorpay_key_secret"
    "RAZORPAY_WEBHOOK_SECRET|Razorpay Webhook Secret (from Dashboard)|true|your_webhook_secret"
    "SPRING_MAIL_HOST|SMTP server hostname|false|smtp.gmail.com"
    "SPRING_MAIL_PORT|SMTP server port (587 for TLS, 465 for SSL)|false|587"
    "SPRING_MAIL_USERNAME|SMTP sender email address|false|donations@yourorg.com"
    "SPRING_MAIL_PASSWORD|SMTP App Password (NOT account password for Gmail)|true|your_gmail_app_password"
    "JWT_SECRET|64-char hex JWT signing secret|true|your_64_char_hex_secret"
    "ORG_NAME|Organisation legal name for 80G receipts|false|ImpactFund Humanitarian Foundation"
    "ORG_PAN|Organisation PAN number for 80G tax certificates|false|AAATI9981K"
    "ORG_80G_CERT|80G Certificate registration number|false|CIT(E)/80G/2023-24/A/10042"
    "ORG_REG_NO|NGO registration number|false|NGO-MH-2023-889971"
    "ORG_ADDRESS|Organisation registered address|false|Level 5 BKC Mumbai 400051"
)

for entry in "${ENV_CHECKS[@]}"; do
    IFS='|' read -r var_name description is_secret example <<< "$entry"

    if [[ -n "${!var_name:-}" ]]; then
        if [[ "$is_secret" == "true" ]]; then
            log_pass "$var_name is SET [$(mask_secret "${!var_name}")] — $description"
        else
            log_pass "$var_name is SET [${!var_name}] — $description"
        fi
    else
        log_fail "$var_name is MISSING — $description"
        echo -e "         ${YELLOW}Example:${RESET} $var_name=$example"
    fi
done

# ==============================================================================
# SECTION 2: Optional but Recommended Variables
# ==============================================================================
log_header "2. Optional / Recommended Variables"

declare -a OPT_CHECKS=(
    "FRONTEND_URL|CORS allowed frontend URL (comma-separated)"
    "HIBERNATE_DDL_AUTO|Should be 'validate' in production (not 'update')"
    "PORT|Server port (Render sets this automatically)"
)

for entry in "${OPT_CHECKS[@]}"; do
    IFS='|' read -r var_name description <<< "$entry"
    if [[ -n "${!var_name:-}" ]]; then
        log_pass "$var_name is SET [${!var_name}] — $description"
    else
        log_warn "$var_name is not set (optional) — $description"
    fi
done

# ─────────────────────────────────────────────────────────────
# SECTION 3: SMTP Connectivity Test
# ─────────────────────────────────────────────────────────────
log_header "3. Outbound SMTP Connectivity Test"

SMTP_HOST="${SPRING_MAIL_HOST:-smtp.gmail.com}"
SMTP_PORT="${SPRING_MAIL_PORT:-587}"

log_info "Testing TCP reachability to $SMTP_HOST:$SMTP_PORT ..."

# Method 1: nc (netcat)
if command -v nc &>/dev/null; then
    if nc -z -w 5 "$SMTP_HOST" "$SMTP_PORT" 2>/dev/null; then
        log_pass "nc: TCP connection to $SMTP_HOST:$SMTP_PORT succeeded"
    else
        log_fail "nc: TCP connection to $SMTP_HOST:$SMTP_PORT FAILED"
        log_warn "Possible cause: Render's outbound firewall blocks port $SMTP_PORT"
        log_warn "Workaround: Use port 465 (SMTPS) or a Render-compatible SMTP relay (SendGrid, Mailgun)"
    fi
else
    log_warn "nc (netcat) not found — skipping TCP reachability test via nc"
fi

# Method 2: curl SMTP probe
if command -v curl &>/dev/null; then
    log_info "Testing SMTP EHLO handshake via curl..."
    CURL_SMTP_RESULT=$(timeout 10 curl -s --max-time 10 "smtp://${SMTP_HOST}:${SMTP_PORT}" \
        --ssl-reqd \
        --url "smtp://${SMTP_HOST}:${SMTP_PORT}" \
        2>&1 | head -5 || echo "FAILED")

    if echo "$CURL_SMTP_RESULT" | grep -qi "EHLO\|220\|250"; then
        log_pass "curl: SMTP EHLO handshake with $SMTP_HOST:$SMTP_PORT successful"
    elif echo "$CURL_SMTP_RESULT" | grep -qi "timed out\|refused\|FAILED"; then
        log_fail "curl: SMTP connection to $SMTP_HOST:$SMTP_PORT failed"
    else
        log_info "curl SMTP test result: $(echo "$CURL_SMTP_RESULT" | head -2)"
    fi
fi

# Method 3: openssl TLS probe (most reliable)
if command -v openssl &>/dev/null; then
    log_info "Testing STARTTLS handshake via openssl..."
    OPENSSL_RESULT=$(echo "" | timeout 8 openssl s_client \
        -connect "${SMTP_HOST}:${SMTP_PORT}" \
        -starttls smtp \
        -quiet \
        2>&1 | head -3 || echo "FAILED")

    if echo "$OPENSSL_RESULT" | grep -qi "Cipher\|CONNECTED\|250"; then
        log_pass "openssl: STARTTLS handshake to $SMTP_HOST:$SMTP_PORT succeeded"
    elif echo "$OPENSSL_RESULT" | grep -qi "timed out\|refused\|error"; then
        log_fail "openssl: STARTTLS handshake FAILED — $OPENSSL_RESULT"
    else
        log_info "openssl result: $(echo "$OPENSSL_RESULT" | head -2)"
    fi
fi

# ─────────────────────────────────────────────────────────────
# SECTION 4: Database Connectivity Test
# ─────────────────────────────────────────────────────────────
log_header "4. Neon PostgreSQL Connection Reachability"

if [[ -n "${SPRING_DATASOURCE_URL:-}" ]]; then
    # Extract host and port from JDBC URL
    # Format: jdbc:postgresql://ep-xxx.neon.tech/dbname?sslmode=require
    DB_HOST=$(echo "${SPRING_DATASOURCE_URL}" | sed 's|jdbc:postgresql://||' | cut -d'/' -f1 | cut -d':' -f1)
    DB_PORT=$(echo "${SPRING_DATASOURCE_URL}" | sed 's|jdbc:postgresql://||' | cut -d'/' -f1 | cut -d':' -f2)
    DB_PORT="${DB_PORT:-5432}"

    log_info "Extracted DB host: $DB_HOST port: $DB_PORT"

    if command -v nc &>/dev/null; then
        if nc -z -w 10 "$DB_HOST" "$DB_PORT" 2>/dev/null; then
            log_pass "TCP connection to Neon DB $DB_HOST:$DB_PORT succeeded"
        else
            log_fail "TCP connection to Neon DB $DB_HOST:$DB_PORT FAILED"
        fi
    elif command -v curl &>/dev/null; then
        if curl -s --connect-timeout 5 "telnet://${DB_HOST}:${DB_PORT}" &>/dev/null; then
            log_pass "Neon DB $DB_HOST:$DB_PORT is reachable"
        else
            log_warn "Could not test Neon DB TCP reachability (curl telnet not supported)"
        fi
    fi
else
    log_warn "SPRING_DATASOURCE_URL not set — skipping DB connectivity check"
fi

# ─────────────────────────────────────────────────────────────
# SECTION 5: JVM / Runtime Environment Check
# ─────────────────────────────────────────────────────────────
log_header "5. JVM Runtime Environment"

if command -v java &>/dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -1)
    log_info "Java version: $JAVA_VERSION"
    JAVA_MAJOR=$(java -version 2>&1 | grep -oP '(?<=version ")[^"]*' | cut -d'.' -f1)
    if [[ "$JAVA_MAJOR" -ge 21 ]]; then
        log_pass "Java $JAVA_MAJOR >= 21 (required for Spring Boot 3.3+)"
    else
        log_fail "Java $JAVA_MAJOR is too old — Spring Boot 3.3+ requires Java 21+"
    fi
fi

log_info "Available memory: $(free -m 2>/dev/null | awk '/Mem:/{print $2}' || echo "N/A") MB"
log_info "Container OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || uname -a)"

# ─────────────────────────────────────────────────────────────
# SECTION 6: Render-Specific Configuration Recommendations
# ─────────────────────────────────────────────────────────────
log_header "6. Render Configuration Recommendations"

echo -e ""
echo -e "  ${BOLD}${CYAN}Render Dashboard Checklist:${RESET}"
echo -e "  ┌─────────────────────────────────────────────────────────────────┐"
echo -e "  │  Service Settings (Settings tab):                               │"
echo -e "  │    Docker Command:    (leave blank, uses Dockerfile CMD)        │"
echo -e "  │    Health Check Path: /actuator/health                          │"
echo -e "  │    Auto-Deploy:       Yes (on push to main)                     │"
echo -e "  │                                                                 │"
echo -e "  │  Environment Variables (Environment tab):                       │"
echo -e "  │    SPRING_DATASOURCE_URL  = jdbc:postgresql://..neon.tech/..    │"
echo -e "  │    SPRING_DATASOURCE_USERNAME = neondb_owner                   │"
echo -e "  │    SPRING_DATASOURCE_PASSWORD = <neon_password>                │"
echo -e "  │    RAZORPAY_KEY_ID        = rzp_live_xxxxxxxxxxxx              │"
echo -e "  │    RAZORPAY_KEY_SECRET    = <razorpay_key_secret>              │"
echo -e "  │    RAZORPAY_WEBHOOK_SECRET= <razorpay_webhook_secret>          │"
echo -e "  │    SPRING_MAIL_HOST       = smtp.gmail.com                     │"
echo -e "  │    SPRING_MAIL_PORT       = 587                                │"
echo -e "  │    SPRING_MAIL_USERNAME   = donations@yourorg.com              │"
echo -e "  │    SPRING_MAIL_PASSWORD   = <16-char Gmail App Password>       │"
echo -e "  │    JWT_SECRET             = <64-char random hex>               │"
echo -e "  │    ORG_NAME               = Your NGO Name                      │"
echo -e "  │    ORG_PAN                = AAATI9981K                         │"
echo -e "  │    ORG_80G_CERT           = CIT(E)/80G/2023-24/A/10042        │"
echo -e "  │    ORG_REG_NO             = NGO-MH-2023-889971                 │"
echo -e "  │    ORG_ADDRESS            = Your Registered Address             │"
echo -e "  │    HIBERNATE_DDL_AUTO     = validate   ← CRITICAL IN PROD!    │"
echo -e "  └─────────────────────────────────────────────────────────────────┘"

echo ""
echo -e "  ${BOLD}${CYAN}Gmail App Password Setup (if using Gmail SMTP):${RESET}"
echo -e "  1. Enable 2-Step Verification on your Google account"
echo -e "  2. Go to: https://myaccount.google.com/apppasswords"
echo -e "  3. App: 'Other (Custom name)' → 'DonationPlatform SMTP'"
echo -e "  4. Copy the 16-char generated password (no spaces)"
echo -e "  5. Set as SPRING_MAIL_PASSWORD on Render"
echo ""
echo -e "  ${BOLD}${CYAN}Razorpay Webhook Registration:${RESET}"
echo -e "  1. Go to: https://dashboard.razorpay.com/app/webhooks"
echo -e "  2. Click 'Add New Webhook'"
echo -e "  3. Webhook URL: https://your-app.onrender.com/api/v1/webhooks/razorpay"
echo -e "  4. Secret: (generate and copy to RAZORPAY_WEBHOOK_SECRET)"
echo -e "  5. Active Events: ✓ payment.captured  ✓ payment.failed"
echo ""

# ─────────────────────────────────────────────────────────────
# FINAL AUDIT SUMMARY
# ─────────────────────────────────────────────────────────────
log_header "AUDIT SUMMARY"
echo ""
echo -e "  ${GREEN}PASSED: $PASS_COUNT${RESET}"
echo -e "  ${YELLOW}WARNINGS: $WARN_COUNT${RESET}"
echo -e "  ${RED}FAILED: $FAIL_COUNT${RESET}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}✅  ENVIRONMENT AUDIT PASSED — Ready to receive traffic.${RESET}"
else
    echo -e "  ${RED}${BOLD}❌  AUDIT FAILED — $FAIL_COUNT critical configuration(s) missing.${RESET}"
    echo -e "  ${RED}     Fix the above FAILED items before enabling production traffic.${RESET}"
fi
echo ""
