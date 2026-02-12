#!/bin/bash

# lb_cert_conversion.sh
# Converts HTTP load balancers from manual certificate (https) to auto-certificate (https_auto_cert).
# F5 XC does not support in-place replacement, so this script backs up the config,
# deletes the old LB, and re-creates it with https_auto_cert.

# --- Input Validation & Setup ---

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <api_key> <tenant_name> --namespace=<ns> [--lb-name=<name>] [--all] [--dry-run] [--yes]"
    echo ""
    echo "  api_key         F5 XC API token"
    echo "  tenant_name     Tenant domain prefix"
    echo "  --namespace=    Target namespace (required)"
    echo "  --lb-name=      Specific LB to convert"
    echo "  --all           Convert all manual-cert LBs in namespace"
    echo "  --dry-run       Show what would change without executing"
    echo "  --yes           Skip per-LB confirmation prompts"
    echo ""
    echo "Either --lb-name or --all must be provided."
    exit 1
fi

API_KEY="$1"
TENANT_NAME="$2"
NAMESPACE=""
LB_NAME=""
ALL_MODE=false
DRY_RUN=false
YES_MODE=false

# Parse optional arguments
for arg in "${@:3}"; do
    if [[ "$arg" =~ ^--namespace=(.+)$ ]]; then
        NAMESPACE="${BASH_REMATCH[1]}"
    elif [[ "$arg" =~ ^--lb-name=(.+)$ ]]; then
        LB_NAME="${BASH_REMATCH[1]}"
    elif [[ "$arg" == "--all" ]]; then
        ALL_MODE=true
    elif [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
    elif [[ "$arg" == "--yes" ]]; then
        YES_MODE=true
    else
        echo "Error: Unknown argument '$arg'"
        exit 1
    fi
done

if [[ -z "$NAMESPACE" ]]; then
    echo "Error: --namespace= is required."
    exit 1
fi

if [[ -z "$LB_NAME" && "$ALL_MODE" == false ]]; then
    echo "Error: Either --lb-name=<name> or --all must be provided."
    exit 1
fi

if [[ -n "$LB_NAME" && "$ALL_MODE" == true ]]; then
    echo "Error: --lb-name and --all cannot be used together."
    exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Please install jq."
    exit 1
fi

API_BASE_URL="https://${TENANT_NAME}.console.ves.volterra.io/api"
BACKUP_DIR="./backups"

# --- Helper Functions ---

send_request() {
    local url=$1
    curl -s -H "Authorization: APIToken $API_KEY" "$url"
}

# Counters for summary
CONVERTED=0
SKIPPED=0
FAILED=0

# Collect DNS info for consolidated table at the end
DNS_ENTRIES=""

convert_lb() {
    local namespace=$1
    local lb_name=$2

    echo ""
    echo "--- Processing LB: $lb_name ---"

    # 1. Fetch full config
    local original_json
    original_json=$(send_request "$API_BASE_URL/config/namespaces/$namespace/http_loadbalancers/$lb_name")

    if [[ -z "$original_json" ]] || ! echo "$original_json" | jq -e . >/dev/null 2>&1; then
        echo "  Error: Failed to fetch LB '$lb_name' or response is not valid JSON."
        FAILED=$((FAILED + 1))
        return 1
    fi

    # 2. Validate it has an https key (manual cert)
    if ! echo "$original_json" | jq -e '.spec.https' >/dev/null 2>&1; then
        echo "  Skipping: LB '$lb_name' does not use manual certificate (no 'https' key in spec)."
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi

    # 3. Backup original JSON
    local backup_dir="$BACKUP_DIR/$namespace/http_loadbalancers"
    mkdir -p "$backup_dir"
    echo "$original_json" > "$backup_dir/${lb_name}.pre-conversion.json"
    echo "  Backup saved to: $backup_dir/${lb_name}.pre-conversion.json"

    # 4. Build new spec using jq
    local new_spec
    new_spec=$(echo "$original_json" | jq '
        .spec as $spec |
        $spec.https as $https |
        ($https | del(.tls_cert_params)) as $shared |
        ($shared + {
            tls_config: ($https.tls_cert_params.tls_config // {"default_security": {}}),
            no_mtls: {}
        }) as $auto_cert |
        $spec
        | del(.https)
        | del(.auto_cert_info, .cert_state, .dns_info,
              .downstream_tls_certificate_expiration_timestamps,
              .host_name, .internet_vip_info, .state)
        | .https_auto_cert = $auto_cert
    ')

    if [[ -z "$new_spec" ]] || ! echo "$new_spec" | jq -e . >/dev/null 2>&1; then
        echo "  Error: Failed to build new spec for LB '$lb_name'."
        FAILED=$((FAILED + 1))
        return 1
    fi

    local create_body
    create_body=$(echo "$original_json" | jq --argjson spec "$new_spec" '
        {metadata: .metadata, spec: $spec}
    ')

    # 5. Dry-run check
    if [[ "$DRY_RUN" == true ]]; then
        local domains
        domains=$(echo "$original_json" | jq -r '.spec.domains[]? // empty')
        echo "  [DRY RUN] Would convert LB '$lb_name' from manual-cert (https) to auto-cert (https_auto_cert)"
        echo "  Domains: $domains"
        CONVERTED=$((CONVERTED + 1))
        return 0
    fi

    # 6. Confirmation
    if [[ "$YES_MODE" == false ]]; then
        read -r -p "  Convert LB '$lb_name' from manual-cert to auto-cert? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "  Skipped by user."
            SKIPPED=$((SKIPPED + 1))
            return 0
        fi
    fi

    # 7. Delete old LB
    echo "  Deleting old LB '$lb_name'..."
    local delete_body
    delete_body=$(jq -n --arg name "$lb_name" --arg namespace "$namespace" \
        '{name: $name, namespace: $namespace}')

    local delete_response
    delete_response=$(curl -s -X DELETE \
        -H "Authorization: APIToken $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$delete_body" \
        "$API_BASE_URL/config/namespaces/$namespace/http_loadbalancers/$lb_name")

    if echo "$delete_response" | jq -e '.code' >/dev/null 2>&1; then
        local err_code
        err_code=$(echo "$delete_response" | jq -r '.code')
        if [[ "$err_code" != "0" && "$err_code" != "null" ]]; then
            echo "  Error: Failed to delete LB '$lb_name'."
            echo "  Response: $delete_response"
            FAILED=$((FAILED + 1))
            return 1
        fi
    fi
    echo "  Deleted successfully."

    # 8. Create new LB
    echo "  Creating new LB '$lb_name' with auto-cert..."
    local create_response
    create_response=$(curl -s -X POST \
        -H "Authorization: APIToken $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$create_body" \
        "$API_BASE_URL/config/namespaces/$namespace/http_loadbalancers")

    if ! echo "$create_response" | jq -e '.metadata.name' >/dev/null 2>&1; then
        echo "  Error: Failed to create new LB '$lb_name'."
        echo "  Response: $create_response"
        echo "  NOTE: Original config is backed up at $backup_dir/${lb_name}.pre-conversion.json"
        FAILED=$((FAILED + 1))
        return 1
    fi
    echo "  Created successfully."

    # 9. Verify creation
    echo "  Verifying new LB..."
    sleep 2
    local verify_json
    verify_json=$(send_request "$API_BASE_URL/config/namespaces/$namespace/http_loadbalancers/$lb_name")

    if ! echo "$verify_json" | jq -e '.spec.https_auto_cert' >/dev/null 2>&1; then
        echo "  Warning: Verification failed - LB '$lb_name' may not have https_auto_cert set."
        echo "  Please check manually in the F5 XC console."
        FAILED=$((FAILED + 1))
        return 1
    fi
    echo "  Verified: LB '$lb_name' now uses https_auto_cert."

    # 10. Output DNS info
    echo ""
    echo "  DNS Update Required for LB: $lb_name"
    local dns_info
    dns_info=$(echo "$verify_json" | jq -r '
        .spec.dns_info // [] | .[] |
        "    Domain: \(.domain // "N/A")\n      CNAME -> \(.dns_cname // .ip_address // "pending")"
    ')
    if [[ -n "$dns_info" ]]; then
        echo -e "$dns_info"
        DNS_ENTRIES="${DNS_ENTRIES}\n  LB: $lb_name\n$dns_info\n"
    else
        echo "    DNS info not yet available (may take a moment to propagate)."
        DNS_ENTRIES="${DNS_ENTRIES}\n  LB: $lb_name\n    DNS info pending\n"
    fi

    local auto_cert_info
    auto_cert_info=$(echo "$verify_json" | jq -r '
        .spec.auto_cert_info // {} |
        if .dns_records then
            .dns_records[] | "    Auto-cert DNS: \(.name // "N/A") -> \(.value // "N/A") (\(.type // "N/A"))"
        else
            empty
        end
    ')
    if [[ -n "$auto_cert_info" ]]; then
        echo "$auto_cert_info"
        DNS_ENTRIES="${DNS_ENTRIES}$auto_cert_info\n"
    fi

    # 11. Report success
    echo ""
    echo "  LB '$lb_name' converted successfully."
    CONVERTED=$((CONVERTED + 1))
    return 0
}

# --- Validate API Token ---

echo "Validating API token..."
auth_check=$(send_request "$API_BASE_URL/web/namespaces")
if ! echo "$auth_check" | jq -e '.items' &>/dev/null; then
    echo "Error: API token may be invalid or response is not JSON."
    echo "Response received:"
    echo "$auth_check"
    exit 1
fi
echo "API token validated."

# --- Main Logic ---

if [[ -n "$LB_NAME" ]]; then
    # Single LB mode
    convert_lb "$NAMESPACE" "$LB_NAME"
else
    # All mode - list all LBs in namespace
    echo ""
    echo "Listing HTTP load balancers in namespace '$NAMESPACE'..."
    lb_list=$(send_request "$API_BASE_URL/config/namespaces/$NAMESPACE/http_loadbalancers")

    if ! echo "$lb_list" | jq -e '.items' >/dev/null 2>&1; then
        echo "Error: Failed to list load balancers in namespace '$NAMESPACE'."
        echo "Response: $lb_list"
        exit 1
    fi

    lb_count=$(echo "$lb_list" | jq '.items | length')
    if [[ "$lb_count" -eq 0 ]]; then
        echo "No HTTP load balancers found in namespace '$NAMESPACE'."
        exit 0
    fi

    echo "Found $lb_count HTTP load balancer(s). Checking for manual-cert configurations..."

    lb_names=$(echo "$lb_list" | jq -r '.items[].name // empty')
    for name in $lb_names; do
        convert_lb "$NAMESPACE" "$name"
    done
fi

# --- Summary ---
echo ""
echo "========================================"
echo "Conversion Summary"
echo "========================================"
if [[ "$DRY_RUN" == true ]]; then
    echo "  Mode: DRY RUN (no changes made)"
fi
echo "  Converted: $CONVERTED"
echo "  Skipped:   $SKIPPED"
echo "  Failed:    $FAILED"
echo "========================================"

# Consolidated DNS table
if [[ -n "$DNS_ENTRIES" && "$DRY_RUN" == false && "$CONVERTED" -gt 0 ]]; then
    echo ""
    echo "========================================"
    echo "Consolidated DNS Updates Required"
    echo "========================================"
    echo -e "$DNS_ENTRIES"
    echo "========================================"
fi
