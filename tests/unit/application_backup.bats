#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/application_backup.sh"
    TEST_WORKDIR="$(mktemp -d)"
    cd "$TEST_WORKDIR"
}

teardown() {
    disable_mock_curl
    [[ -f "${MOCK_CURL_ROUTES:-}" ]] && rm -f "$MOCK_CURL_ROUTES" || true
    cd "$REPO_DIR"
    rm -rf "$TEST_WORKDIR"
}

# --- Argument validation ---

@test "exits 1 with usage when no arguments provided" {
    run "$SCRIPT"
    assert_failure
    assert_output --partial "Usage:"
}

@test "exits 1 with usage when only 1 argument provided" {
    run "$SCRIPT" "fake-key"
    assert_failure
    assert_output --partial "Usage:"
}

@test "exits 1 with usage when too many arguments provided" {
    run "$SCRIPT" "fake-key" "tenant" "extra"
    assert_failure
    assert_output --partial "Usage:"
}

# --- jq dependency ---

@test "exits 1 when jq is not installed" {
    PATH="$(path_without_jq)" run "$SCRIPT" "fake-key" "test-tenant"
    assert_failure
    assert_output --partial "jq is required"
}

# --- Auth check: empty namespace response ---

@test "exits 1 when namespace response is empty" {
    export MOCK_CURL_RESPONSE="/dev/null"
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_failure
    assert_output --partial "No response received"
}

# --- Processes namespaces excluding system ---

@test "processes non-system namespaces and creates backup directories" {
    HTTP_LB_FIXTURE="$(mktemp)"
    cat > "$HTTP_LB_FIXTURE" <<'EOF'
{"items": [{"name": "my-http-lb", "namespace": "test-ns"}]}
EOF
    HTTP_LB_DETAIL="$(mktemp)"
    cat > "$HTTP_LB_DETAIL" <<'EOF'
{"metadata": {"name": "my-http-lb", "namespace": "test-ns"}, "spec": {"domains": ["app.example.com"]}}
EOF
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*http_loadbalancers/my-http-lb|200|$HTTP_LB_DETAIL
*http_loadbalancers|200|$HTTP_LB_FIXTURE
*cdn_loadbalancers|200|$FIXTURE_DIR/empty_items.json
*tcp_loadbalancers|200|$FIXTURE_DIR/empty_items.json
*proxys|200|$FIXTURE_DIR/empty_items.json
*virtual_sites|200|$FIXTURE_DIR/empty_items.json
*origin_pools|200|$FIXTURE_DIR/empty_items.json
*healthchecks|200|$FIXTURE_DIR/empty_items.json
*routes|200|$FIXTURE_DIR/empty_items.json
*certificates|200|$FIXTURE_DIR/empty_items.json
*trusted_ca_lists|200|$FIXTURE_DIR/empty_items.json
*service_policys|200|$FIXTURE_DIR/empty_items.json
*app_firewalls|200|$FIXTURE_DIR/empty_items.json
*user_identifications|200|$FIXTURE_DIR/empty_items.json
*app_settings|200|$FIXTURE_DIR/empty_items.json
*api_definitions|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Backed up HTTP LB: my-http-lb"
    [[ -f "$TEST_WORKDIR/backups/test-ns/http_loadbalancers/my-http-lb.json" ]]
    rm -f "$HTTP_LB_FIXTURE" "$HTTP_LB_DETAIL"
}

# --- Handles empty namespace (no objects) ---

@test "handles namespace with no objects gracefully" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*cdn_loadbalancers|200|$FIXTURE_DIR/empty_items.json
*http_loadbalancers|200|$FIXTURE_DIR/empty_items.json
*tcp_loadbalancers|200|$FIXTURE_DIR/empty_items.json
*proxys|200|$FIXTURE_DIR/empty_items.json
*virtual_sites|200|$FIXTURE_DIR/empty_items.json
*origin_pools|200|$FIXTURE_DIR/empty_items.json
*healthchecks|200|$FIXTURE_DIR/empty_items.json
*routes|200|$FIXTURE_DIR/empty_items.json
*certificates|200|$FIXTURE_DIR/empty_items.json
*trusted_ca_lists|200|$FIXTURE_DIR/empty_items.json
*service_policys|200|$FIXTURE_DIR/empty_items.json
*app_firewalls|200|$FIXTURE_DIR/empty_items.json
*user_identifications|200|$FIXTURE_DIR/empty_items.json
*app_settings|200|$FIXTURE_DIR/empty_items.json
*api_definitions|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Processing namespace:"
    refute_output --partial "Backed up"
}

