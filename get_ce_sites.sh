#!/bin/bash

# Input validation
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <api_key> <tenant_name>"
    exit 1
fi

API_KEY="$1"
TENANT_NAME="$2"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Please install jq."
    exit 1
fi

# Get JSON response from API and parse it
API_URL="https://${TENANT_NAME}.console.ves.volterra.io/api/config/namespaces/system/sites"
JSON_RESPONSE=$(curl -s -H "Authorization: APIToken $API_KEY" "$API_URL")

# Ensure JSON_RESPONSE is not empty or an invalid JSON
if [ -z "$JSON_RESPONSE" ] || ! echo "$JSON_RESPONSE" | jq . &> /dev/null; then
    echo "Error: Failed to fetch valid JSON response from API"
    exit 1
fi

# Parse JSON and pass the relevant data to another script
echo "$JSON_RESPONSE" | jq -c '.items[] | select(.labels["ves.io/siteType"] == "ves-io-ce") | {name: .name, tenant: .tenant}' | while read -r item; do
    SITE_NAME=$(echo "$item" | jq -r '.name')
    TENANT=$(echo "$item" | jq -r '.tenant')

    # Call another script with SITE_NAME, TENANT_NAME, and API_KEY
    ./ce_site_update.sh "$SITE_NAME" "$TENANT_NAME" "$API_KEY"
done