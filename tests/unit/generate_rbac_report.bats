#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/generate_rbac_report.sh"
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

# --- Report file creation ---

@test "creates markdown report file in current directory" {
    setup_mock_routes <<ROUTES
*roles|200|$FIXTURE_DIR/roles_list.json
*api_groups/ves-io-api-read|200|$FIXTURE_DIR/api_group_detail.json
*api_groups/ves-io-api-write|200|$FIXTURE_DIR/api_group_detail.json
*api_group_elements/*|200|$FIXTURE_DIR/api_group_element_detail.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Markdown RBAC report generated"
    [[ -f "$TEST_WORKDIR/rbac_table_report_test-tenant_page1.md" ]]
}

# --- Report content ---

@test "report contains role name and table headers" {
    setup_mock_routes <<ROUTES
*roles|200|$FIXTURE_DIR/roles_list.json
*api_groups/ves-io-api-read|200|$FIXTURE_DIR/api_group_detail.json
*api_groups/ves-io-api-write|200|$FIXTURE_DIR/api_group_detail.json
*api_group_elements/*|200|$FIXTURE_DIR/api_group_element_detail.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    report="$TEST_WORKDIR/rbac_table_report_test-tenant_page1.md"
    [[ -f "$report" ]]
    run cat "$report"
    assert_output --partial "Role: \`admin-role\`"
    assert_output --partial "| API Group | Element | Method(s) | Path Regex |"
}

# --- Report contains element details ---

@test "report includes API group element methods and path regex" {
    setup_mock_routes <<ROUTES
*roles|200|$FIXTURE_DIR/roles_list.json
*api_groups/ves-io-api-read|200|$FIXTURE_DIR/api_group_detail.json
*api_groups/ves-io-api-write|200|$FIXTURE_DIR/api_group_detail.json
*api_group_elements/*|200|$FIXTURE_DIR/api_group_element_detail.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    report="$TEST_WORKDIR/rbac_table_report_test-tenant_page1.md"
    run cat "$report"
    assert_output --partial "GET, POST"
    assert_output --partial "/api/v1/.*"
}

# --- Fetches roles from correct endpoint ---

@test "calls the roles API endpoint" {
    setup_mock_routes <<ROUTES
*roles|200|$FIXTURE_DIR/roles_list.json
*api_groups/*|200|$FIXTURE_DIR/api_group_detail.json
*api_group_elements/*|200|$FIXTURE_DIR/api_group_element_detail.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_curl_called "custom/namespaces/system/roles"
}

# --- Empty roles list ---

@test "handles empty roles list without error" {
    setup_mock_routes <<ROUTES
*roles|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Markdown RBAC report generated"
}
