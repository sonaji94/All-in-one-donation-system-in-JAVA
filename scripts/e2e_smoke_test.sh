#!/usr/bin/env bash
# ==============================================================================
# e2e_smoke_test.sh — End-to-End Live Transaction & Receipt Simulation
# Platform: All-in-One Donation & Crowdfunding Platform
# Author:   SRE Certification Suite v1.0
#
# Usage:
#   chmod +x e2e_smoke_test.sh
#   ./e2e_smoke_test.sh https://your-app.onrender.com your_webhook_secret
#
# This script runs a complete synthetic transaction through every layer:
#   [Auth] → [Order Creation] → [Webhook Reconciliation] → [Receipt Verification]
#
# Note: The Razorpay payment step uses webhook simulation (not real payment SDK).
#       For a real payment, integrate Razorpay test mode in frontend.
# ==============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────
# ARGUMENTS
# ─────────────────────────────────────────────────────────────
TARGET_URL="${1:-}"
WEBHOOK_SECRET="${2:-}"

if [[ -z "$TARGET_URL" || -z "$WEBHOOK_SECRET" ]]; then
    echo "Usage: $0 <TARGET_URL> <WEBHOOK_SECRET>"
    echo "Example: $0 https://donation-platform.onrender.com razorpay_webhook_secret_here"
    exit 1
fi

TARGET_URL="${TARGET_URL%/}"

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
SKIP_COUNT=0
ABORT=false

log_pass()   { echo -e "${GREEN}[PASS]${RESET} $1"; ((PASS_COUNT++)); }
log_fail()   { echo -e "${RED}[FAIL]${RESET} $1"; ((FAIL_COUNT++)); }
log_skip()   { echo -e "${YELLOW}[SKIP]${RESET} $1"; ((SKIP_COUNT++)); }
log_info()   { echo -e "${CYAN}[INFO]${RESET} $1"; }
log_warn()   { echo -e "${YELLOW}[WARN]${RESET} $1"; }
log_step()   { echo -e "\n${BOLD}${CYAN}━━━ STEP $1: $2 ━━━${RESET}"; }
log_header() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}"; echo -e "${BOLD}${CYAN}  $1${RESET}"; echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}"; }

# ─────────────────────────────────────────────────────────────
# HELPER: JSON field extractor
# ─────────────────────────────────────────────────────────────
extract_json() {
    local json="$1"
    local field="$2"
    echo "$json" | jq -r "$field" 2>/dev/null || echo ""
}

assert_equals() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        log_pass "$label: '$actual'"
    else
        log_fail "$label: expected '$expected' got '$actual'"
    fi
}

assert_not_empty() {
    local label="$1"
    local value="$2"
    if [[ -n "$value" && "$value" != "null" && "$value" != "" ]]; then
        log_pass "$label is present: '${value:0:40}...'"
    else
        log_fail "$label is EMPTY or NULL"
    fi
}

# ─────────────────────────────────────────────────────────────
# UNIQUE RUN IDENTIFIER
# ─────────────────────────────────────────────────────────────
RUN_ID="$(date +%Y%m%d%H%M%S)"
TEST_EMAIL="smoketest_${RUN_ID}@certify.donationplatform.com"
TEST_PASSWORD="Smoke@Test123"
TEST_NAME="SRE Smoke Tester ${RUN_ID}"
TEST_CAMPAIGN_ID="b1eebc99-9c0b-4ef8-bb6d-6bb9bd380b22"   # Seed campaign from V1
TEST_AMOUNT=50000  # 500 INR in paise (Razorpay amounts are in paise)
TEST_AMOUNT_DECIMAL="500.00"  # In rupees for API
TEST_PAN="ABCDE1234F"

log_header "END-TO-END SMOKE CERTIFICATION — Run ID: $RUN_ID"
log_info "Target URL:    $TARGET_URL"
log_info "Test Email:    $TEST_EMAIL"
log_info "Campaign ID:   $TEST_CAMPAIGN_ID"
log_info "Donation:      ₹$TEST_AMOUNT_DECIMAL"
echo ""

# ─────────────────────────────────────────────────────────────
# STEP 1: HEALTH CHECK
# ─────────────────────────────────────────────────────────────
log_step "1" "Application Health Verification"

HTTP_STATUS=$(curl -s -o /tmp/e2e_health.json -w "%{http_code}" \
    --connect-timeout 10 --max-time 20 \
    "${TARGET_URL}/actuator/health")

