#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/service_policy_allowlist_update.sh"
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
    run "$SCRIPT" "policy-name"
    assert_failure
    assert_output --partial "Usage:"
}

@test "exits 1 with usage when only 2 arguments provided" {
    run "$SCRIPT" "policy-name" "namespace"
    assert_failure
    assert_output --partial "Usage:"
}

@test "exits 1 with usage when only 3 arguments provided" {
    run "$SCRIPT" "policy-name" "namespace" "tenant"
    assert_failure
    assert_output --partial "Usage:"
}

@test "exits 1 when jq is not installed" {
    PATH="$(path_without_jq)" run "$SCRIPT" "test-policy" "test-ns" "test-tenant" "fake-token"
    assert_failure
    assert_output --partial "jq is required"
}

@test "exits 1 when icanhazip returns empty response" {
    setup_mock_routes <<'ROUTES'
*icanhazip*|200|/dev/null
ROUTES
    run "$SCRIPT" "test-policy" "test-ns" "test-tenant" "fake-token"
    assert_failure
    assert_output --partial "Failed to retrieve public IP"
}

@test "creates new policy when policy does not exist" {
    setup_mock_routes <<ROUTES
*icanhazip*|200|$FIXTURE_DIR/icanhazip_response.txt
*service_policys/test-policy?*|404|$FIXTURE_DIR/error_response.json
*service_policys|200|$FIXTURE_DIR/service_policy_create_success.json
ROUTES
    run "$SCRIPT" "test-policy" "test-ns" "test-tenant" "fake-token"
    assert_success
    assert_output --partial "Creating new policy"
    assert_output --partial "Successfully created"
    assert_curl_method "POST" "service_policys"
}

@test "appends IP to existing policy when not already present" {
    setup_mock_routes <<ROUTES
*icanhazip*|200|$FIXTURE_DIR/icanhazip_response.txt
*service_policys/test-policy?*|200|$FIXTURE_DIR/service_policy_existing.json
*service_policys/test-policy|200|$FIXTURE_DIR/service_policy_replace_success.json
ROUTES
    run "$SCRIPT" "test-policy" "test-ns" "test-tenant" "fake-token"
    assert_success
    assert_output --partial "Successfully updated"
    assert_curl_method "PUT" "service_policys"
}

@test "skips update when IP already in allow list" {
    setup_mock_routes <<ROUTES
*icanhazip*|200|$FIXTURE_DIR/icanhazip_response.txt
*service_policys/test-policy?*|200|$FIXTURE_DIR/service_policy_with_ip.json
ROUTES
    run "$SCRIPT" "test-policy" "test-ns" "test-tenant" "fake-token"
    assert_success
    assert_output --partial "already in the allow list"
}

@test "exits 1 when PUT returns error" {
    setup_mock_routes <<ROUTES
*icanhazip*|200|$FIXTURE_DIR/icanhazip_response.txt
*service_policys/test-policy?*|200|$FIXTURE_DIR/service_policy_existing.json
*service_policys/test-policy|403|$FIXTURE_DIR/error_response.json
ROUTES
    run "$SCRIPT" "test-policy" "test-ns" "test-tenant" "fake-token"
    assert_failure
    assert_output --partial "Error updating"
}
