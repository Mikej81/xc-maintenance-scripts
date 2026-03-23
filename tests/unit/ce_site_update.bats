#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/ce_site_update.sh"
}

teardown() {
    disable_mock_curl
    [[ -f "${MOCK_CURL_ROUTES:-}" ]] && rm -f "$MOCK_CURL_ROUTES" || true
}

# --- Missing argument tests ---

@test "exits 1 when no arguments provided" {
    run "$SCRIPT"
    assert_failure
    assert_output --partial "No site-name argument provided"
}

@test "exits 1 when only site-name provided" {
    run "$SCRIPT" "test-site"
    assert_failure
    assert_output --partial "No tenant-name argument provided"
}

@test "exits 1 when only site-name and tenant-name provided" {
    run "$SCRIPT" "test-site" "test-tenant"
    assert_failure
    assert_output --partial "No API Token argument provided"
}

# --- Missing jq test ---

@test "exits 1 when jq is not installed" {
    PATH="$(path_without_jq)" run "$SCRIPT" "test-site" "test-tenant" "fake-token"
    assert_failure
    assert_output --partial "jq is required"
}

# --- Core logic tests ---

@test "reports no updates when OS and SW versions match" {
    local SITE_FIXTURE
    SITE_FIXTURE="$(mktemp)"
    cat > "$SITE_FIXTURE" <<'JSON'
{
  "status": [
    {
      "operating_system_status": {
        "available_version": "7.2024.30",
        "deployment_state": { "version": "7.2024.30" }
      }
    },
    {
      "volterra_software_status": {
        "available_version": "crt-20240930-2456",
        "deployment_state": { "version": "crt-20240930-2456" }
      }
    }
  ]
}
JSON

    setup_mock_routes <<ROUTES
*sites/test-site|200|$SITE_FIXTURE
ROUTES

    run "$SCRIPT" "test-site" "test-tenant" "fake-token"
    assert_success
    assert_output --partial "No OS updates found for site test-site"
    assert_output --partial "No version updates found for site test-site"
    rm -f "$SITE_FIXTURE"
}

@test "triggers OS upgrade when available version differs" {
    local SITE_FIXTURE
    SITE_FIXTURE="$(mktemp)"
    cat > "$SITE_FIXTURE" <<'JSON'
{
  "status": [
    {
      "operating_system_status": {
        "available_version": "7.2024.31",
        "deployment_state": { "version": "7.2024.30" }
      }
    },
    {
      "volterra_software_status": {
        "available_version": "crt-20240930-2456",
        "deployment_state": { "version": "crt-20240930-2456" }
      }
    }
  ]
}
JSON
    local UPGRADE_RESP
    UPGRADE_RESP="$(mktemp)"
    echo '{"status": "ok"}' > "$UPGRADE_RESP"

    setup_mock_routes <<ROUTES
*sites/my-site|200|$SITE_FIXTURE
*upgrade_os|200|$UPGRADE_RESP
ROUTES

    run "$SCRIPT" "my-site" "test-tenant" "fake-token"
    assert_success
    assert_output --partial "OS updates for site my-site"
    assert_output --partial "OS update available: 7.2024.31"
    assert_output --partial "No version updates found for site my-site"
    assert_curl_method "POST" "upgrade_os"
    rm -f "$SITE_FIXTURE" "$UPGRADE_RESP"
}

@test "triggers SW upgrade when available version differs" {
    local SITE_FIXTURE
    SITE_FIXTURE="$(mktemp)"
    cat > "$SITE_FIXTURE" <<'JSON'
{
  "status": [
    {
      "operating_system_status": {
        "available_version": "7.2024.30",
        "deployment_state": { "version": "7.2024.30" }
      }
    },
    {
      "volterra_software_status": {
        "available_version": "crt-20241001-9999",
        "deployment_state": { "version": "crt-20240930-2456" }
      }
    }
  ]
}
JSON
    local UPGRADE_RESP
    UPGRADE_RESP="$(mktemp)"
    echo '{"status": "ok"}' > "$UPGRADE_RESP"

    setup_mock_routes <<ROUTES
*sites/my-site|200|$SITE_FIXTURE
*upgrade_sw|200|$UPGRADE_RESP
ROUTES

    run "$SCRIPT" "my-site" "test-tenant" "fake-token"
    assert_success
    assert_output --partial "No OS updates found for site my-site"
    assert_output --partial "Version updates for site my-site"
    assert_output --partial "Update available: crt-20241001-9999"
    assert_curl_method "POST" "upgrade_sw"
    rm -f "$SITE_FIXTURE" "$UPGRADE_RESP"
}

@test "constructs correct API URL with tenant and site names" {
    local SITE_FIXTURE
    SITE_FIXTURE="$(mktemp)"
    cat > "$SITE_FIXTURE" <<'JSON'
{"status": []}
JSON

    setup_mock_routes <<ROUTES
*|200|$SITE_FIXTURE
ROUTES

    run "$SCRIPT" "my-ce-site" "acme-corp" "fake-token"
    assert_success
    assert_curl_called "acme-corp.console.ves.volterra.io/api/config/namespaces/system/sites/my-ce-site"
    rm -f "$SITE_FIXTURE"
}
