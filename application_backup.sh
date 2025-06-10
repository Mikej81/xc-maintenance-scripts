#!/bin/bash

# Input validation
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <api_key> <tenant_name>"
    exit 1
fi

API_KEY="$1"
TENANT_NAME="$2"
API_BASE_URL="https://${TENANT_NAME}.console.ves.volterra.io"
BACKUP_DIR="./backups"

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Please install jq."
    exit 1
fi

# Function to send GET requests
send_request() {
    local url=$1
    curl -s -H "Authorization: APIToken $API_KEY" "$url"
}

# Step 1: Get the list of namespaces
namespace_response=$(send_request "$API_BASE_URL/api/web/namespaces")

# Check for empty response
if [[ -z "$namespace_response" ]]; then
    echo "Error: No response received when fetching namespaces."
    exit 1
fi

namespaces=$(echo "$namespace_response" | jq -r '.items[].name')

# Loop through each namespace
for namespace in $namespaces; do
    echo "Processing namespace: $namespace"
    ns_backup_dir="$BACKUP_DIR/$namespace"
    any_objects=false

    # --- CDN Loadbalancers ---
    cdn_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/cdn_loadbalancers")
    if echo "$cdn_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$cdn_list" | jq '.items | length')" -gt 0 ]; then
            mkdir -p "$ns_backup_dir/cdn_loadbalancers"
            cdn_names=$(echo "$cdn_list" | jq -r '.items[].name // empty')
            for name in $cdn_names; do
                obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/cdn_loadbalancers/$name")
                if [[ -n "$obj_json" ]]; then
                    echo "$obj_json" > "$ns_backup_dir/cdn_loadbalancers/${name}.json"
                    echo "   Backed up CDN LB: $name"
                    any_objects=true
                fi
            done
        fi
    else
        echo "Invalid JSON for CDN LB in namespace: $namespace"
    fi

    # --- HTTP Loadbalancers ---
    http_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/http_loadbalancers")
    if echo "$http_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$http_list" | jq '.items | length')" -gt 0 ]; then
            mkdir -p "$ns_backup_dir/http_loadbalancers"
            http_names=$(echo "$http_list" | jq -r '.items[].name // empty')
            for name in $http_names; do
                obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/http_loadbalancers/$name")
                if [[ -n "$obj_json" ]]; then
                    echo "$obj_json" > "$ns_backup_dir/http_loadbalancers/${name}.json"
                    echo "   Backed up HTTP LB: $name"
                    any_objects=true
                fi
            done
        fi
    fi

        if [ "$any_objects" = false ]; then
        echo "  No http load balancers found in namespace: $namespace"
    fi

    # --- TCP Loadbalancers ---
    tcp_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/tcp_loadbalancers")
    if echo "$tcp_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$tcp_list" | jq '.items | length')" -gt 0 ]; then
            mkdir -p "$ns_backup_dir/tcp_loadbalancers"
            tcp_names=$(echo "$tcp_list" | jq -r '.items[].name // empty')
            for name in $tcp_names; do
                obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/tcp_loadbalancers/$name")
                if [[ -n "$obj_json" ]]; then
                    echo "$obj_json" > "$ns_backup_dir/tcp_loadbalancers/${name}.json"
                    echo "   Backed up TCP LB: $name"
                    any_objects=true
                fi
            done
        fi
    fi

    if [ "$any_objects" = false ]; then
        echo "  No tcp load balancers found in namespace: $namespace"
    fi

    # --- Origin Pools ---
    origin_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/origin_pools")
    if echo "$origin_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$origin_list" | jq '.items | length')" -gt 0 ]; then
            mkdir -p "$ns_backup_dir/origin_pools"
            origin_names=$(echo "$origin_list" | jq -r '.items[].name // empty')
            for name in $origin_names; do
                obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/origin_pools/$name")
                if [[ -n "$obj_json" ]]; then
                    echo "$obj_json" > "$ns_backup_dir/origin_pools/${name}.json"
                    echo "   Backed up Origin Pool: $name"
                    any_objects=true
                fi
            done
        fi
    fi

    if [ "$any_objects" = false ]; then
        echo "  No origin pools found in namespace: $namespace"
    fi

    # --- Routes ---
    route_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/routes")
    if echo "$route_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$route_list" | jq '.items | length')" -gt 0 ]; then
            mkdir -p "$ns_backup_dir/routes"
            route_names=$(echo "$route_list" | jq -r '
              .items[]
              | select(
                  (type == "object")
                  and ((.namespace == "shared" or .tenant == "ves-io") | not)
                  and ((.name | startswith("ves-io-")) | not)
              )
              | .name')
            for name in $route_names; do
                obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/routes/$name")
                if [[ -n "$obj_json" ]]; then
                    echo "$obj_json" > "$ns_backup_dir/routes/${name}.json"
                    echo "   Backed up Route: $name"
                    any_objects=true
                fi
            done
        fi
    fi

    if [ "$any_objects" = false ]; then
        echo "  No routes found in namespace: $namespace"
    fi    

# --- Certificates ---
cert_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/certificates")
if echo "$cert_list" | jq -e . >/dev/null 2>&1; then
    if [ "$(echo "$cert_list" | jq '.items | length')" -gt 0 ]; then
        cert_names=$(echo "$cert_list" | jq -r '
          .items[]
          | select(
              (type == "object")
              and ((.namespace == "shared") | not)
              and ((.name | startswith("ves-io-")) | not)
          )
          | .name')

        if [ -n "$cert_names" ]; then
            mkdir -p "$ns_backup_dir/certificates"
            for name in $cert_names; do
                obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/certificates/$name")
                if [[ -n "$obj_json" ]]; then
                    echo "$obj_json" > "$ns_backup_dir/certificates/${name}.json"
                    echo "   Backed up Certificate: $name"
                    any_objects=true
                fi
            done
        fi
    fi
fi


    if [ "$any_objects" = false ]; then
        echo "  No certificates found in namespace: $namespace"
    fi       

    # --- Service Policies ---
    policy_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/service_policys")
    if echo "$policy_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$policy_list" | jq '.items | length')" -gt 0 ]; then
            # Only get policy names where namespace is NOT shared
            policy_names=$(echo "$policy_list" | jq -r '
              .items[]
              | select(
                  (type == "object")
                  and ((.namespace == "shared" or .tenant == "ves-io") | not)
                  and ((.name | startswith("ves-io-")) | not)
              )
              | .name')

            if [ -n "$policy_names" ]; then
                mkdir -p "$ns_backup_dir/service_policys"
                for name in $policy_names; do
                    obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/service_policys/$name")
                    if [[ -n "$obj_json" ]]; then
                        echo "$obj_json" > "$ns_backup_dir/service_policys/${name}.json"
                        echo "   Backed up Service Policy: $name"
                        any_objects=true
                    fi
                done
            fi
        fi
    fi

# --- Application Firewalls ---
firewall_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/app_firewalls")
if echo "$firewall_list" | jq -e . >/dev/null 2>&1; then
    if [ "$(echo "$firewall_list" | jq '.items | length')" -gt 0 ]; then
        # Apply advanced filters:
        # 1. Exclude if tenant is "ves-io" and namespace is "shared"
        # 2. Exclude if name starts with "ves-io-"
        firewall_names=$(echo "$firewall_list" | jq -r '
          .items[]
          | select(
              (type == "object")
              and ((.namespace == "shared" or .tenant == "ves-io") | not)
              and ((.name | startswith("ves-io-")) | not)
          )
          | .name')


        if [ -n "$firewall_names" ]; then
            mkdir -p "$ns_backup_dir/app_firewalls"
            for name in $firewall_names; do
                obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/app_firewalls/$name")
                if [[ -n "$obj_json" ]]; then
                    echo "$obj_json" > "$ns_backup_dir/app_firewalls/${name}.json"
                    echo "   Backed up App Firewall: $name"
                    any_objects=true
                fi
            done
        fi
    fi
fi


    echo "----------------------------------------"
done
