#!/bin/bash

# Input validation
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <api_key> <tenant_name> [--days=N]"
    exit 1
fi

API_KEY="$1"
TENANT_NAME="$2"
AGE_DAYS=180 # Default to 180 days

# Optional argument: --days=N
for arg in "$@"; do
    if [[ "$arg" =~ ^--days=([0-9]+)$ ]]; then
        AGE_DAYS="${BASH_REMATCH[1]}"
    fi
done

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Please install jq."
    exit 1
fi

# Setup
API_BASE_URL="https://${TENANT_NAME}.console.ves.volterra.io/api"
cutoff_date=$(date -u -d "-${AGE_DAYS} days" +"%Y-%m-%dT%H:%M:%SZ")

# Validate API token by making a test call
auth_check=$(curl -s -H "Authorization: APIToken ${API_KEY}" "$API_BASE_URL/web/namespaces")
if ! echo "$auth_check" | jq -e '.items' &>/dev/null; then
    echo "Error: API token may be invalid or response is not JSON."
    echo "Response received:"
    echo "$auth_check"
    exit 1
fi

# Get all namespaces
namespaces=$(echo "$auth_check" | jq -r '.items[].name')

# Function to delete old resources
purge_old_objects() {
    local namespace=$1
    local kind=$2
    local endpoint=$3

    echo "Checking for $kind older than $AGE_DAYS days in namespace: $namespace"

    list_response=$(curl -s -H "Authorization: APIToken ${API_KEY}" \
      "$API_BASE_URL/config/namespaces/${namespace}/${endpoint}")

    echo "$list_response" | jq -c '.items[]' | while read -r item; do
        name=$(echo "$item" | jq -r '.name')
        item_namespace=$(echo "$item" | jq -r '.namespace')

        # Skip shared/system objects
        if [[ "$item_namespace" == "shared" || "$item_namespace" == "system" ]]; then
            continue
        fi

        # Fetch full metadata
        details=$(curl -s -H "Authorization: APIToken ${API_KEY}" \
          "$API_BASE_URL/config/namespaces/${item_namespace}/${endpoint}/${name}?response_format=5")

        # Pull timestamps
        mod_ts=$(echo "$details" | jq -r '.system_metadata.modification_timestamp')
        create_ts=$(echo "$details" | jq -r '.system_metadata.creation_timestamp')

        # Determine the date to compare
        ts_to_compare="$create_ts"
        if [[ "$mod_ts" != "null" && -n "$mod_ts" ]]; then
            ts_to_compare="$mod_ts"
        fi

        # Convert both dates to seconds since epoch
        ts_epoch=$(date -d "$ts_to_compare" +"%s")
        cutoff_epoch=$(date -d "$cutoff_date" +"%s")

        if [[ "$ts_epoch" -lt "$cutoff_epoch" ]]; then
            echo "Deleting old $kind: $name (Timestamp: $ts_to_compare)"

            json_body=$(jq -n --arg name "$name" --arg namespace "$item_namespace" '{fail_if_referred: true, name: $name, namespace: $namespace}')

            delete_response=$(curl -s -X DELETE -H "Authorization: APIToken ${API_KEY}" -H "Content-Type: application/json" -d "$json_body" \
              "$API_BASE_URL/config/namespaces/${item_namespace}/${endpoint}/${name}")

            echo "Delete response: $delete_response"
        fi
    done
}


# Loop through namespaces
for ns in $namespaces; do
    [[ "$ns" == "system" || "$ns" == "shared" ]] && continue

    purge_old_objects "$ns" "origin_pool" "origin_pools"
    purge_old_objects "$ns" "app_firewall" "app_firewalls"
    purge_old_objects "$ns" "service_policy" "service_policys"
    purge_old_objects "$ns" "app_setting" "app_settings"
    purge_old_objects "$ns" "api_definition" "api_definitions"
done

echo "Completed cleanup of objects older than $AGE_DAYS days."
