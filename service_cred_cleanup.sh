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

# Construct the API URL with the site-name and tenant-name
API_URL="https://${TENANT_NAME}.console.ves.volterra.io/api/web/namespaces/system/service_credentials"
REVOKE_URL="https://${TENANT_NAME}.console.ves.volterra.io/api/web/namespaces/system/revoke/service_credentials"

# Query the API and store the output in a variable
api_response=$(curl -H "Authorization: APIToken ${API_KEY}" -s "$API_URL")

# Check if the API response contains data
if [[ -z "$api_response" ]]; then
    echo "Error: Empty response from API."
    exit 1
fi

# Current timestamp in ISO 8601 format
current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Loop through items and check each expiry_timestamp
echo "$api_response" | jq -c '.items[]' | while read -r item; do
    # Get expiry timestamp
    expiry_timestamp=$(echo "$item" | jq -r '.expiry_timestamp')
    
    # Check if expiry timestamp has passed
    if [[ "$expiry_timestamp" < "$current_time" ]]; then
        # Get the name and namespace for expired items
        name=$(echo "$item" | jq -r '.name')
        namespace=$(echo "$item" | jq -r '.namespace')
        
        # Construct the JSON body for the revoke request
        json_body=$(jq -n --arg name "$name" --arg namespace "$namespace" '{name: $name, namespace: $namespace}')
        
        echo "Revoking item '$name' in namespace '$namespace' (Expiry: $expiry_timestamp)"
        
        # Make the revoke API call with the JSON body
        # This will revoke, it could be changed to renew.
        revoke_response=$(curl -X POST -H "Authorization: APIToken ${API_KEY}" -H "Content-Type: application/json" -d "$json_body" -s "$REVOKE_URL")
        
        # print the revoke response or handle errors
        echo "Revoke response: $revoke_response"
    fi
done
