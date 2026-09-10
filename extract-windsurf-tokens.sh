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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to extract tokens from browser localStorage
extract_from_browser() {
    local browser_path="$1"
    local browser_name="$2"
    
    if [ ! -d "$browser_path" ]; then
        return 1
    fi
    
    echo -e "${YELLOW}Checking $browser_name...${NC}"
    
    # Try to find the leveldb directory
    local leveldb_dir="$browser_path/Local Storage/leveldb"
    
    if [ ! -d "$leveldb_dir" ]; then
        echo -e "  ${RED}No leveldb directory found${NC}"
        return 1
    fi
    
    # Try to extract using a simple approach - this is basic and may not work for all browsers
    # For a more robust solution, we'd need to parse the leveldb format directly
    echo -e "  ${YELLOW}leveldb directory found, but direct extraction requires complex parsing${NC}"
    return 1
}

# Function to provide manual extraction instructions
provide_manual_instructions() {
    echo -e "${RED}Automatic extraction not available for your browser configuration${NC}"
    echo ""
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
    
    # Parse JSON and store each token
    local session_token=$(echo "$json_data" | jq -r '.devin_session_token // empty')
    local auth1_token=$(echo "$json_data" | jq -r '.devin_auth1_token // empty')
    local account_id=$(echo "$json_data" | jq -r '.devin_account_id // empty')
    local primary_org_id=$(echo "$json_data" | jq -r '.devin_primary_org_id // empty')
    
    if [ -z "$session_token" ] || [ -z "$auth1_token" ] || [ -z "$account_id" ] || [ -z "$primary_org_id" ]; then
        echo -e "${RED}Error: Missing required tokens in JSON data${NC}"
        return 1
    fi
    
    # Store each token in keychain
    /usr/bin/security add-generic-password -a "$USER" -s "windsurf-session-token" -w "$session_token" 2>/dev/null || \
        /usr/bin/security delete-generic-password -a "$USER" -s "windsurf-session-token" 2>/dev/null && \
        /usr/bin/security add-generic-password -a "$USER" -s "windsurf-session-token" -w "$session_token"
    
    /usr/bin/security add-generic-password -a "$USER" -s "windsurf-auth1-token" -w "$auth1_token" 2>/dev/null || \
        /usr/bin/security delete-generic-password -a "$USER" -s "windsurf-auth1-token" 2>/dev/null && \
        /usr/bin/security add-generic-password -a "$USER" -s "windsurf-auth1-token" -w "$auth1_token"
    
    /usr/bin/security add-generic-password -a "$USER" -s "windsurf-account-id" -w "$account_id" 2>/dev/null || \
        /usr/bin/security delete-generic-password -a "$USER" -s "windsurf-account-id" 2>/dev/null && \
        /usr/bin/security add-generic-password -a "$USER" -s "windsurf-account-id" -w "$account_id"
    
    /usr/bin/security add-generic-password -a "$USER" -s "windsurf-primary-org-id" -w "$primary_org_id" 2>/dev/null || \
        /usr/bin/security delete-generic-password -a "$USER" -s "windsurf-primary-org-id" 2>/dev/null && \
        /usr/bin/security add-generic-password -a "$USER" -s "windsurf-primary-org-id" -w "$primary_org_id"
    
    echo -e "${GREEN}✓ Tokens stored successfully in keychain${NC}"
}

# Check if jq is available
if ! command_exists jq; then
    echo -e "${YELLOW}Warning: jq not found. Install with: brew install jq${NC}"
fi

# Try automatic extraction from common browsers
echo -e "${BLUE}Attempting automatic token extraction...${NC}"
echo ""

# Common browser paths on macOS
declare -a browsers=(
    "$HOME/Library/Application Support/Google/Chrome:Chrome"
    "$HOME/Library/Application Support/Microsoft Edge:Edge"
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser:Brave"
    "$HOME/Library/Application Support/Arc:Arc"
    "$HOME/Library/Application Support/Vivaldi:Vivaldi"
)

found_browser=false
for browser_info in "${browsers[@]}"; do
    IFS=':' read -r browser_path browser_name <<< "$browser_info"
    if extract_from_browser "$browser_path" "$browser_name"; then
        found_browser=true
        break
    fi
done

if [ "$found_browser" = false ]; then
    provide_manual_instructions
fi

# Check if JSON data was provided as argument
if [ $# -eq 1 ]; then
    echo -e "${BLUE}Storing provided JSON data...${NC}"
    store_tokens "$1"
fi

echo ""
echo -e "${BLUE}Token extraction complete${NC}"