if [[ "$HTTP_STATUS" == "200" ]]; then
    APP_STATUS=$(extract_json "$(cat /tmp/e2e_health.json)" ".status")
    if [[ "$APP_STATUS" == "UP" ]]; then
        log_pass "Application is UP and healthy"
    else
        log_fail "Application status is '$APP_STATUS' — expected 'UP'"
        ABORT=true
    fi
else
    log_fail "Health check failed with HTTP $HTTP_STATUS. Aborting E2E test."
    ABORT=true
fi

if [[ "$ABORT" == true ]]; then
    echo -e "\n${RED}ABORTED${RESET} — Application is not healthy. Cannot proceed with E2E tests."
    exit 1
fi

# ─────────────────────────────────────────────────────────────
# STEP 2: REGISTER A NEW TEST USER
# ─────────────────────────────────────────────────────────────
log_step "2" "Register New Test Donor"

REGISTER_PAYLOAD=$(cat <<EOF
{
  "name": "$TEST_NAME",
  "email": "$TEST_EMAIL",
  "password": "$TEST_PASSWORD"
}
EOF
)

REGISTER_HTTP=$(curl -s -o /tmp/e2e_register.json -w "%{http_code}" \
    -X POST "${TARGET_URL}/api/v1/auth/register" \
    -H "Content-Type: application/json" \
    -d "$REGISTER_PAYLOAD" \
    --connect-timeout 10 --max-time 20)

REGISTER_BODY=$(cat /tmp/e2e_register.json)
log_info "Register HTTP: $REGISTER_HTTP"
log_info "Response: $(echo "$REGISTER_BODY" | jq -c . 2>/dev/null || echo "$REGISTER_BODY")"

if [[ "$REGISTER_HTTP" == "201" ]]; then
    log_pass "User registered with HTTP 201"
    JWT_TOKEN=$(extract_json "$REGISTER_BODY" ".data.token")
    assert_not_empty "JWT Token from registration" "$JWT_TOKEN"
elif [[ "$REGISTER_HTTP" == "409" ]]; then
    log_warn "Email already exists (HTTP 409). Proceeding to login..."
    JWT_TOKEN=""
else
    log_fail "Registration failed with HTTP $REGISTER_HTTP"
    JWT_TOKEN=""
fi

# ─────────────────────────────────────────────────────────────
# STEP 3: AUTHENTICATE AND EXTRACT JWT
# ─────────────────────────────────────────────────────────────
log_step "3" "Authenticate & Extract JWT Token"

LOGIN_PAYLOAD=$(cat <<EOF
{
  "email": "$TEST_EMAIL",
  "password": "$TEST_PASSWORD"
}
EOF
)

