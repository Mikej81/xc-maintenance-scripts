#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/user_audit.sh"
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

@test "table format output includes user audit report header" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*users|200|$FIXTURE_DIR/users_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "User Audit Report"
    assert_output --partial "Tenant: test-tenant"
    assert_output --partial "active@example.com"
    assert_output --partial "inactive@example.com"
    assert_output --partial "disabled@example.com"
    assert_output --partial "Total Users: 3"
}

@test "csv format outputs header row and user data" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*users|200|$FIXTURE_DIR/users_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant" --format=csv
    assert_success
    assert_output --partial "Email,Name,Type,Domain,Last Login,Days Inactive,Roles,Status"
    assert_output --partial "active@example.com"
    assert_output --partial "inactive@example.com"
}

@test "inactive-days filter excludes active user but keeps inactive" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*users|200|$FIXTURE_DIR/users_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant" --inactive-days=30
    assert_success
    refute_output --partial "User: active@example.com"
    assert_output --partial "User: inactive@example.com"
    assert_output --partial "disabled@example.com"
}
