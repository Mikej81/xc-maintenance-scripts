#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/orphaned_object_purge.sh"
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

# --- jq dependency ---

@test "exits 1 when jq is not installed" {
    PATH="$(path_without_jq)" run "$SCRIPT" "fake-key" "test-tenant"
    assert_failure
    assert_output --partial "jq is required"
}

# --- Auth validation ---

@test "exits 1 when API token is invalid" {
    export MOCK_CURL_RESPONSE="$FIXTURE_DIR/error_response.json"
    run "$SCRIPT" "bad-key" "test-tenant"
    assert_failure
    assert_output --partial "API token may be invalid"
}

# --- Skips system and shared namespaces ---

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
    assert_output --partial "Completed orphan cleanup"
    # Should only process test-ns, not system or shared
    assert_output --partial "namespace: test-ns"
    refute_output --partial "Checking for orphaned origin_pool in namespace: system"
    refute_output --partial "Checking for orphaned origin_pool in namespace: shared"
}

# --- Purges orphaned objects with 0 referring_objects ---

@test "purges orphaned object with no referring objects" {
    ORIGIN_POOLS_FIXTURE="$(mktemp)"
    cat > "$ORIGIN_POOLS_FIXTURE" <<'EOF'
{"items": [{"name": "orphan-pool", "namespace": "test-ns"}]}
EOF
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*origin_pools/orphan-pool?*|200|$FIXTURE_DIR/orphaned_object_details_no_refs.json
*origin_pools|200|$ORIGIN_POOLS_FIXTURE
*app_firewalls|200|$FIXTURE_DIR/empty_items.json
*service_policys|200|$FIXTURE_DIR/empty_items.json
*app_settings|200|$FIXTURE_DIR/empty_items.json
*api_definitions|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    assert_output --partial "Purging orphaned origin_pool: orphan-pool"
    assert_curl_method "DELETE" "origin_pools/orphan-pool"
    rm -f "$ORIGIN_POOLS_FIXTURE"
}

# --- Skips objects with referring_objects ---

@test "does not purge object that has referring objects" {
    ORIGIN_POOLS_FIXTURE="$(mktemp)"
    cat > "$ORIGIN_POOLS_FIXTURE" <<'EOF'
{"items": [{"name": "used-pool", "namespace": "test-ns"}]}
EOF
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*origin_pools/used-pool?*|200|$FIXTURE_DIR/orphaned_object_details_with_refs.json
*origin_pools|200|$ORIGIN_POOLS_FIXTURE
*app_firewalls|200|$FIXTURE_DIR/empty_items.json
*service_policys|200|$FIXTURE_DIR/empty_items.json
*app_settings|200|$FIXTURE_DIR/empty_items.json
*api_definitions|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    refute_output --partial "Purging orphaned"
    rm -f "$ORIGIN_POOLS_FIXTURE"
}

# --- Checks all five resource types ---

@test "checks all five resource types for each namespace" {
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
    assert_output --partial "Checking for orphaned origin_pool in namespace: test-ns"
    assert_output --partial "Checking for orphaned app_firewall in namespace: test-ns"
    assert_output --partial "Checking for orphaned service_policy in namespace: test-ns"
    assert_output --partial "Checking for orphaned app_setting in namespace: test-ns"
    assert_output --partial "Checking for orphaned api_definition in namespace: test-ns"
}

# --- Skips items in shared/system namespace ---

@test "skips items whose namespace is shared or system" {
    ORIGIN_POOLS_FIXTURE="$(mktemp)"
    cat > "$ORIGIN_POOLS_FIXTURE" <<'EOF'
{"items": [{"name": "shared-pool", "namespace": "shared"}, {"name": "system-pool", "namespace": "system"}]}
EOF
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*origin_pools|200|$ORIGIN_POOLS_FIXTURE
*app_firewalls|200|$FIXTURE_DIR/empty_items.json
*service_policys|200|$FIXTURE_DIR/empty_items.json
*app_settings|200|$FIXTURE_DIR/empty_items.json
*api_definitions|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant"
    assert_success
    # Should not attempt to fetch details or purge shared/system items
    refute_output --partial "Purging orphaned"
    rm -f "$ORIGIN_POOLS_FIXTURE"
}
