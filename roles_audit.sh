#!/bin/bash

# Input validation
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <api_key> <tenant_name>"
    exit 1
fi

API_KEY="$1"
TENANT_NAME="$2"
BASE_URL="https://${TENANT_NAME}.console.ves.volterra.io"

# Check for jq dependency
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Please install jq."
    exit 1
fi

# Fetch all roles
ROLES_URL="${BASE_URL}/api/web/custom/namespaces/system/roles"
roles_response=$(curl -s -H "Authorization: APIToken ${API_KEY}" "$ROLES_URL")

# Check if the API response contains data
if [[ -z "$roles_response" ]]; then
    echo "Error: Empty response from API."
    exit 1
fi

# Print header
echo -e "\n📋 F5 XC Roles Audit Report for tenant '$TENANT_NAME'\n"

# Loop through roles and extract important fields
echo "$roles_response" | jq -c '.items[]' | while read -r role; do
    role_name=$(echo "$role" | jq -r '.name')
    tenant=$(echo "$role" | jq -r '.tenant')
    namespace=$(echo "$role" | jq -r '.namespace')
    
    echo "🔹 Role: $role_name"
    echo "    Tenant: $tenant"
    echo "    Namespace: $namespace"
    echo "    API Groups:"

    # Print each API group
    echo "$role" | jq -r '.api_groups[]' | sed 's/^/        - /'
    
    echo ""
done
