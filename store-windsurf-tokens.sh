#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

# Windsurf Token Storage Script
# This script stores Windsurf session tokens in the keychain

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [ $# -eq 0 ]; then
    echo -e "${RED}Error: Please provide the JSON token data as argument${NC}"
    echo "Usage: ./store-windsurf-tokens.sh '<json_data>'"
    exit 1
fi

json_data="$1"

echo -e "${BLUE}Storing Windsurf tokens in keychain...${NC}"

# Check if jq is available
if command -v jq >/dev/null 2>&1; then
    # Parse JSON and store each token
    session_token=$(echo "$json_data" | jq -r '.devin_session_token // empty')
    auth1_token=$(echo "$json_data" | jq -r '.devin_auth1_token // empty')
    account_id=$(echo "$json_data" | jq -r '.devin_account_id // empty')
    primary_org_id=$(echo "$json_data" | jq -r '.devin_primary_org_id // empty')
else
    # Fallback: simple parsing without jq
    session_token=$(echo "$json_data" | grep -o '"devin_session_token"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
    auth1_token=$(echo "$json_data" | grep -o '"devin_auth1_token"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
    account_id=$(echo "$json_data" | grep -o '"devin_account_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
    primary_org_id=$(echo "$json_data" | grep -o '"devin_primary_org_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
fi

if [ -z "$session_token" ] || [ -z "$auth1_token" ] || [ -z "$account_id" ] || [ -z "$primary_org_id" ]; then
    echo -e "${RED}Error: Missing required tokens in JSON data${NC}"
    echo "Required: devin_session_token, devin_auth1_token, devin_account_id, devin_primary_org_id"
    exit 1
fi

# Store each token in keychain (delete first if exists)
for token_name in "windsurf-session-token" "windsurf-auth1-token" "windsurf-account-id" "windsurf-primary-org-id"; do
    /usr/bin/security delete-generic-password -a "$USER" -s "$token_name" 2>/dev/null || true
done

/usr/bin/security add-generic-password -a "$USER" -s "windsurf-session-token" -w "$session_token"
/usr/bin/security add-generic-password -a "$USER" -s "windsurf-auth1-token" -w "$auth1_token"
/usr/bin/security add-generic-password -a "$USER" -s "windsurf-account-id" -w "$account_id"
/usr/bin/security add-generic-password -a "$USER" -s "windsurf-primary-org-id" -w "$primary_org_id"

echo -e "${GREEN}✓ All tokens stored successfully in keychain${NC}"
echo ""
echo "Stored tokens:"
echo "  - windsurf-session-token"
echo "  - windsurf-auth1-token"
echo "  - windsurf-account-id"
echo "  - windsurf-primary-org-id"
