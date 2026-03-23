#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/roles_audit.sh"
}

teardown() {
    disable_mock_curl
    [[ -f "${MOCK_CURL_ROUTES:-}" ]] && rm -f "$MOCK_CURL_ROUTES" || true
}

# ---------- argument validation ----------

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

# ---------- dependency checks ----------

@test "exits 1 when jq is not installed" {
    PATH="$(path_without_jq)" run "$SCRIPT" "fake-key" "test-tenant"
    assert_failure
    assert_output --partial "jq is required"
}

# ---------- empty / error responses ----------

@test "exits 1 when API returns empty response" {
    setup_mock_routes <<'ROUTES'
*roles|200|/dev/null
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_failure
    assert_output --partial "Empty response from API"
}

@test "produces no role output when items list is empty" {
    setup_mock_routes <<ROUTES
*roles|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    refute_output --partial "Role:"
}

# ---------- core logic ----------

@test "displays role names from the roles list" {
    setup_mock_routes <<ROUTES
*roles|200|$FIXTURE_DIR/roles_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Role: admin-role"
}

@test "displays api_groups for each role" {
    setup_mock_routes <<ROUTES
*roles|200|$FIXTURE_DIR/roles_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "API Groups:"
    assert_output --partial "ves-io-api-read"
    assert_output --partial "ves-io-api-write"
}

@test "displays tenant and namespace for each role" {
    setup_mock_routes <<ROUTES
*roles|200|$FIXTURE_DIR/roles_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Tenant: test-tenant"
    assert_output --partial "Namespace: system"
}

@test "prints audit report header with tenant name" {
    setup_mock_routes <<ROUTES
*roles|200|$FIXTURE_DIR/roles_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Roles Audit Report for tenant 'test-tenant'"
}

@test "calls correct roles API endpoint" {
    setup_mock_routes <<ROUTES
*roles|200|$FIXTURE_DIR/roles_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_curl_called "test-tenant.console.ves.volterra.io/api/web/custom/namespaces/system/roles"
}