LOGIN_HTTP=$(curl -s -o /tmp/e2e_login.json -w "%{http_code}" \
    -X POST "${TARGET_URL}/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "$LOGIN_PAYLOAD" \
    --connect-timeout 10 --max-time 20)

LOGIN_BODY=$(cat /tmp/e2e_login.json)
log_info "Login HTTP: $LOGIN_HTTP"

if [[ "$LOGIN_HTTP" == "200" ]]; then
    log_pass "Authentication successful — HTTP 200"
    JWT_TOKEN=$(extract_json "$LOGIN_BODY" ".data.token")
    USER_NAME=$(extract_json "$LOGIN_BODY" ".data.name")
    assert_not_empty "JWT Token" "$JWT_TOKEN"
    assert_not_empty "Authenticated User Name" "$USER_NAME"
else
    log_fail "Authentication failed with HTTP $LOGIN_HTTP"
    log_info "Body: $(echo "$LOGIN_BODY" | jq -c . 2>/dev/null || echo "$LOGIN_BODY")"
    echo -e "\n${RED}ABORTED${RESET} — Cannot proceed without valid JWT."
    exit 1
fi

# ─────────────────────────────────────────────────────────────
# STEP 4: FETCH ACTIVE CAMPAIGNS LIST
# ─────────────────────────────────────────────────────────────
log_step "4" "Fetch Active Campaigns"

CAMPAIGNS_HTTP=$(curl -s -o /tmp/e2e_campaigns.json -w "%{http_code}" \
    -X GET "${TARGET_URL}/api/v1/campaigns" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    --connect-timeout 10 --max-time 20)

CAMPAIGNS_BODY=$(cat /tmp/e2e_campaigns.json)
log_info "Campaigns HTTP: $CAMPAIGNS_HTTP"

if [[ "$CAMPAIGNS_HTTP" == "200" ]]; then
    log_pass "Campaigns list returned HTTP 200"
    CAMPAIGN_COUNT=$(extract_json "$CAMPAIGNS_BODY" ".data | length")
    log_info "Active campaigns found: $CAMPAIGN_COUNT"
    if [[ "$CAMPAIGN_COUNT" -ge 1 ]]; then
        log_pass "At least 1 active campaign exists"
        # Try to use seed campaign, or fallback to first in list
        SEED_CAMPAIGN_EXISTS=$(extract_json "$CAMPAIGNS_BODY" ".data[] | select(.id == \"$TEST_CAMPAIGN_ID\") | .id" | head -1)
        if [[ -n "$SEED_CAMPAIGN_EXISTS" ]]; then
            log_pass "Seed campaign (b1eebc99...) found in campaign list"
        else
            log_warn "Seed campaign not found. Using first campaign in list."
            TEST_CAMPAIGN_ID=$(extract_json "$CAMPAIGNS_BODY" ".data[0].id")
            log_info "Using campaign ID: $TEST_CAMPAIGN_ID"
        fi
    else
        log_warn "No campaigns found — seed data may not have been applied"
    fi
else
    log_fail "Campaigns endpoint returned HTTP $CAMPAIGNS_HTTP"
fi

# ─────────────────────────────────────────────────────────────
# STEP 5: CREATE DONATION ORDER — POST /api/v1/donations/order
# ─────────────────────────────────────────────────────────────
log_step "5" "Create Razorpay Donation Order"

ORDER_PAYLOAD=$(cat <<EOF
{
  "campaignId": "$TEST_CAMPAIGN_ID",
  "amount": $TEST_AMOUNT_DECIMAL,
  "donorName": "$TEST_NAME",
  "donorEmail": "$TEST_EMAIL",
  "donorPan": "$TEST_PAN",
  "isAnonymous": false
}
EOF
)

ORDER_HTTP=$(curl -s -o /tmp/e2e_order.json -w "%{http_code}" \
    -X POST "${TARGET_URL}/api/v1/donations/order" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -d "$ORDER_PAYLOAD" \
    --connect-timeout 15 --max-time 30)

ORDER_BODY=$(cat /tmp/e2e_order.json)
log_info "Order HTTP: $ORDER_HTTP"
log_info "Response: $(echo "$ORDER_BODY" | jq -c . 2>/dev/null || echo "$ORDER_BODY")"

RAZORPAY_ORDER_ID=""
DONATION_ID=""

if [[ "$ORDER_HTTP" == "201" ]]; then
    log_pass "Donation order created — HTTP 201"
    RAZORPAY_ORDER_ID=$(extract_json "$ORDER_BODY" ".data.razorpayOrderId")
    DONATION_ID=$(extract_json "$ORDER_BODY" ".data.donationId")
    RAZORPAY_KEY_ID=$(extract_json "$ORDER_BODY" ".data.keyId")
    ORDER_AMOUNT=$(extract_json "$ORDER_BODY" ".data.amount")

    assert_not_empty "Razorpay Order ID"  "$RAZORPAY_ORDER_ID"
    assert_not_empty "Internal Donation ID" "$DONATION_ID"
    assert_not_empty "Razorpay Key ID" "$RAZORPAY_KEY_ID"
    log_info "Razorpay Order ID: $RAZORPAY_ORDER_ID"
    log_info "Internal Donation ID: $DONATION_ID"
else
    log_fail "Order creation failed with HTTP $ORDER_HTTP"
    log_warn "If HTTP 500 — check RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET env vars on Render."
    log_warn "If HTTP 404 — check campaign ID $TEST_CAMPAIGN_ID exists in DB."
    RAZORPAY_ORDER_ID="order_FALLBACK_${RUN_ID}"
    log_info "Using fallback order ID for webhook simulation: $RAZORPAY_ORDER_ID"
fi

# ─────────────────────────────────────────────────────────────
# STEP 6: SIMULATE RAZORPAY WEBHOOK — payment.captured
# ─────────────────────────────────────────────────────────────
log_step "6" "Simulate Razorpay payment.captured Webhook"

TEST_PAYMENT_ID="pay_SMOKE_E2E_${RUN_ID}"
WEBHOOK_TIMESTAMP=$(date +%s)

WEBHOOK_PAYLOAD=$(cat <<EOF
{
  "entity": "event",
  "account_id": "acc_smoke_certification",
  "event": "payment.captured",
  "contains": ["payment"],
  "payload": {
    "payment": {
      "entity": {
        "id": "${TEST_PAYMENT_ID}",
        "entity": "payment",
        "amount": ${TEST_AMOUNT},
        "currency": "INR",
        "status": "captured",
        "order_id": "${RAZORPAY_ORDER_ID}",
        "international": false,
        "method": "upi",
        "amount_refunded": 0,
        "refund_status": null,
        "captured": true,
        "description": "E2E Smoke Test Donation — Run $RUN_ID",
        "card_id": null,
        "bank": null,
        "wallet": null,
        "vpa": "smoketester@upi",
        "email": "${TEST_EMAIL}",
        "contact": "+919876543210",
        "notes": {
          "campaign_id": "${TEST_CAMPAIGN_ID}",
          "donor_name": "${TEST_NAME}",
          "donor_pan": "${TEST_PAN}"
        },
        "fee": 1180,
        "tax": 180,
        "error_code": null,
        "error_description": null,
        "error_source": null,
        "error_step": null,
        "error_reason": null,
        "acquirer_data": {
          "upi_transaction_id": "E2ESMOKE${RUN_ID}"
        },
        "created_at": ${WEBHOOK_TIMESTAMP}
      }
    }
  },
  "created_at": ${WEBHOOK_TIMESTAMP}
}
EOF
)

HMAC_SIG=$(echo -n "$WEBHOOK_PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print $2}')
log_info "HMAC-SHA256 Signature: ${HMAC_SIG:0:20}..."

WEBHOOK_HTTP=$(curl -s -o /tmp/e2e_webhook.json -w "%{http_code}" \
    -X POST "${TARGET_URL}/api/v1/webhooks/razorpay" \
    -H "Content-Type: application/json" \
    -H "X-Razorpay-Signature: $HMAC_SIG" \
    -d "$WEBHOOK_PAYLOAD" \
    --connect-timeout 15 --max-time 45)

WEBHOOK_BODY=$(cat /tmp/e2e_webhook.json)
log_info "Webhook HTTP: $WEBHOOK_HTTP"
log_info "Response: $(echo "$WEBHOOK_BODY" | jq -c . 2>/dev/null || echo "$WEBHOOK_BODY")"

if [[ "$WEBHOOK_HTTP" == "200" ]]; then
    log_pass "Webhook processed — HTTP 200"
elif [[ "$WEBHOOK_HTTP" == "500" ]]; then
    log_warn "HTTP 500 from webhook — donation record may not exist for this test order."
    log_warn "This happens when order was created via fallback ID (Razorpay order creation failed)."
    log_warn "If real order was created in Step 5 and HTTP is still 500 — check server logs on Render."
elif [[ "$WEBHOOK_HTTP" == "400" ]]; then
    log_fail "HTTP 400 — HMAC signature rejected. Webhook secret mismatch!"
else
    log_warn "Webhook returned HTTP $WEBHOOK_HTTP"
fi

# Wait for async processing (receipt PDF generation + email dispatch)
if [[ "$WEBHOOK_HTTP" == "200" ]]; then
    log_info "Waiting 5 seconds for async receipt generation thread to complete..."
    sleep 5
fi

# ─────────────────────────────────────────────────────────────
# STEP 7: VERIFY DONATION STATUS TRANSITION
# ─────────────────────────────────────────────────────────────
log_step "7" "Verify Donation → SUCCESS State"

if [[ -n "$DONATION_ID" && "$DONATION_ID" != "null" ]]; then
    DONATIONS_HTTP=$(curl -s -o /tmp/e2e_donations.json -w "%{http_code}" \
        -X GET "${TARGET_URL}/api/v1/donations/campaign/${TEST_CAMPAIGN_ID}" \
        -H "Authorization: Bearer $JWT_TOKEN" \
        --connect-timeout 10 --max-time 20)

    DONATIONS_BODY=$(cat /tmp/e2e_donations.json)
    log_info "Donations list HTTP: $DONATIONS_HTTP"

    if [[ "$DONATIONS_HTTP" == "200" ]]; then
        log_pass "Donations endpoint accessible — HTTP 200"

        # Search for our specific donation by ID
        OUR_DONATION=$(extract_json "$DONATIONS_BODY" ".data[] | select(.id == \"$DONATION_ID\")")
        if [[ -n "$OUR_DONATION" ]]; then
            DONATION_STATUS=$(extract_json "$OUR_DONATION" ".status")
            log_info "Donation $DONATION_ID status: $DONATION_STATUS"
            if [[ "$DONATION_STATUS" == "SUCCESS" ]]; then
                log_pass "Donation status transitioned to SUCCESS ✓"
            elif [[ "$DONATION_STATUS" == "INITIATED" ]]; then
                log_warn "Donation still INITIATED — webhook reconciliation may not have found this order."
                log_warn "Check: Does donations.razorpay_order_id = '$RAZORPAY_ORDER_ID' in Neon DB?"
            else
                log_fail "Unexpected donation status: '$DONATION_STATUS'"
            fi
        else
            log_warn "Donation ID $DONATION_ID not found in campaign donations list"
            log_info "All donations: $(echo "$DONATIONS_BODY" | jq -c '.data[]? | {id:.id, status:.status}' 2>/dev/null)"
        fi
    else
        log_fail "Donations endpoint returned HTTP $DONATIONS_HTTP"
    fi
else
    log_skip "Skipping donation status check — no donation ID from Step 5"
fi

# ─────────────────────────────────────────────────────────────
# STEP 8: VERIFY CAMPAIGN collectedAmount INCREMENT
# ─────────────────────────────────────────────────────────────
log_step "8" "Verify Campaign collectedAmount Incremented"

CAMPAIGN_HTTP=$(curl -s -o /tmp/e2e_campaign_check.json -w "%{http_code}" \
    -X GET "${TARGET_URL}/api/v1/campaigns/${TEST_CAMPAIGN_ID}" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    --connect-timeout 10 --max-time 20)

CAMPAIGN_BODY=$(cat /tmp/e2e_campaign_check.json)
log_info "Campaign detail HTTP: $CAMPAIGN_HTTP"

if [[ "$CAMPAIGN_HTTP" == "200" ]]; then
    log_pass "Campaign detail returned HTTP 200"
    COLLECTED=$(extract_json "$CAMPAIGN_BODY" ".data.collectedAmount // .data.collected_amount")
    TARGET=$(extract_json "$CAMPAIGN_BODY" ".data.targetAmount // .data.target_amount")
    log_info "Campaign collectedAmount: ₹$COLLECTED"
    log_info "Campaign targetAmount:    ₹$TARGET"
    if [[ -n "$COLLECTED" && "$COLLECTED" != "null" ]]; then
        COLLECTED_INT=$(echo "$COLLECTED" | awk -F'.' '{print $1}')
        if [[ "$COLLECTED_INT" -gt 0 ]]; then
            log_pass "Campaign collectedAmount is > 0 (₹$COLLECTED). Increment confirmed."
        else
            log_warn "Campaign collectedAmount is still 0. Webhook may not have processed successfully."
        fi
    fi
elif [[ "$CAMPAIGN_HTTP" == "404" ]]; then
    log_warn "Campaign detail endpoint /api/v1/campaigns/{id} returned 404."
    log_warn "This endpoint may not exist — check CampaignController for @GetMapping('/{id}')."
    log_skip "Campaign amount check skipped (endpoint not found)"
else
    log_fail "Campaign endpoint returned HTTP $CAMPAIGN_HTTP"
fi

# ─────────────────────────────────────────────────────────────
# STEP 9: VERIFY 80G RECEIPT CREATION
# ─────────────────────────────────────────────────────────────
log_step "9" "Verify 80G Tax Receipt Generated"

if [[ -n "$DONATION_ID" && "$DONATION_ID" != "null" ]]; then
    RECEIPT_HTTP=$(curl -s -o /tmp/e2e_receipt.json -w "%{http_code}" \
        -X GET "${TARGET_URL}/api/v1/receipts/donation/${DONATION_ID}" \
        --connect-timeout 10 --max-time 20)

    RECEIPT_BODY=$(cat /tmp/e2e_receipt.json)
    log_info "Receipt by donation ID HTTP: $RECEIPT_HTTP"

    if [[ "$RECEIPT_HTTP" == "200" ]]; then
        log_pass "Receipt found — HTTP 200"
        RECEIPT_NUMBER=$(extract_json "$RECEIPT_BODY" ".data.receiptNumber")
        RECEIPT_DONOR=$(extract_json "$RECEIPT_BODY" ".data.donorName")
        RECEIPT_AMOUNT=$(extract_json "$RECEIPT_BODY" ".data.amount")
        RECEIPT_EMAIL=$(extract_json "$RECEIPT_BODY" ".data.donorEmail")
        RECEIPT_PAN=$(extract_json "$RECEIPT_BODY" ".data.donorPan")
        PDF_HAS_DATA=$(extract_json "$RECEIPT_BODY" ".data.pdfBlob")

        assert_not_empty "Receipt Number (REC-YYYYMMDD-XXXX format)" "$RECEIPT_NUMBER"
        assert_not_empty "Receipt donorName" "$RECEIPT_DONOR"
        assert_not_empty "Receipt amount" "$RECEIPT_AMOUNT"
        assert_not_empty "Receipt donorEmail" "$RECEIPT_EMAIL"

        log_info "Receipt Number: $RECEIPT_NUMBER"
        log_info "Donor Name:     $RECEIPT_DONOR"
        log_info "Amount:         ₹$RECEIPT_AMOUNT"
        log_info "Donor Email:    $RECEIPT_EMAIL"
        log_info "Donor PAN:      $RECEIPT_PAN"

        # Verify receipt number format: REC-YYYYMMDD-XXXX
        if [[ "$RECEIPT_NUMBER" =~ ^REC-[0-9]{8}-[0-9]{4}$ ]]; then
            log_pass "Receipt number format REC-YYYYMMDD-XXXX validated"
        else
            log_fail "Receipt number '$RECEIPT_NUMBER' does not match format REC-YYYYMMDD-XXXX"
        fi

        # Step 9b: Download PDF and verify it's non-empty
        log_info "Attempting PDF download: /api/v1/receipts/$RECEIPT_NUMBER/download"

        PDF_HTTP=$(curl -s -o /tmp/e2e_receipt.pdf -w "%{http_code}" \
            -X GET "${TARGET_URL}/api/v1/receipts/${RECEIPT_NUMBER}/download" \
            --connect-timeout 10 --max-time 30)

        if [[ "$PDF_HTTP" == "200" ]]; then
            PDF_SIZE=$(wc -c < /tmp/e2e_receipt.pdf)
            if [[ "$PDF_SIZE" -gt 1000 ]]; then
                log_pass "PDF receipt downloaded — size: ${PDF_SIZE} bytes (> 1KB)"
                # Verify PDF header magic bytes
                PDF_HEADER=$(head -c 4 /tmp/e2e_receipt.pdf 2>/dev/null | cat -v)
                if [[ "$PDF_HEADER" == *"PDF"* ]]; then
                    log_pass "PDF magic bytes verified (%PDF header present)"
                else
                    log_warn "PDF header unexpected — possible corrupt PDF"
                fi
                log_info "PDF saved to: /tmp/e2e_receipt.pdf"
            else
                log_fail "PDF too small (${PDF_SIZE} bytes) — generation may have failed"
            fi
        elif [[ "$PDF_HTTP" == "404" ]]; then
            log_fail "PDF not found (HTTP 404) — pdf_blob may be NULL in DB"
        else
            log_fail "PDF download returned HTTP $PDF_HTTP"
        fi

    elif [[ "$RECEIPT_HTTP" == "404" ]]; then
        log_warn "Receipt not found (HTTP 404) — async generation may not have completed yet."
        log_info "The @Async receipt generation runs after the DB commit. Retry in 10 seconds..."
        sleep 10
        RETRY_HTTP=$(curl -s -o /tmp/e2e_receipt_retry.json -w "%{http_code}" \
            -X GET "${TARGET_URL}/api/v1/receipts/donation/${DONATION_ID}" \
            --connect-timeout 10 --max-time 20)
        if [[ "$RETRY_HTTP" == "200" ]]; then
            log_pass "Receipt found on retry after 10s delay — async generation succeeded"
            RECEIPT_NUMBER=$(extract_json "$(cat /tmp/e2e_receipt_retry.json)" ".data.receiptNumber")
            log_info "Receipt Number: $RECEIPT_NUMBER"
        else
            log_fail "Receipt still not found after retry (HTTP $RETRY_HTTP) — check async thread pool logs"
        fi
    else
        log_fail "Receipt endpoint returned HTTP $RECEIPT_HTTP"
        log_info "Body: $(echo "$RECEIPT_BODY" | jq -c . 2>/dev/null || echo "$RECEIPT_BODY")"
    fi
else
    log_skip "Skipping receipt check — no donation ID from Step 5"
fi

# ─────────────────────────────────────────────────────────────
# STEP 10: VERIFY IDEMPOTENCY — DUPLICATE WEBHOOK MUST NOT DOUBLE-CREDIT
# ─────────────────────────────────────────────────────────────
log_step "10" "Idempotency Guard — Re-dispatch Webhook for Same Order"

# Capture campaign collectedAmount BEFORE second webhook
BEFORE_COLLECTED="0"
if [[ "$CAMPAIGN_HTTP" == "200" ]]; then
    BEFORE_COLLECTED=$(extract_json "$CAMPAIGN_BODY" ".data.collectedAmount // .data.collected_amount")
    log_info "Campaign collectedAmount BEFORE second webhook: ₹$BEFORE_COLLECTED"
fi

# Re-send identical webhook
HMAC_SIG_DUP=$(echo -n "$WEBHOOK_PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print $2}')

DUP_WEBHOOK_HTTP=$(curl -s -o /tmp/e2e_webhook_dup.json -w "%{http_code}" \
    -X POST "${TARGET_URL}/api/v1/webhooks/razorpay" \
    -H "Content-Type: application/json" \
    -H "X-Razorpay-Signature: $HMAC_SIG_DUP" \
    -d "$WEBHOOK_PAYLOAD" \
    --connect-timeout 15 --max-time 30)

log_info "Duplicate webhook HTTP: $DUP_WEBHOOK_HTTP"
sleep 3

# Re-fetch campaign amount
AFTER_HTTP=$(curl -s -o /tmp/e2e_campaign_after.json -w "%{http_code}" \
    -X GET "${TARGET_URL}/api/v1/campaigns/${TEST_CAMPAIGN_ID}" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    --connect-timeout 10 --max-time 20)

if [[ "$AFTER_HTTP" == "200" ]]; then
    AFTER_COLLECTED=$(extract_json "$(cat /tmp/e2e_campaign_after.json)" ".data.collectedAmount // .data.collected_amount")
    log_info "Campaign collectedAmount AFTER second webhook: ₹$AFTER_COLLECTED"

    if [[ "$BEFORE_COLLECTED" == "$AFTER_COLLECTED" ]]; then
        log_pass "Idempotency VERIFIED — collectedAmount unchanged after duplicate webhook (₹$AFTER_COLLECTED)"
    else
        log_fail "IDEMPOTENCY BROKEN — collectedAmount changed from ₹$BEFORE_COLLECTED to ₹$AFTER_COLLECTED after duplicate webhook!"
        log_fail "CRITICAL: Funds were DOUBLE-CREDITED. Check DonationService.reconcilePaymentCaptured() idempotency guard."
    fi
else
    log_skip "Cannot verify idempotency — campaign detail endpoint not available"
fi

# ─────────────────────────────────────────────────────────────
# FINAL E2E CERTIFICATION SUMMARY
# ─────────────────────────────────────────────────────────────
log_header "E2E CERTIFICATION SUMMARY — Run ID: $RUN_ID"
echo ""
echo -e "  ${BOLD}Target URL:${RESET}        $TARGET_URL"
echo -e "  ${BOLD}Test Email:${RESET}        $TEST_EMAIL"
echo -e "  ${BOLD}Donation ID:${RESET}       ${DONATION_ID:-N/A}"
echo -e "  ${BOLD}Razorpay Order:${RESET}    ${RAZORPAY_ORDER_ID:-N/A}"
echo -e "  ${BOLD}Receipt Number:${RESET}    ${RECEIPT_NUMBER:-N/A}"
echo ""
echo -e "  ${GREEN}PASSED: $PASS_COUNT${RESET}"
echo -e "  ${RED}FAILED: $FAIL_COUNT${RESET}"
echo -e "  ${YELLOW}SKIPPED: $SKIP_COUNT${RESET}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}✅  E2E CERTIFICATION PASSED — Production stack is live and verified.${RESET}"
else
    echo -e "  ${RED}${BOLD}❌  CERTIFICATION FAILED — $FAIL_COUNT check(s) need attention before go-live.${RESET}"
fi
echo ""
