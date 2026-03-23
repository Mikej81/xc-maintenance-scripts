#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/old_object_purge.sh"
}

teardown() {
    disable_mock_curl
    [[ -f "${MOCK_CURL_ROUTES:-}" ]] && rm -f "$MOCK_CURL_ROUTES" || true
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

@test "exits 1 when auth check fails" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/error_response.json
ROUTES
    run "$SCRIPT" "bad-key" "test-tenant"
    assert_failure
    assert_output --partial "API token may be invalid"
}

@test "default days is 180 and completes with empty namespaces" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*origin_pools|200|$FIXTURE_DIR/empty_items.json
*app_firewalls|200|$FIXTURE_DIR/empty_items.json
*service_policys|200|$FIXTURE_DIR/empty_items.json
*app_settings|200|$FIXTURE_DIR/empty_items.json
*api_definitions|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Completed cleanup of objects older than 180 days"
}

@test "custom days flag overrides default" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*origin_pools|200|$FIXTURE_DIR/empty_items.json
*app_firewalls|200|$FIXTURE_DIR/empty_items.json
*service_policys|200|$FIXTURE_DIR/empty_items.json
*app_settings|200|$FIXTURE_DIR/empty_items.json
*api_definitions|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant" --days=30
    assert_success
    assert_output --partial "Completed cleanup of objects older than 30 days"
}

@test "skips system and shared namespaces" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*origin_pools|200|$FIXTURE_DIR/empty_items.json
*app_firewalls|200|$FIXTURE_DIR/empty_items.json
*service_policys|200|$FIXTURE_DIR/empty_items.json
*app_settings|200|$FIXTURE_DIR/empty_items.json
*api_definitions|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    refute_output --partial "namespace: system"
    refute_output --partial "namespace: shared"
    assert_output --partial "test-ns"
}
