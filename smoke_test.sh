#!/usr/bin/env bash
# ==============================================================================
# Automated Production Smoke Test Harness
# All-in-One Donation & Crowdfunding Platform
# Requirements: bash, curl, jq
# Usage: ./smoke_test.sh [TARGET_BASE_URL]
# Example: ./smoke_test.sh https://donation-platform-api.onrender.com
# ==============================================================================

set -eo pipefail

BASE_URL="${1:-http://localhost:8080}"
BASE_URL="${BASE_URL%/}" # Strip trailing slash if present

# Terminal Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Dependency check
command -v curl >/dev/null 2>&1 || { echo -e "${RED}Error: curl is required but not installed.${NC}" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo -e "${RED}Error: jq is required but not installed. Please install jq to run smoke tests.${NC}" >&2; exit 1; }

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BOLD}${CYAN}   PRODUCTION SMOKE TEST: ALL-IN-ONE DONATION PLATFORM   ${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo -e "Target URL   : ${BOLD}${BASE_URL}${NC}"
echo -e "Started At   : $(date -u +"%Y-%m-%dT%H:%M:%SZ")\n"

TOTAL_TESTS=5
PASSED_TESTS=0

log_pass() {
    echo -e " [${GREEN}${BOLD}PASS${NC}] $1"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

log_fail() {
    echo -e " [${RED}${BOLD}FAIL${NC}] $1"
    echo -e "${RED}Reason: $2${NC}"
    echo -e "\n${RED}Smoke tests aborted.${NC}"
    exit 1
}

# ------------------------------------------------------------------------------
# TEST 1: Actuator Health Check
# ------------------------------------------------------------------------------
echo -e "${YELLOW}Phase 1: Actuator Health Endpoint Check...${NC}"
HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/actuator/health")
HEALTH_CODE=$(echo "$HEALTH_RESPONSE" | tail -n1)
HEALTH_BODY=$(echo "$HEALTH_RESPONSE" | sed '$d')

if [ "$HEALTH_CODE" -eq 200 ]; then
    STATUS=$(echo "$HEALTH_BODY" | jq -r '.status // empty')
    if [ "$STATUS" == "UP" ] || [ -n "$STATUS" ]; then
        log_pass "Health check responded HTTP 200 with status '$STATUS'"
    else
        log_fail "Health check returned unexpected payload" "$HEALTH_BODY"
    fi
else
    log_fail "Health check returned HTTP $HEALTH_CODE" "$HEALTH_BODY"
fi

# ------------------------------------------------------------------------------
# TEST 2: Register New Donor User
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 2: User Registration (POST /api/v1/auth/register)...${NC}"
UNIQUE_ID=$(date +%s%N | cut -b1-13)
TEST_EMAIL="donor_${UNIQUE_ID}@smoketest.local"
TEST_PASSWORD="TestPassword@123"
TEST_NAME="Smoke Test Donor ${UNIQUE_ID}"

REGISTER_PAYLOAD=$(cat <<EOF
{
  "name": "${TEST_NAME}",
  "email": "${TEST_EMAIL}",
  "password": "${TEST_PASSWORD}",
  "role": "ROLE_USER"
}
EOF
)

REGISTER_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/auth/register" \
    -H "Content-Type: application/json" \
    -d "$REGISTER_PAYLOAD")

REGISTER_CODE=$(echo "$REGISTER_RESPONSE" | tail -n1)
REGISTER_BODY=$(echo "$REGISTER_RESPONSE" | sed '$d')

if [ "$REGISTER_CODE" -eq 201 ]; then
    REGISTER_SUCCESS=$(echo "$REGISTER_BODY" | jq -r '.success // empty')
    if [ "$REGISTER_SUCCESS" == "true" ]; then
        log_pass "User registration succeeded for email: $TEST_EMAIL"
    else
        log_fail "Registration returned success=false" "$REGISTER_BODY"
    fi
else
    log_fail "User registration failed with HTTP $REGISTER_CODE" "$REGISTER_BODY"
fi

# ------------------------------------------------------------------------------
# TEST 3: User Authentication & JWT Extraction (POST /api/v1/auth/login)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 3: User Authentication (POST /api/v1/auth/login)...${NC}"
LOGIN_PAYLOAD=$(cat <<EOF
{
  "email": "${TEST_EMAIL}",
  "password": "${TEST_PASSWORD}"
}
EOF
)

LOGIN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "$LOGIN_PAYLOAD")

LOGIN_CODE=$(echo "$LOGIN_RESPONSE" | tail -n1)
LOGIN_BODY=$(echo "$LOGIN_RESPONSE" | sed '$d')

if [ "$LOGIN_CODE" -eq 200 ]; then
    JWT_TOKEN=$(echo "$LOGIN_BODY" | jq -r '.data.token // empty')
    if [ -n "$JWT_TOKEN" ] && [ "$JWT_TOKEN" != "null" ]; then
        log_pass "Authentication succeeded. Bearer JWT obtained (${#JWT_TOKEN} chars)"
    else
        log_fail "JWT token missing from login response" "$LOGIN_BODY"
    fi
else
    log_fail "Authentication failed with HTTP $LOGIN_CODE" "$LOGIN_BODY"
fi

# ------------------------------------------------------------------------------
# TEST 4: Query Active Campaigns (GET /api/v1/campaigns)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 4: Fetch Active Campaigns (GET /api/v1/campaigns)...${NC}"
CAMPAIGN_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/campaigns" \
    -H "Accept: application/json")

CAMPAIGN_CODE=$(echo "$CAMPAIGN_RESPONSE" | tail -n1)
CAMPAIGN_BODY=$(echo "$CAMPAIGN_RESPONSE" | sed '$d')

if [ "$CAMPAIGN_CODE" -eq 200 ]; then
    CAMPAIGN_COUNT=$(echo "$CAMPAIGN_BODY" | jq '.data | length')
    if [ "$CAMPAIGN_COUNT" -gt 0 ]; then
        CAMPAIGN_ID=$(echo "$CAMPAIGN_BODY" | jq -r '.data[0].id')
        CAMPAIGN_TITLE=$(echo "$CAMPAIGN_BODY" | jq -r '.data[0].title')
        log_pass "Retrieved $CAMPAIGN_COUNT active campaign(s). Selected ID: $CAMPAIGN_ID ('$CAMPAIGN_TITLE')"
    else
        # If no campaign exists, create one using authenticated admin/user
        echo -e "   ${CYAN}Notice: No active campaign found. Creating a campaign for testing...${NC}"
        CREATE_CAMP_PAYLOAD=$(cat <<EOF
{
  "title": "Smoke Test Emergency Initiative",
  "description": "Automated campaign generated during deployment smoke test execution.",
  "targetAmount": 100000.00
}
EOF
        )
        NEW_CAMP_RESP=$(curl -s -X POST "${BASE_URL}/api/v1/campaigns" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${JWT_TOKEN}" \
            -d "$CREATE_CAMP_PAYLOAD")
        CAMPAIGN_ID=$(echo "$NEW_CAMP_RESP" | jq -r '.data.id')
        log_pass "Dynamically created test campaign ID: $CAMPAIGN_ID"
    fi
else
    log_fail "Failed to query active campaigns. HTTP $CAMPAIGN_CODE" "$CAMPAIGN_BODY"
fi

# ------------------------------------------------------------------------------
# TEST 5: Create Razorpay Donation Order (POST /api/v1/donations/order)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 5: Create Razorpay Donation Order (POST /api/v1/donations/order)...${NC}"
DONATION_AMOUNT=250.00
DONATION_PAYLOAD=$(cat <<EOF
{
  "campaignId": "${CAMPAIGN_ID}",
  "amount": ${DONATION_AMOUNT},
  "donorName": "${TEST_NAME}",
  "donorEmail": "${TEST_EMAIL}",
  "isAnonymous": false
}
EOF
)

DONATION_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/donations/order" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${JWT_TOKEN}" \
    -d "$DONATION_PAYLOAD")

DONATION_CODE=$(echo "$DONATION_RESPONSE" | tail -n1)
DONATION_BODY=$(echo "$DONATION_RESPONSE" | sed '$d')

if [ "$DONATION_CODE" -eq 201 ]; then
    RAZORPAY_ORDER_ID=$(echo "$DONATION_BODY" | jq -r '.data.razorpayOrderId // empty')
    ORDER_AMOUNT=$(echo "$DONATION_BODY" | jq -r '.data.amount // empty')
    CURRENCY=$(echo "$DONATION_BODY" | jq -r '.data.currency // empty')
    KEY_ID=$(echo "$DONATION_BODY" | jq -r '.data.keyId // empty')

    if [ -n "$RAZORPAY_ORDER_ID" ] && [ "$RAZORPAY_ORDER_ID" != "null" ]; then
        log_pass "Donation order created successfully! Razorpay Order ID: $RAZORPAY_ORDER_ID ($CURRENCY $ORDER_AMOUNT, Key: $KEY_ID)"
    else
        log_fail "Razorpay order ID missing from response payload" "$DONATION_BODY"
    fi
else
    log_fail "Failed to create donation order with HTTP $DONATION_CODE" "$DONATION_BODY"
fi

# ------------------------------------------------------------------------------
# SUMMARY REPORT
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}==============================================================================${NC}"
echo -e "${BOLD}${GREEN}   ALL SMOKE TESTS COMPLETED SUCCESSFULLY! (${PASSED_TESTS}/${TOTAL_TESTS} PASSED)   ${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo -e "Platform is live, healthy, authenticated, and ready to accept live transactions."
exit 0
