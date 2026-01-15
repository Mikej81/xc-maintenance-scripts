#!/bin/bash

# Input validation
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <api_key> <tenant_name> [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --inactive-days=N    Only show users inactive for more than N days"
    echo "  --format=FORMAT      Output format: table (default), csv"
    echo ""
    echo "Examples:"
    echo "  $0 myapikey mytenant"
    echo "  $0 myapikey mytenant --inactive-days=90"
    echo "  $0 myapikey mytenant --format=csv"
    exit 1
fi

API_KEY="$1"
TENANT_NAME="$2"
INACTIVE_DAYS=""
OUTPUT_FORMAT="table"

# Parse optional arguments
for arg in "$@"; do
    if [[ "$arg" =~ ^--inactive-days=([0-9]+)$ ]]; then
        INACTIVE_DAYS="${BASH_REMATCH[1]}"
    elif [[ "$arg" =~ ^--format=(table|csv)$ ]]; then
        OUTPUT_FORMAT="${BASH_REMATCH[1]}"
    fi
done

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Please install jq."
    exit 1
fi

# Construct the base API URL
BASE_URL="https://${TENANT_NAME}.console.ves.volterra.io"
API_BASE_URL="${BASE_URL}/api"

# Validate API token by making a test call
auth_check=$(curl -s -H "Authorization: APIToken ${API_KEY}" \
  "$API_BASE_URL/web/namespaces")

if ! echo "$auth_check" | jq -e '.items' &>/dev/null; then
    echo "Error: API token may be invalid or response is not JSON."
    echo "Response received:"
    echo "$auth_check"
    exit 1
fi

# Current timestamp for reference
current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
current_epoch=$(date +%s)

# Calculate cutoff date if filtering by inactive days
cutoff_epoch=0
if [[ -n "$INACTIVE_DAYS" ]]; then
    cutoff_epoch=$(date -d "-${INACTIVE_DAYS} days" +%s)
fi

# Fetch all users
users_response=$(curl -s -H "Authorization: APIToken ${API_KEY}" \
  "$API_BASE_URL/web/custom/namespaces/system/users")

# Check if response is valid
if ! echo "$users_response" | jq -e '.items' &>/dev/null; then
    echo "Error: Unable to fetch users. Response:"
    echo "$users_response"
    exit 1
fi

# Counters for summary
total_users=0
active_users=0
inactive_users=0
disabled_users=0

# Print header based on format
if [[ "$OUTPUT_FORMAT" == "csv" ]]; then
    echo "Email,Name,Type,Domain,Last Login,Days Inactive,Roles,Status"
else
    echo ""
    echo "========================================================"
    echo "  User Audit Report"
    echo "  Tenant: $TENANT_NAME"
    echo "  Generated: $current_time"
    if [[ -n "$INACTIVE_DAYS" ]]; then
        echo "  Filter: Users inactive for more than $INACTIVE_DAYS days"
    fi
    echo "========================================================"
    echo ""
fi

# Process each user
echo "$users_response" | jq -c '.items[]' | while read -r user; do
    email=$(echo "$user" | jq -r '.email // "N/A"')
    first_name=$(echo "$user" | jq -r '.first_name // ""')
    last_name=$(echo "$user" | jq -r '.last_name // ""')
    full_name="${first_name} ${last_name}"
    full_name=$(echo "$full_name" | xargs)  # Trim whitespace
    [[ -z "$full_name" ]] && full_name="N/A"

    user_type=$(echo "$user" | jq -r '.type // "N/A"')
    domain=$(echo "$user" | jq -r '.domain // "N/A"')
    disabled=$(echo "$user" | jq -r '.disabled // false')

    # Get last login time
    last_login=$(echo "$user" | jq -r '.last_login_timestamp // "Never"')

    # Calculate days since last login
    days_inactive="N/A"
    if [[ "$last_login" != "Never" && "$last_login" != "null" ]]; then
        last_login_epoch=$(date -d "$last_login" +%s 2>/dev/null || echo "0")
        if [[ "$last_login_epoch" != "0" ]]; then
            days_inactive=$(( (current_epoch - last_login_epoch) / 86400 ))
        fi
    fi

    # Get namespace roles
    namespace_roles=$(echo "$user" | jq -r '.namespace_roles // []')
    role_list=""
    if [[ "$namespace_roles" != "[]" && "$namespace_roles" != "null" ]]; then
        role_list=$(echo "$user" | jq -r '.namespace_roles[] | "\(.namespace):\(.role)"' 2>/dev/null | tr '\n' ';' | sed 's/;$//')
    fi
    [[ -z "$role_list" ]] && role_list="None"

    # Determine status
    status="Active"
    if [[ "$disabled" == "true" ]]; then
        status="Disabled"
    elif [[ "$days_inactive" != "N/A" && "$days_inactive" -gt 90 ]]; then
        status="Inactive"
    elif [[ "$last_login" == "Never" || "$last_login" == "null" ]]; then
        status="Never Logged In"
    fi

    # Apply inactive filter if specified
    if [[ -n "$INACTIVE_DAYS" ]]; then
        if [[ "$days_inactive" == "N/A" ]]; then
            # Include users who never logged in
            :
        elif [[ "$days_inactive" -lt "$INACTIVE_DAYS" ]]; then
            continue
        fi
    fi

    # Format last login for display
    last_login_display="$last_login"
    if [[ "$last_login" != "Never" && "$last_login" != "null" ]]; then
        last_login_display=$(date -d "$last_login" +"%Y-%m-%d %H:%M" 2>/dev/null || echo "$last_login")
    fi

    # Output based on format
    if [[ "$OUTPUT_FORMAT" == "csv" ]]; then
        echo "\"$email\",\"$full_name\",\"$user_type\",\"$domain\",\"$last_login_display\",\"$days_inactive\",\"$role_list\",\"$status\""
    else
        echo "User: $email"
        echo "    Name: $full_name"
        echo "    Type: $user_type"
        echo "    Domain: $domain"
        echo "    Last Login: $last_login_display"
        echo "    Days Inactive: $days_inactive"
        echo "    Roles: $role_list"
        echo "    Status: $status"
        echo ""
    fi
done

# Fetch summary counts (run again to count since the while loop runs in a subshell)
total_users=$(echo "$users_response" | jq '.items | length')
disabled_users=$(echo "$users_response" | jq '[.items[] | select(.disabled == true)] | length')
never_logged_in=$(echo "$users_response" | jq '[.items[] | select(.last_login_timestamp == null)] | length')

# Print summary (only for table format)
if [[ "$OUTPUT_FORMAT" == "table" ]]; then
    echo "========================================================"
    echo "  Summary"
    echo "========================================================"
    echo ""
    echo "  Total Users: $total_users"
    echo "  Disabled Users: $disabled_users"
    echo "  Never Logged In: $never_logged_in"
    echo ""
    echo "========================================================"
    echo "  Audit complete."
    echo "========================================================"
fi
