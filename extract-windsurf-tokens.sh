#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

# Windsurf Token Extraction Script
# This script extracts Windsurf session tokens from browser localStorage and stores them in the keychain

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Windsurf Token Extraction Script${NC}"
echo "=================================="
echo ""

# Function to provide manual extraction instructions
provide_manual_instructions() {
    echo -e "${BLUE}Manual Extraction Instructions:${NC}"
    echo "1. Open Windsurf in your browser and log in"
    echo "2. Open Developer Tools (F12 or Cmd+Option+I)"
    echo "3. Go to the Console tab"
    echo "4. Paste and run this JavaScript:"
    echo ""
    echo -e "${GREEN}(() => {"
    echo "  const keys = ["
    echo "    \"devin_session_token\","
    echo "    \"devin_auth1_token\","
    echo "    \"devin_account_id\","
    echo "    \"devin_primary_org_id\","
    echo "  ];"
    echo ""
    echo "  const read = (key) => {"
    echo "    const value = localStorage.getItem(key);"
    echo "    if (!value) return null;"
    echo "    try {"
    echo "      return JSON.parse(value);"
    echo "    } catch {"
    echo "      return value;"
    echo "    }"
    echo "  };"
    echo ""
    echo "  const payload = Object.fromEntries(keys.map((key) => [key, read(key)]));"
    echo "  const missing = keys.filter((key) => !payload[key]);"
    echo ""
    echo "  if (missing.length > 0) {"
    echo "    console.log(\"Missing Windsurf session keys:\", missing.join(\", \"));"
    echo "    return;"
    echo "  }"
    echo ""
    echo "  const json = JSON.stringify(payload, null, 2);"
    echo "  console.log(json);"
    echo "  if (typeof copy === \"function\") {"
    echo "    copy(json);"
    echo "    console.log(\"Copied to clipboard!\");"
    echo "  }"
    echo "})();${NC}"
    echo ""
    echo "5. Copy the JSON output from the console"
    echo "6. Run: ./store-windsurf-tokens.sh '<paste the JSON here>'"
}

# Function to store tokens in keychain
store_tokens() {
    local json_data="$1"
    
    echo -e "${BLUE}Storing tokens in keychain...${NC}"
    
    # Check if jq is available
    if command -v jq >/dev/null 2>&1; then
        # Parse JSON and store each token
        local session_token=$(echo "$json_data" | jq -r '.devin_session_token // empty')
        local auth1_token=$(echo "$json_data" | jq -r '.devin_auth1_token // empty')
        local account_id=$(echo "$json_data" | jq -r '.devin_account_id // empty')
        local primary_org_id=$(echo "$json_data" | jq -r '.devin_primary_org_id // empty')
    else
        # Fallback: simple parsing without jq
        local session_token=$(echo "$json_data" | grep -o '"devin_session_token"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
        local auth1_token=$(echo "$json_data" | grep -o '"devin_auth1_token"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
        local account_id=$(echo "$json_data" | grep -o '"devin_account_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
        local primary_org_id=$(echo "$json_data" | grep -o '"devin_primary_org_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
    fi
    
    if [ -z "$session_token" ] || [ -z "$auth1_token" ] || [ -z "$account_id" ] || [ -z "$primary_org_id" ]; then
        echo -e "${RED}Error: Missing required tokens in JSON data${NC}"
        echo "Required: devin_session_token, devin_auth1_token, devin_account_id, devin_primary_org_id"
        return 1
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
}

# Check if JSON data was provided as argument
if [ $# -eq 1 ]; then
    echo -e "${BLUE}Storing provided JSON data...${NC}"
    store_tokens "$1"
else
    provide_manual_instructions
fi

echo ""
echo -e "${BLUE}Token extraction complete${NC}"
