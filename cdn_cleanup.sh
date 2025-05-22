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

# Construct the API base URL
API_BASE_URL="https://${TENANT_NAME}.console.ves.volterra.io/api"

# Color variables
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to send GET requests
send_request() {
    local url=$1
    curl -s -H "Authorization: APIToken $API_KEY" "$url"
}

# Function to send DELETE requests
send_delete_request() {
    local url=$1
    curl -s -X DELETE -H "Authorization: APIToken $API_KEY" "$url"
}

# Step 1: Get the list of namespaces
namespace_response=$(send_request "$API_BASE_URL/web/namespaces")

# Check for empty response
if [[ -z "$namespace_response" ]]; then
    echo "Error: No response received when fetching namespaces."
    exit 1
fi

namespaces=$(echo "$namespace_response" | jq -r '.items[].name')

# Step 2: Query CDN Loadbalancers for each namespace
for namespace in $namespaces; do
    echo "Checking CDN Loadbalancers for namespace: $namespace"
    
    loadbalancers=$(send_request "$API_BASE_URL/config/namespaces/$namespace/cdn_loadbalancers" | jq -r '.items[]')
    
    if [ -n "$loadbalancers" ]; then

        echo $loadbalancers | while IFS= read -r loadbalancer; do
            loadbalancer_name=$(echo $loadbalancer | jq -r '.name')

            echo -e "${RED}Found loadbalancer: $loadbalancer_name in namespace: $namespace${NC}"
                        
            # Step 3: Delete the CDN Loadbalancer
            delete_url="$API_BASE_URL/config/namespaces/$namespace/cdn_loadbalancers/$loadbalancer_name"
            #delete_response=$(send_delete_request "$delete_url")

            #echo "Delete URL: $delete_url"

            # if [ -z "$delete_response" ]; then
            #     echo "Successfully deleted CDN Loadbalancer: $loadbalancer in namespace: $namespace"
            # else
            #     echo "Failed to delete CDN Loadbalancer: $loadbalancer in namespace: $namespace"
            #     echo "Response: $delete_response"
            # fi

        done
    else
        echo "No loadbalancers found in namespace: $namespace"
    fi

    echo "----------------------------------------"

done

