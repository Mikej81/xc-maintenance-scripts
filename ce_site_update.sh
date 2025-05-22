#!/bin/bash

# Check if the site-name, tenant-name, and API Token arguments are provided
if [ -z "$1" ]; then
    echo "Error: No site-name argument provided."
    echo "Usage: $0 <site-name> <tenant-name> <api-token>"
    exit 1
fi

if [ -z "$2" ]; then
    echo "Error: No tenant-name argument provided."
    echo "Usage: $0 <site-name> <tenant-name> <api-token>"
    exit 1
fi

if [ -z "$3" ]; then
    echo "Error: No API Token argument provided."
    echo "Usage: $0 <site-name> <tenant-name> <api-token>"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Please install jq."
    exit 1
fi

# Assign the arguments to variables
SITE_NAME="$1"
TENANT_NAME="$2"
API_TOKEN="$3"

# Construct the API URL with the site-name and tenant-name
API_URL="https://${TENANT_NAME}.console.ves.volterra.io/api/config/namespaces/system/sites/${SITE_NAME}"

# Use curl to fetch the JSON data
json_data=$(curl -H "Authorization: APIToken ${API_TOKEN}" -s "$API_URL")

# Use jq to extract the operating system update information
os_updates=$(echo "$json_data" | jq -r '.status[] | select(.operating_system_status != null) | .operating_system_status | select(.available_version != .deployment_state.version) | .available_version')

# Check if there are version updates for the operating system
if [ -z "$os_updates" ]; then
    echo "No OS updates found for site $SITE_NAME"
else
    echo "OS updates for site $SITE_NAME:"

    # Loop through each OS version update
    for os_version in $os_updates; do
        echo "OS update available: $os_version"

        # Construct the POST request body
        post_data="{\"version\":\"$os_version\"}"

        # Replace with the actual POST API endpoint
        POST_API_URL="$API_URL/upgrade_os"

        # Make the POST request
        response=$(curl -s -X POST -H "Authorization: APIToken ${API_TOKEN}" -H "Content-Type: application/json" -d "$post_data" "$POST_API_URL")

        echo "Response for OS version $os_version:"
        echo "$response"
    done
fi

# Use jq to extract the information
version_updates=$(echo "$json_data" | jq -r '.status[] | select(.volterra_software_status != null) | .volterra_software_status | select(.available_version != .deployment_state.version) | .available_version')

# Check if there are version updates
if [ -z "$version_updates" ]; then
    echo "No version updates found for site $SITE_NAME"
else
    echo "Version updates for site $SITE_NAME:"

    # Loop through each version update
    for version in $version_updates; do
        echo "Update available: $version"

        # Construct the POST request body
        post_data="{\"version\":\"$version\"}"

        # Replace with the actual POST API endpoint
        POST_API_URL="$API_URL/upgrade_sw"

        # Make the POST request
        response=$(curl -s -X POST -H "Authorization: APIToken ${API_TOKEN}" -H "Content-Type: application/json" -d "$post_data" "$POST_API_URL")

        echo "Response for version $version:"
        echo "$response"
    done
fi
