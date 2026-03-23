#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/api_group_audit.sh"
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
*api_groups|200|/dev/null
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_failure
    assert_output --partial "Empty response from API"
}

@test "produces no group output when items list is empty" {
    setup_mock_routes <<ROUTES
*api_groups|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    refute_output --partial "API Group:"
}

# ---------- core logic ----------

@test "displays API group names from the list" {
    setup_mock_routes <<ROUTES
*api_group_elements/*|200|$FIXTURE_DIR/api_group_element_detail.json
*api_groups/test-api-group|200|$FIXTURE_DIR/api_group_detail.json
*api_groups|200|$FIXTURE_DIR/api_groups_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "API Group: test-api-group"
}

@test "displays tenant/namespace combination for each group" {
    setup_mock_routes <<ROUTES
*api_group_elements/*|200|$FIXTURE_DIR/api_group_element_detail.json
*api_groups/test-api-group|200|$FIXTURE_DIR/api_group_detail.json
*api_groups|200|$FIXTURE_DIR/api_groups_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Tenant/Namespace: test-tenant-system"
}

@test "displays element names from group detail" {
    setup_mock_routes <<ROUTES
*api_group_elements/*|200|$FIXTURE_DIR/api_group_element_detail.json
*api_groups/test-api-group|200|$FIXTURE_DIR/api_group_detail.json
*api_groups|200|$FIXTURE_DIR/api_groups_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Element: test-element-1"
}

@test "displays methods and path regex for each element" {
    setup_mock_routes <<ROUTES
*api_group_elements/*|200|$FIXTURE_DIR/api_group_element_detail.json
*api_groups/test-api-group|200|$FIXTURE_DIR/api_group_detail.json
*api_groups|200|$FIXTURE_DIR/api_groups_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Methods: GET, POST"
    assert_output --partial "Path Regex: /api/v1/.*"
}

@test "prints audit report header with tenant name" {
    setup_mock_routes <<ROUTES
*api_group_elements/*|200|$FIXTURE_DIR/api_group_element_detail.json
*api_groups/test-api-group|200|$FIXTURE_DIR/api_group_detail.json
*api_groups|200|$FIXTURE_DIR/api_groups_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "API Group Audit Report for tenant 'test-tenant'"
}

@test "calls correct API groups endpoint" {
    setup_mock_routes <<ROUTES
*api_group_elements/*|200|$FIXTURE_DIR/api_group_element_detail.json
*api_groups/test-api-group|200|$FIXTURE_DIR/api_group_detail.json
*api_groups|200|$FIXTURE_DIR/api_groups_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_curl_called "test-tenant.console.ves.volterra.io/api/web/namespaces/system/api_groups"
}
