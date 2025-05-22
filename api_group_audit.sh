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

# Fetch all API groups
GROUPS_URL="${BASE_URL}/api/web/namespaces/system/api_groups"
api_groups=$(curl -s -H "Authorization: APIToken ${API_KEY}" "$GROUPS_URL")

# Check for valid response
if [[ -z "$api_groups" ]]; then
    echo "Error: Empty response from API."
    exit 1
fi

# Audit Report Header
echo -e "\n📋 API Group Audit Report for tenant '$TENANT_NAME'\n"

# Process each API group
echo "$api_groups" | jq -c '.items[]' | while read -r group; do
    group_name=$(echo "$group" | jq -r '.name')
    tenant=$(echo "$group" | jq -r '.tenant')
    namespace=$(echo "$group" | jq -r '.namespace')
    combined_ns="${tenant}-${namespace}"

    echo "🔹 API Group: $group_name"
    echo "    Tenant/Namespace: $combined_ns"

    # Get detailed API group info
    group_detail_url="${BASE_URL}/api/web/namespaces/${combined_ns}/api_groups/${group_name}"
    group_detail=$(curl -s -H "Authorization: APIToken ${API_KEY}" "$group_detail_url")

    # Loop through each element in the group
    echo "$group_detail" | jq -c '.spec.elements[]' | while read -r element; do
        element_name=$(echo "$element" | jq -r '.name')
        echo "    🔸 Element: $element_name"

        # Get element details
        element_detail_url="${BASE_URL}/api/web/namespaces/${combined_ns}/api_group_elements/${element_name}"
        element_detail=$(curl -s -H "Authorization: APIToken ${API_KEY}" "$element_detail_url")

        # Extract and display method and path
        methods=$(echo "$element_detail" | jq -r '.spec.methods | join(", ")')
        path=$(echo "$element_detail" | jq -r '.spec.path_regex')

        echo "        ├── Methods: $methods"
        echo "        └── Path Regex: $path"
    done

    echo ""
done
