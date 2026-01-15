#!/bin/bash

# Input validation
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <api_key> <tenant_name> [--type=TYPE]"
    echo ""
    echo "Options:"
    echo "  --type=TYPE    Filter by object type. Valid types:"
    echo "                   origin_pool, app_firewall, service_policy,"
    echo "                   app_setting, api_definition, http_loadbalancer"
    echo "                 If not specified, all types are audited."
    echo ""
    echo "Example:"
    echo "  $0 myapikey mytenant --type=service_policy"
    exit 1
fi

API_KEY="$1"
TENANT_NAME="$2"
TYPE_FILTER=""

# Optional argument: --type=TYPE
for arg in "$@"; do
    if [[ "$arg" =~ ^--type=(.+)$ ]]; then
        TYPE_FILTER="${BASH_REMATCH[1]}"
    fi
done

# Validate type filter if provided
VALID_TYPES=("origin_pool" "app_firewall" "service_policy" "app_setting" "api_definition" "http_loadbalancer")
if [[ -n "$TYPE_FILTER" ]]; then
    valid=false
    for t in "${VALID_TYPES[@]}"; do
        if [[ "$TYPE_FILTER" == "$t" ]]; then
            valid=true
            break
        fi
    done
    if [[ "$valid" == "false" ]]; then
        echo "Error: Invalid type '$TYPE_FILTER'"
        echo "Valid types: ${VALID_TYPES[*]}"
        exit 1
    fi
fi

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

# Current timestamp for reference
current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Counters for summary
declare -A orphan_counts
total_orphans=0

# Function to audit orphaned resources
audit_orphans() {
    local namespace=$1
    local kind=$2
    local endpoint=$3

    list_response=$(curl -s -H "Authorization: APIToken ${API_KEY}" "$API_BASE_URL/config/namespaces/${namespace}/${endpoint}")

    # Check if response has items
    if ! echo "$list_response" | jq -e '.items' &>/dev/null; then
        return
    fi

    echo "$list_response" | jq -c '.items[]' 2>/dev/null | while read -r item; do

        name=$(echo "$item" | jq -r '.name')
        item_namespace=$(echo "$item" | jq -r '.namespace')

        if [[ "$item_namespace" == "shared" || "$item_namespace" == "system" ]]; then
            continue
        fi

        details=$(curl -s -H "Authorization: APIToken ${API_KEY}" "$API_BASE_URL/config/namespaces/${item_namespace}/${endpoint}/${name}?response_format=5")

        ref_count=$(echo "$details" | jq '.referring_objects | length')

        if [[ "$ref_count" == "0" ]]; then
            # Extract metadata for the report
            create_ts=$(echo "$details" | jq -r '.system_metadata.creation_timestamp // "N/A"')
            mod_ts=$(echo "$details" | jq -r '.system_metadata.modification_timestamp // "N/A"')
            creator=$(echo "$details" | jq -r '.system_metadata.creator_id // "N/A"')

            echo "    Name: $name"
            echo "        Namespace: $item_namespace"
            echo "        Created: $create_ts"
            echo "        Modified: $mod_ts"
            echo "        Creator: $creator"
            echo ""

            # Output a marker for counting (will be processed later)
            echo "ORPHAN_FOUND:$kind" >&3
        fi
    done
}

# Print report header
echo ""
echo "========================================================"
echo "  Orphaned Object Audit Report"
echo "  Tenant: $TENANT_NAME"
echo "  Generated: $current_time"
if [[ -n "$TYPE_FILTER" ]]; then
    echo "  Filter: $TYPE_FILTER"
fi
echo "========================================================"
echo ""

# Create a temp file for counting orphans
count_file=$(mktemp)
exec 3>"$count_file"

# Loop through namespaces and audit orphaned objects
for ns in $namespaces; do
    [[ "$ns" == "system" || "$ns" == "shared" ]] && continue

    # Only process requested types (or all if no filter)
    if [[ -z "$TYPE_FILTER" || "$TYPE_FILTER" == "origin_pool" ]]; then
        echo "Checking origin_pool in namespace: $ns"
        audit_orphans "$ns" "origin_pool" "origin_pools"
    fi

    if [[ -z "$TYPE_FILTER" || "$TYPE_FILTER" == "app_firewall" ]]; then
        echo "Checking app_firewall in namespace: $ns"
        audit_orphans "$ns" "app_firewall" "app_firewalls"
    fi

    if [[ -z "$TYPE_FILTER" || "$TYPE_FILTER" == "service_policy" ]]; then
        echo "Checking service_policy in namespace: $ns"
        audit_orphans "$ns" "service_policy" "service_policys"
    fi

    if [[ -z "$TYPE_FILTER" || "$TYPE_FILTER" == "app_setting" ]]; then
        echo "Checking app_setting in namespace: $ns"
        audit_orphans "$ns" "app_setting" "app_settings"
    fi

    if [[ -z "$TYPE_FILTER" || "$TYPE_FILTER" == "api_definition" ]]; then
        echo "Checking api_definition in namespace: $ns"
        audit_orphans "$ns" "api_definition" "api_definitions"
    fi

    if [[ -z "$TYPE_FILTER" || "$TYPE_FILTER" == "http_loadbalancer" ]]; then
        echo "Checking http_loadbalancer in namespace: $ns"
        audit_orphans "$ns" "http_loadbalancer" "http_loadbalancers"
    fi
done

exec 3>&-

# Count orphans by type
while IFS= read -r line; do
    if [[ "$line" =~ ^ORPHAN_FOUND:(.+)$ ]]; then
        kind="${BASH_REMATCH[1]}"
        orphan_counts[$kind]=$((${orphan_counts[$kind]:-0} + 1))
        total_orphans=$((total_orphans + 1))
    fi
done < "$count_file"

rm -f "$count_file"

# Print summary
echo ""
echo "========================================================"
echo "  Audit Summary"
echo "========================================================"
echo ""

if [[ $total_orphans -eq 0 ]]; then
    echo "  No orphaned objects found."
else
    echo "  Total orphaned objects: $total_orphans"
    echo ""
    echo "  Breakdown by type:"
    for kind in "${!orphan_counts[@]}"; do
        echo "    - $kind: ${orphan_counts[$kind]}"
    done
fi

echo ""
echo "========================================================"
echo "  Audit complete."
echo "========================================================"