# --- Calls correct API base URL ---

@test "uses correct tenant API base URL" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*cdn_loadbalancers|200|$FIXTURE_DIR/empty_items.json
*http_loadbalancers|200|$FIXTURE_DIR/empty_items.json
*tcp_loadbalancers|200|$FIXTURE_DIR/empty_items.json
*proxys|200|$FIXTURE_DIR/empty_items.json
*virtual_sites|200|$FIXTURE_DIR/empty_items.json
*origin_pools|200|$FIXTURE_DIR/empty_items.json
*healthchecks|200|$FIXTURE_DIR/empty_items.json
*routes|200|$FIXTURE_DIR/empty_items.json
*certificates|200|$FIXTURE_DIR/empty_items.json
*trusted_ca_lists|200|$FIXTURE_DIR/empty_items.json
*service_policys|200|$FIXTURE_DIR/empty_items.json
*app_firewalls|200|$FIXTURE_DIR/empty_items.json
*user_identifications|200|$FIXTURE_DIR/empty_items.json
*app_settings|200|$FIXTURE_DIR/empty_items.json
*api_definitions|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_curl_called "test-tenant.console.ves.volterra.io"
}

# --- Backs up multiple resource types ---

@test "backs up CDN and HTTP loadbalancers when both exist" {
    CDN_LB_FIXTURE="$(mktemp)"
    cat > "$CDN_LB_FIXTURE" <<'EOF'
{"items": [{"name": "my-cdn-lb", "namespace": "test-ns"}]}
EOF
    CDN_LB_DETAIL="$(mktemp)"
    cat > "$CDN_LB_DETAIL" <<'EOF'
{"metadata": {"name": "my-cdn-lb", "namespace": "test-ns"}, "spec": {}}
EOF
    HTTP_LB_FIXTURE="$(mktemp)"
    cat > "$HTTP_LB_FIXTURE" <<'EOF'
{"items": [{"name": "my-http-lb", "namespace": "test-ns"}]}
EOF
    HTTP_LB_DETAIL="$(mktemp)"
    cat > "$HTTP_LB_DETAIL" <<'EOF'
{"metadata": {"name": "my-http-lb", "namespace": "test-ns"}, "spec": {}}
EOF
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*cdn_loadbalancers/my-cdn-lb|200|$CDN_LB_DETAIL
*cdn_loadbalancers|200|$CDN_LB_FIXTURE
*http_loadbalancers/my-http-lb|200|$HTTP_LB_DETAIL
*http_loadbalancers|200|$HTTP_LB_FIXTURE
*tcp_loadbalancers|200|$FIXTURE_DIR/empty_items.json
*proxys|200|$FIXTURE_DIR/empty_items.json
*virtual_sites|200|$FIXTURE_DIR/empty_items.json
*origin_pools|200|$FIXTURE_DIR/empty_items.json
*healthchecks|200|$FIXTURE_DIR/empty_items.json
*routes|200|$FIXTURE_DIR/empty_items.json
*certificates|200|$FIXTURE_DIR/empty_items.json
*trusted_ca_lists|200|$FIXTURE_DIR/empty_items.json
*service_policys|200|$FIXTURE_DIR/empty_items.json
*app_firewalls|200|$FIXTURE_DIR/empty_items.json
*user_identifications|200|$FIXTURE_DIR/empty_items.json
*app_settings|200|$FIXTURE_DIR/empty_items.json
*api_definitions|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Backed up CDN LB: my-cdn-lb"
    assert_output --partial "Backed up HTTP LB: my-http-lb"
    [[ -f "$TEST_WORKDIR/backups/test-ns/cdn_loadbalancers/my-cdn-lb.json" ]]
    [[ -f "$TEST_WORKDIR/backups/test-ns/http_loadbalancers/my-http-lb.json" ]]
    rm -f "$CDN_LB_FIXTURE" "$CDN_LB_DETAIL" "$HTTP_LB_FIXTURE" "$HTTP_LB_DETAIL"
}
