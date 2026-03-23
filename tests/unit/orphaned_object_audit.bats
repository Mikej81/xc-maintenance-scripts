#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/orphaned_object_audit.sh"
}

teardown() {
    disable_mock_curl
    [[ -f "${MOCK_CURL_ROUTES:-}" ]] && rm -f "$MOCK_CURL_ROUTES" || true
    [[ -f "${ORPHAN_ITEMS_FIXTURE:-}" ]] && rm -f "$ORPHAN_ITEMS_FIXTURE" || true
}

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

@test "exits 1 when jq is not installed" {
    PATH="$(path_without_jq)" run "$SCRIPT" "fake-key" "test-tenant"
    assert_failure
    assert_output --partial "jq is required"
}

@test "exits 1 with invalid type" {
    run "$SCRIPT" "fake-key" "test-tenant" --type=bogus_type
    assert_failure
    assert_output --partial "Invalid type"
}

@test "valid type origin_pool only checks that type" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*origin_pools|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant" --type=origin_pool
    assert_success
    assert_output --partial "Checking origin_pool"
    refute_output --partial "Checking app_firewall"
    refute_output --partial "Checking service_policy"
}

@test "full audit with empty items reports no orphaned objects" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*origin_pools|200|$FIXTURE_DIR/empty_items.json
*app_firewalls|200|$FIXTURE_DIR/empty_items.json
*service_policys|200|$FIXTURE_DIR/empty_items.json
*app_settings|200|$FIXTURE_DIR/empty_items.json
*api_definitions|200|$FIXTURE_DIR/empty_items.json
*http_loadbalancers|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "No orphaned objects found"
}

@test "detects orphaned object when referring_objects is empty" {
    ORPHAN_ITEMS_FIXTURE="$(mktemp)"
    echo '{"items": [{"name": "orphan-pool", "namespace": "test-ns"}]}' > "$ORPHAN_ITEMS_FIXTURE"

    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*origin_pools|200|$ORPHAN_ITEMS_FIXTURE
*app_firewalls|200|$FIXTURE_DIR/empty_items.json
*service_policys|200|$FIXTURE_DIR/empty_items.json
*app_settings|200|$FIXTURE_DIR/empty_items.json
*api_definitions|200|$FIXTURE_DIR/empty_items.json
*http_loadbalancers|200|$FIXTURE_DIR/empty_items.json
*response_format=5*|200|$FIXTURE_DIR/orphaned_object_details_no_refs.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "orphan-pool"
    assert_output --partial "Namespace: test-ns"
}

@test "exits 1 when auth check fails" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/error_response.json
ROUTES
    run "$SCRIPT" "bad-key" "test-tenant"
    assert_failure
    assert_output --partial "API token may be invalid"
}
