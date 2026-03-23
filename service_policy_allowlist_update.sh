#!/bin/bash

# Update or create a Service Policy allow list with the current public IP address
# obtained from ipv4.icanhazip.com
#
# Usage: ./service_policy_allowlist_update.sh <policy-name> <namespace> <tenant-name> <api-token>

# Check arguments
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
    echo "Usage: $0 <policy-name> <namespace> <tenant-name> <api-token>"
    echo ""
    echo "  policy-name  - Name of the service policy to create/update"
    echo "  namespace    - XC namespace for the service policy"
    echo "  tenant-name  - XC tenant name (e.g. 'acmecorp')"
    echo "  api-token    - XC API token"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq."
    exit 1
fi

POLICY_NAME="$1"
NAMESPACE="$2"
TENANT_NAME="$3"
API_TOKEN="$4"

BASE_URL="https://${TENANT_NAME}.console.ves.volterra.io"
API_PATH="/api/config/namespaces/${NAMESPACE}/service_policys"
AUTH_HEADER="Authorization: APIToken ${API_TOKEN}"
CONTENT_TYPE="Content-Type: application/json"

# Get current public IP
echo "Fetching current public IP..."
MY_IP=$(curl -s -4 https://ipv4.icanhazip.com | tr -d '[:space:]')

if [ -z "$MY_IP" ]; then
    echo "Error: Failed to retrieve public IP address."
    exit 1
fi

MY_PREFIX="${MY_IP}/32"
echo "Current public IP: ${MY_IP} (${MY_PREFIX})"

# Check if the service policy already exists
echo "Checking for existing service policy '${POLICY_NAME}' in namespace '${NAMESPACE}'..."
existing=$(curl -s -w "\n%{http_code}" \
    -H "${AUTH_HEADER}" \
    "${BASE_URL}${API_PATH}/${POLICY_NAME}?response_format=GET_RSP_FORMAT_FOR_REPLACE")

http_code=$(echo "$existing" | tail -1)
response_body=$(echo "$existing" | sed '$d')

if [ "$http_code" -eq 200 ]; then
    echo "Service policy found. Updating allow list..."

    # The GET_RSP_FORMAT_FOR_REPLACE response wraps data under .replace_form
    replace_form=$(echo "$response_body" | jq '.replace_form // {metadata: .metadata, spec: .spec}')

    # Extract the current spec and check if our IP is already present
    current_prefixes=$(echo "$replace_form" | jq -r '.spec.allow_list.prefix_list.prefixes // [] | .[]' 2>/dev/null)

    # Check if IP already exists in the prefix list
    if echo "$current_prefixes" | grep -qx "$MY_PREFIX"; then
        echo "IP ${MY_PREFIX} is already in the allow list. No update needed."
        exit 0
    fi

    # Build the updated prefix list by adding our IP to the existing ones
    updated_prefixes=$(echo "$replace_form" | jq --arg ip "$MY_PREFIX" \
        '.spec.allow_list.prefix_list.prefixes = ((.spec.allow_list.prefix_list.prefixes // []) + [$ip] | unique)')

    # Build the replace request body using the existing config
    replace_body=$(echo "$updated_prefixes" | jq '{
        metadata: {
            name: .metadata.name,
            namespace: .metadata.namespace,
            labels: (.metadata.labels // {}),
            annotations: (.metadata.annotations // {}),
            description: (.metadata.description // "")
        },
        spec: .spec
    }')

    # Replace the service policy
    response=$(curl -s -w "\n%{http_code}" -X PUT \
        -H "${AUTH_HEADER}" \
        -H "${CONTENT_TYPE}" \
        -d "$replace_body" \
        "${BASE_URL}${API_PATH}/${POLICY_NAME}")

    put_code=$(echo "$response" | tail -1)
    put_body=$(echo "$response" | sed '$d')

    if [ "$put_code" -eq 200 ]; then
        echo "Successfully updated service policy '${POLICY_NAME}' with IP ${MY_PREFIX}."
    else
        echo "Error updating service policy (HTTP ${put_code}):"
        echo "$put_body" | jq . 2>/dev/null || echo "$put_body"
        exit 1
    fi

else
    echo "Service policy not found (HTTP ${http_code}). Creating new policy..."

    # Create a new service policy with the allow list
    create_body=$(jq -n \
        --arg name "$POLICY_NAME" \
        --arg ns "$NAMESPACE" \
        --arg ip "$MY_PREFIX" \
        '{
            metadata: {
                name: $name,
                namespace: $ns,
                description: "Allow list managed by service_policy_allowlist_update.sh"
            },
            spec: {
                allow_list: {
                    prefix_list: {
                        prefixes: [$ip]
                    },
                    default_action_deny: {}
                },
                any_server: {}
            }
        }')

    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "${AUTH_HEADER}" \
        -H "${CONTENT_TYPE}" \
        -d "$create_body" \
        "${BASE_URL}${API_PATH}")

    post_code=$(echo "$response" | tail -1)
    post_body=$(echo "$response" | sed '$d')

    if [ "$post_code" -eq 200 ]; then
        echo "Successfully created service policy '${POLICY_NAME}' with IP ${MY_PREFIX}."
    else
        echo "Error creating service policy (HTTP ${post_code}):"
        echo "$post_body" | jq . 2>/dev/null || echo "$post_body"
        exit 1
    fi
fi
