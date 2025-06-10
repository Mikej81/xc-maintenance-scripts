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

namespaces=$(echo "$namespace_response" | jq -r '.items[].name' | grep -v '^system$')
#namespaces+=" shared"

    # Loop through each namespace
    for namespace in $namespaces; do

    # Determine namespace context
    is_special_namespace=false
    if [[ "$namespace" == "shared" ]]; then
        is_special_namespace=true
    fi

    # Define jqfilter based on whether we are in a system/shared namespace
    if [[ "$is_special_namespace" == "true" ]]; then
        jqfilter='.items[] 
            | select(
                (type == "object")
                and (.namespace != "system")
                and ((.name | startswith("ves-io-")) | not)
            ) 
            | .name'
    else
        jqfilter='.items[] 
            | select(
                (type == "object") 
                and (.namespace != "shared")
                and (.namespace != "system")
                and (.tenant != "ves-io") 
                and ((.name | startswith("ves-io-")) | not)
            ) 
            | .name'
    fi

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
                    #any_objects=true
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
                    #any_objects=true
                fi
            done
        fi
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
                    #any_objects=true
                fi
            done
        fi
    fi

    # --- DRP ---
    drp_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/proxys")
    if echo "$drp_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$drp_list" | jq '.items | length')" -gt 0 ]; then
            mkdir -p "$ns_backup_dir/proxys"
            drp_names=$(echo "$drp_list" | jq -r '.items[].name // empty')
            for name in $drp_names; do
                obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/proxys/$name")
                if [[ -n "$obj_json" ]]; then
                    echo "$obj_json" > "$ns_backup_dir/proxys/${name}.json"
                    echo "   Backed up DRP: $name"
                    #any_objects=true
                fi
            done
        fi
    fi

    # --- Virtual Sites ---
    vs_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/virtual_sites")
    if echo "$vs_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$vs_list" | jq '.items | length')" -gt 0 ]; then
            
            vs_names=$(echo "$vs_list" | jq -r "$jqfilter")
            for name in $vs_names; do
                obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/virtual_sites/$name")
                if [[ -n "$obj_json" ]]; then
                    mkdir -p "$ns_backup_dir/virtual_sites"
                    echo "$obj_json" > "$ns_backup_dir/virtual_sites/${name}.json"
                    echo "   Backed up Virtual Site: $name"
                    #any_objects=true
                fi
            done
        fi
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
                    #any_objects=true
                fi
            done
        fi
    fi

    # --- Health Checks ---
    hc_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/healthchecks")
    if echo "$hc_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$hc_list" | jq '.items | length')" -gt 0 ]; then
            mkdir -p "$ns_backup_dir/health_checks"
            hc_names=$(echo "$hc_list" | jq -r '.items[].name // empty')
            for name in $hc_names; do
                obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/healthchecks/$name")
                if [[ -n "$obj_json" ]]; then
                    echo "$obj_json" > "$ns_backup_dir/health_checks/${name}.json"
                    echo "   Backed up Health Check: $name"
                    #any_objects=true
                fi
            done
        fi
    fi

    # --- Routes ---
    route_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/routes")
    if echo "$route_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$route_list" | jq '.items | length')" -gt 0 ]; then
            mkdir -p "$ns_backup_dir/routes"
            route_names=$(echo "$route_list" | jq -r "$jqfilter")
            for name in $route_names; do
                obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/routes/$name")
                if [[ -n "$obj_json" ]]; then
                    echo "$obj_json" > "$ns_backup_dir/routes/${name}.json"
                    echo "   Backed up Route: $name"
                    #any_objects=true
                fi
            done
        fi
    fi

    # --- Certificates ---
    cert_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/certificates")
    if echo "$cert_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$cert_list" | jq '.items | length')" -gt 0 ]; then
            cert_names=$(echo "$cert_list" | jq -r "$jqfilter")

            if [ -n "$cert_names" ]; then
                mkdir -p "$ns_backup_dir/certificates"
                for name in $cert_names; do
                    obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/certificates/$name")
                    if [[ -n "$obj_json" ]]; then
                        echo "$obj_json" > "$ns_backup_dir/certificates/${name}.json"
                        echo "   Backed up Certificate: $name"
                        #any_objects=true
                    fi
                done
            fi
        fi
    fi

    # --- Trusted CA  ---
    ca_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/trusted_ca_lists")
    if echo "$ca_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$ca_list" | jq '.items | length')" -gt 0 ]; then
            ca_names=$(echo "$ca_list" | jq -r "$jqfilter")

            if [ -n "$ca_names" ]; then
                mkdir -p "$ns_backup_dir/trusted_ca_lists"
                for name in $ca_names; do
                    obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/trusted_ca_lists/$name")
                    if [[ -n "$obj_json" ]]; then
                        echo "$obj_json" > "$ns_backup_dir/trusted_ca_lists/${name}.json"
                        echo "   Backed up Trusted CA: $name"
                        #any_objects=true
                    fi
                done
            fi
        fi
    fi

    # --- Service Policies ---
    policy_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/service_policys")
    if echo "$policy_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$policy_list" | jq '.items | length')" -gt 0 ]; then

            policy_names=$(echo "$policy_list" | jq -r "$jqfilter")

            if [ -n "$policy_names" ]; then
                mkdir -p "$ns_backup_dir/service_policys"
                for name in $policy_names; do
                    obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/service_policys/$name")
                    if [[ -n "$obj_json" ]]; then
                        echo "$obj_json" > "$ns_backup_dir/service_policys/${name}.json"
                        echo "   Backed up Service Policy: $name"
                        #any_objects=true
                    fi
                done
            fi
        fi
    fi

    # --- Application Firewalls ---
    firewall_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/app_firewalls")
    if echo "$firewall_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$firewall_list" | jq '.items | length')" -gt 0 ]; then

            firewall_names=$(echo "$firewall_list" | jq -r "$jqfilter")

            if [ -n "$firewall_names" ]; then
                mkdir -p "$ns_backup_dir/app_firewalls"
                for name in $firewall_names; do
                    obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/app_firewalls/$name")
                    if [[ -n "$obj_json" ]]; then
                        echo "$obj_json" > "$ns_backup_dir/app_firewalls/${name}.json"
                        echo "   Backed up App Firewall: $name"
                        #any_objects=true
                    fi
                done
            fi
        fi
    fi

    # --- User Identifications ---
    userid_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/user_identifications")
    if echo "$userid_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$userid_list" | jq '.items | length')" -gt 0 ]; then

            userid_names=$(echo "$userid_list" | jq -r "$jqfilter")

            if [ -n "$userid_names" ]; then
                mkdir -p "$ns_backup_dir/user_identifications"
                for name in $userid_names; do
                    obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/user_identifications/$name")
                    if [[ -n "$obj_json" ]]; then
                        echo "$obj_json" > "$ns_backup_dir/user_identifications/${name}.json"
                        echo "   Backed up User Identification: $name"
                        #any_objects=true
                    fi
                done
            fi
        fi
    fi

    # --- App Settings ---
    appsetting_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/app_settings")
    if echo "$appsetting_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$appsetting_list" | jq '.items | length')" -gt 0 ]; then
            appsetting_names=$(echo "$appsetting_list" | jq -r "$jqfilter")

            if [ -n "$appsetting_names" ]; then
                mkdir -p "$ns_backup_dir/app_settings"
                for name in $appsetting_names; do
                    obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/app_settings/$name")
                    if [[ -n "$obj_json" ]]; then
                        echo "$obj_json" > "$ns_backup_dir/app_settings/${name}.json"
                        echo "   Backed up App Settings: $name"
                        #any_objects=true
                    fi
                done
            fi
        fi
    fi

    # --- API Definition ---
    apidef_list=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/api_definitions")
    if echo "$appsetting_list" | jq -e . >/dev/null 2>&1; then
        if [ "$(echo "$apidef_list" | jq '.items | length')" -gt 0 ]; then
            apidef_names=$(echo "$apidef_list" | jq -r "$jqfilter")

            if [ -n "$apidef_names" ]; then
                mkdir -p "$ns_backup_dir/api_definitions"
                for name in $apidef_names; do
                    obj_json=$(send_request "$API_BASE_URL/api/config/namespaces/$namespace/api_definitions/$name")
                    if [[ -n "$obj_json" ]]; then
                        echo "$obj_json" > "$ns_backup_dir/api_definitions/${name}.json"
                        echo "   Backed up API Definition: $name"
                        #any_objects=true
                    fi
                done
            fi
        fi
    fi

    echo "----------------------------------------"
done
