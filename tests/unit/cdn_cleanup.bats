#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/cdn_cleanup.sh"
}

teardown() {
    disable_mock_curl
    [[ -f "${MOCK_CURL_ROUTES:-}" ]] && rm -f "$MOCK_CURL_ROUTES" || true
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

# --- Empty namespace response ---

@test "exits 1 when namespace response is empty" {
    export MOCK_CURL_RESPONSE="/dev/null"
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_failure
    assert_output --partial "No response received"
}

# --- No CDN loadbalancers found ---

@test "reports no loadbalancers when namespaces have no CDN LBs" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*cdn_loadbalancers|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "No loadbalancers found"
}

# --- CDN loadbalancers found (delete commented out) ---

@test "finds CDN loadbalancers and prints them without deleting" {
    CDN_LB_FIXTURE="$(mktemp)"
    cat > "$CDN_LB_FIXTURE" <<'EOF'
{"items": [{"name": "cdn-lb-1", "namespace": "test-ns"}]}
EOF
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*cdn_loadbalancers|200|$CDN_LB_FIXTURE
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Found loadbalancer: cdn-lb-1"
    # Since delete is commented out, no DELETE call should be made
    run grep "^DELETE|" "$MOCK_CURL_LOG"
    assert_failure
    rm -f "$CDN_LB_FIXTURE"
}

# --- Iterates all namespaces ---

@test "checks CDN loadbalancers in each namespace from response" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*cdn_loadbalancers|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Checking CDN Loadbalancers for namespace: system"
    assert_output --partial "Checking CDN Loadbalancers for namespace: test-ns"
}
