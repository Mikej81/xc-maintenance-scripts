#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/all_ce_sites_update.sh"
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
    assert_output --partial "Error: Failed to fetch valid JSON response from API"
}

@test "exits 1 when API returns invalid JSON" {
    local BAD_JSON
    BAD_JSON="$(mktemp)"
    echo "not valid json" > "$BAD_JSON"
    export MOCK_CURL_RESPONSE="$BAD_JSON"
    run "$SCRIPT" "fake-token" "test-tenant"
    assert_failure
    assert_output --partial "Error: Failed to fetch valid JSON response from API"
    rm -f "$BAD_JSON"
}

@test "produces no output for empty items list" {
    export MOCK_CURL_RESPONSE="$FIXTURE_DIR/empty_items.json"
    run "$SCRIPT" "fake-token" "test-tenant"
    assert_success
    refute_output --partial "Error"
}

@test "calls ce_site_update.sh for each CE site" {
    # Create a sites list with CE-type sites
    local SITES_FIXTURE
    SITES_FIXTURE="$(mktemp)"
    cat > "$SITES_FIXTURE" <<'JSON'
{
  "items": [
    {
      "name": "ce-site-alpha",
      "tenant": "test-tenant",
      "labels": { "ves.io/siteType": "ves-io-ce" }
    },
    {
      "name": "re-site-beta",
      "tenant": "test-tenant",
      "labels": { "ves.io/siteType": "ves-io-re" }
    },
    {
      "name": "ce-site-gamma",
      "tenant": "test-tenant",
      "labels": { "ves.io/siteType": "ves-io-ce" }
    }
  ]
}
JSON

    # Create a stub ce_site_update.sh that just echoes its args
    local STUB_DIR
    STUB_DIR="$(mktemp -d)"
    cat > "$STUB_DIR/ce_site_update.sh" <<'STUB'
#!/bin/bash
echo "STUB_CALLED: site=$1 tenant=$2 token=$3"
STUB
    chmod +x "$STUB_DIR/ce_site_update.sh"

    export MOCK_CURL_RESPONSE="$SITES_FIXTURE"

    # Run from the stub directory so ./ce_site_update.sh resolves to our stub
    cd "$STUB_DIR"
    run "$SCRIPT" "fake-token" "test-tenant"
    assert_success
    assert_output --partial "STUB_CALLED: site=ce-site-alpha tenant=test-tenant token=fake-token"
    assert_output --partial "STUB_CALLED: site=ce-site-gamma tenant=test-tenant token=fake-token"
    refute_output --partial "re-site-beta"

    rm -rf "$STUB_DIR" "$SITES_FIXTURE"
}

@test "constructs correct API URL for site listing" {
    export MOCK_CURL_RESPONSE="$FIXTURE_DIR/empty_items.json"
    run "$SCRIPT" "fake-token" "acme-corp"
    assert_success
    assert_curl_called "acme-corp.console.ves.volterra.io/api/config/namespaces/system/sites"
}
