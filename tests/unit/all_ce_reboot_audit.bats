#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/all_ce_reboot_audit.sh"
}

teardown() {
    disable_mock_curl
    [[ -f "${MOCK_CURL_ROUTES:-}" ]] && rm -f "$MOCK_CURL_ROUTES" || true
}

# --- Missing argument tests ---

@test "exits 1 when no arguments provided" {
    run "$SCRIPT"
    assert_failure
    assert_output --partial "Usage:"
}

@test "exits 1 when only 1 argument provided" {
    run "$SCRIPT" "fake-token"
    assert_failure
    assert_output --partial "Usage:"
}

# --- Missing jq test ---

@test "exits 1 when jq is not installed" {
    PATH="$(path_without_jq)" run "$SCRIPT" "fake-token" "test-tenant"
    assert_failure
    assert_output --partial "jq is required"
}

# --- Core logic tests ---

@test "exits 1 when API returns empty response" {
    export MOCK_CURL_RESPONSE="/dev/null"
    run "$SCRIPT" "fake-token" "test-tenant"
    assert_failure
    assert_output --partial "Error: Failed to fetch valid site list"
}

@test "exits 1 when API returns invalid JSON" {
    local BAD_JSON
    BAD_JSON="$(mktemp)"
    echo "this is not json" > "$BAD_JSON"
    export MOCK_CURL_RESPONSE="$BAD_JSON"
    run "$SCRIPT" "fake-token" "test-tenant"
    assert_failure
    assert_output --partial "Error: Failed to fetch valid site list"
    rm -f "$BAD_JSON"
}

@test "prints header and produces no site output with empty items" {
    export MOCK_CURL_RESPONSE="$FIXTURE_DIR/empty_items.json"
    run "$SCRIPT" "fake-token" "test-tenant"
    assert_success
    assert_output --partial "Site Reboot Summary"
    assert_output --partial "===================="
    refute_output --partial "Error"
}

@test "processes online CE site and displays reboot info" {
    local SITES_FIXTURE
    SITES_FIXTURE="$(mktemp)"
    cat > "$SITES_FIXTURE" <<'JSON'
{
  "items": [
    {
      "name": "ce-prod-01",
      "tenant": "test-tenant",
      "labels": { "ves.io/siteType": "ves-io-ce" },
      "get_spec": { "site_state": "ONLINE" }
    }
  ]
}
JSON

    local DETAIL_FIXTURE
    DETAIL_FIXTURE="$(mktemp)"
    cat > "$DETAIL_FIXTURE" <<'JSON'
{
  "spec": {
    "main_nodes": [
      { "name": "node-1" }
    ]
  }
}
JSON

    local EXEC_FIXTURE
    EXEC_FIXTURE="$(mktemp)"
    cat > "$EXEC_FIXTURE" <<'JSON'
{
  "output": " 0 abcdef1234 Thu 2025-01-15 08:00:00 UTC—Thu 2025-01-16 10:30:00 UTC\n-1 abcdef5678 Wed 2025-01-14 06:00:00 UTC—Thu 2025-01-15 07:59:59 UTC"
}
JSON

    setup_mock_routes <<ROUTES
*exec-user|200|$EXEC_FIXTURE
*system/sites/ce-prod-01|200|$DETAIL_FIXTURE
*report_fields*|200|$SITES_FIXTURE
ROUTES

    run "$SCRIPT" "fake-token" "test-tenant"
    assert_success
    assert_output --partial "Site Reboot Summary"
    assert_output --partial "Site: ce-prod-01"
    assert_output --partial "node-1:"
    rm -f "$SITES_FIXTURE" "$DETAIL_FIXTURE" "$EXEC_FIXTURE"
}

@test "skips non-CE and offline sites" {
    local SITES_FIXTURE
    SITES_FIXTURE="$(mktemp)"
    cat > "$SITES_FIXTURE" <<'JSON'
{
  "items": [
    {
      "name": "re-site-01",
      "tenant": "test-tenant",
      "labels": { "ves.io/siteType": "ves-io-re" },
      "get_spec": { "site_state": "ONLINE" }
    },
    {
      "name": "ce-offline-01",
      "tenant": "test-tenant",
      "labels": { "ves.io/siteType": "ves-io-ce" },
      "get_spec": { "site_state": "OFFLINE" }
    }
  ]
}
JSON

    export MOCK_CURL_RESPONSE="$SITES_FIXTURE"
    run "$SCRIPT" "fake-token" "test-tenant"
    assert_success
    assert_output --partial "Site Reboot Summary"
    refute_output --partial "re-site-01"
    refute_output --partial "ce-offline-01"
    rm -f "$SITES_FIXTURE"
}

@test "warns when site detail has no main_nodes" {
    local SITES_FIXTURE
    SITES_FIXTURE="$(mktemp)"
    cat > "$SITES_FIXTURE" <<'JSON'
{
  "items": [
    {
      "name": "ce-empty-nodes",
      "tenant": "test-tenant",
      "labels": { "ves.io/siteType": "ves-io-ce" },
      "get_spec": { "site_state": "ONLINE" }
    }
  ]
}
JSON

    local DETAIL_FIXTURE
    DETAIL_FIXTURE="$(mktemp)"
    cat > "$DETAIL_FIXTURE" <<'JSON'
{
  "spec": {
    "main_nodes": []
  }
}
JSON

    setup_mock_routes <<ROUTES
*system/sites/ce-empty-nodes|200|$DETAIL_FIXTURE
*report_fields*|200|$SITES_FIXTURE
ROUTES

    run "$SCRIPT" "fake-token" "test-tenant"
    assert_success
    assert_output --partial "Warning: No main_nodes found"
    rm -f "$SITES_FIXTURE" "$DETAIL_FIXTURE"
}

@test "constructs correct API URL for site listing" {
    export MOCK_CURL_RESPONSE="$FIXTURE_DIR/empty_items.json"
    run "$SCRIPT" "fake-token" "acme-corp"
    assert_success
    assert_curl_called "acme-corp.console.ves.volterra.io"
}
