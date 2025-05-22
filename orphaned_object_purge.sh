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

# Construct the base API URL
API_BASE_URL="https://${TENANT_NAME}.console.ves.volterra.io/api"

# Validate API token by making a test call
auth_check=$(curl -s -H "Authorization: APIToken ${API_KEY}" \
  "$API_BASE_URL/web/namespaces")

# Check for invalid credentials or HTML responses
if ! echo "$auth_check" | jq -e '.items' &>/dev/null; then
    echo "Error: API token may be invalid or response is not JSON."
    echo "Response received:"
    echo "$auth_check"
    exit 1
fi

# Get all namespaces
namespaces=$(echo "$auth_check" | jq -r '.items[].name')

# Current timestamp for reference (not used for deletion logic but can be logged)
current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Function to delete orphaned resources
purge_orphans() {
    local namespace=$1
    local kind=$2
    local endpoint=$3

    echo "Checking for orphaned $kind in namespace: $namespace"

    list_response=$(curl -s -H "Authorization: APIToken ${API_KEY}" "$API_BASE_URL/config/namespaces/${namespace}/${endpoint}")

    echo "$list_response" | jq -c '.items[]' | while read -r item; do
    
        name=$(echo "$item" | jq -r '.name')
        item_namespace=$(echo "$item" | jq -r '.namespace')

        if [[ "$item_namespace" == "shared" || "$item_namespace" == "system" ]]; then
          #echo "Skipping $kind '$name' in shared/system namespace: $item_namespace"
          continue
        fi

        details=$(curl -s -H "Authorization: APIToken ${API_KEY}" "$API_BASE_URL/config/namespaces/${item_namespace}/${endpoint}/${name}?response_format=5")

        ref_count=$(echo "$details" | jq '.referring_objects | length')

        if [[ "$ref_count" == "0" ]]; then
            echo "Purging orphaned $kind: $name in namespace: $namespace"
            
            json_body=$(jq -n --arg name "$name" --arg ns "$item_namespace" '{fail_if_referred: true, name: $name, namespace: $ns}')

            delete_response=$(curl -s -X DELETE -H "Authorization: APIToken ${API_KEY}" -H "Content-Type: application/json" -d "$json_body" "$API_BASE_URL/config/namespaces/${item_namespace}/${endpoint}/${name}")

            echo "Delete response: $delete_response"
        fi
    done
}

# Loop through namespaces and purge orphaned objects
for ns in $namespaces; do
    [[ "$ns" == "system" || "$ns" == "shared" ]] && continue

    purge_orphans "$ns" "origin_pool" "origin_pools"
    purge_orphans "$ns" "app_firewall" "app_firewalls"
    purge_orphans "$ns" "service_policy" "service_policys"
    purge_orphans "$ns" "app_setting" "app_settings"
    purge_orphans "$ns" "api_definition" "api_definitions"
done

echo "Completed orphan cleanup."
