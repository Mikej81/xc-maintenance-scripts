#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/api_cred_cleanup.sh"
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
*api_credentials|200|/dev/null
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_failure
    assert_output --partial "Empty response from API"
}

@test "produces no revoke output when items list is empty" {
    setup_mock_routes <<ROUTES
*api_credentials|200|$FIXTURE_DIR/api_credentials_empty.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    refute_output --partial "Revoking item"
}

# ---------- core logic ----------

@test "revokes expired credentials and skips valid ones" {
    setup_mock_routes <<ROUTES
*revoke/api_credentials|200|$FIXTURE_DIR/empty_items.json
*api_credentials|200|$FIXTURE_DIR/api_credentials_expired.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Revoking item 'expired-cred-1'"
    refute_output --partial "Revoking item 'valid-cred-1'"
}

@test "sends POST to revoke endpoint for expired credentials" {
    setup_mock_routes <<ROUTES
*revoke/api_credentials|200|$FIXTURE_DIR/empty_items.json
*api_credentials|200|$FIXTURE_DIR/api_credentials_expired.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_curl_method "POST" "revoke/api_credentials"
}

@test "includes name and namespace in revoke request output" {
    setup_mock_routes <<ROUTES
*revoke/api_credentials|200|$FIXTURE_DIR/empty_items.json
*api_credentials|200|$FIXTURE_DIR/api_credentials_expired.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "namespace 'system'"
}

@test "calls correct tenant URL for API credentials" {
    setup_mock_routes <<ROUTES
*revoke/api_credentials|200|$FIXTURE_DIR/empty_items.json
*api_credentials|200|$FIXTURE_DIR/api_credentials_expired.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_curl_called "test-tenant.console.ves.volterra.io/api/web/namespaces/system/api_credentials"
}
