#!/bin/bash

# Input validation
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <api_key> <tenant_name>"
    exit 1
fi

API_KEY="$1"
TENANT_NAME="$2"
BASE_URL="https://${TENANT_NAME}.console.ves.volterra.io"

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Please install jq."
    exit 1
fi

# Fetch CE sites with full report fields
SITE_LIST=$(curl -s -H "Authorization: APIToken $API_KEY" \
  "$BASE_URL/api/config/namespaces/system/sites?report_fields=&report_status_fields=&")

# Check response
if [ -z "$SITE_LIST" ] || ! echo "$SITE_LIST" | jq . &> /dev/null; then
    echo "Error: Failed to fetch valid site list"
    exit 1
fi

echo "Site Reboot Summary"
echo "===================="

# Filter and loop through CE sites that are ONLINE
echo "$SITE_LIST" | jq -r '.items[] | select(.labels["ves.io/siteType"] == "ves-io-ce" and .get_spec.site_state == "ONLINE") | .name' | while read -r SITE_NAME; do

    # Fetch site object to extract main_nodes
    SITE_DETAIL=$(curl -s -H "Authorization: APIToken $API_KEY" "$BASE_URL/api/config/namespaces/system/sites/$SITE_NAME")

    if [ -z "$SITE_DETAIL" ] || ! echo "$SITE_DETAIL" | jq . &> /dev/null; then
        echo "[$SITE_NAME] Error: Unable to retrieve site detail"
        continue
    fi

    NODE_NAMES=$(echo "$SITE_DETAIL" | jq -r '.spec.main_nodes[]?.name')

    if [ -z "$NODE_NAMES" ]; then
        echo "[$SITE_NAME] Warning: No main_nodes found"
        continue
    fi

    echo ""
    echo "Site: $SITE_NAME"
    echo "--------------------"

    # Loop through each node in the site
    for NODE_NAME in $NODE_NAMES; do
        RESPONSE=$(curl -s -X POST \
          -H "Authorization: APIToken $API_KEY" \
          -H "Content-Type: application/json" \
          "$BASE_URL/api/operate/namespaces/system/sites/$SITE_NAME/vpm/debug/$NODE_NAME/exec-user" \
          -d '{"command": ["journalctl --list-boots"]}')

        # Parse and clean output
        LAST_BOOT=$(echo "$RESPONSE" | jq -r '.output' | grep -v '^\s*$' | tail -n 1)

        if [ -z "$LAST_BOOT" ]; then
            echo "  $NODE_NAME: Unable to determine last reboot"
        else
            echo "  $NODE_NAME: $LAST_BOOT"
        fi
    done
done
