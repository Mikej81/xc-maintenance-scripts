#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    enable_mock_curl
    SCRIPT="$REPO_DIR/lb_cert_conversion.sh"
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

@test "exits 1 when --namespace is missing" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant" --lb-name=test-lb
    assert_failure
    assert_output --partial "--namespace= is required"
}

@test "exits 1 when neither --lb-name nor --all is provided" {
    run "$SCRIPT" "fake-key" "test-tenant" --namespace=test-ns
    assert_failure
    assert_output --partial "Either --lb-name=<name> or --all must be provided"
}

@test "exits 1 when both --lb-name and --all are provided" {
    run "$SCRIPT" "fake-key" "test-tenant" --namespace=test-ns --lb-name=my-lb --all
    assert_failure
    assert_output --partial "--lb-name and --all cannot be used together"
}

@test "exits 1 on unknown argument" {
    run "$SCRIPT" "fake-key" "test-tenant" --namespace=test-ns --lb-name=my-lb --bogus
    assert_failure
    assert_output --partial "Unknown argument"
}

# --- jq dependency ---

@test "exits 1 when jq is not installed" {
    PATH="$(path_without_jq)" run "$SCRIPT" "fake-key" "test-tenant" --namespace=test-ns --lb-name=my-lb
    assert_failure
    assert_output --partial "jq is required"
}

# --- Auth validation ---

@test "exits 1 when API token is invalid" {
    export MOCK_CURL_RESPONSE="$FIXTURE_DIR/error_response.json"
    run "$SCRIPT" "bad-key" "test-tenant" --namespace=test-ns --lb-name=my-lb
    assert_failure
    assert_output --partial "API token may be invalid"
}

# --- Dry run mode ---

@test "dry-run shows what would change without executing" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*http_loadbalancers/manual-cert-lb|200|$FIXTURE_DIR/http_loadbalancer_manual_cert.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant" --namespace=test-ns --lb-name=manual-cert-lb --dry-run
    assert_success
    assert_output --partial "[DRY RUN]"
    assert_output --partial "Would convert LB 'manual-cert-lb'"
    assert_output --partial "Mode: DRY RUN"
    # No DELETE calls should be made
    run grep "^DELETE|" "$MOCK_CURL_LOG"
    assert_failure
}

# --- Skips LB already using auto-cert ---

@test "skips LB that does not have manual cert (https key)" {
    AUTO_CERT_LB="$(mktemp)"
    cat > "$AUTO_CERT_LB" <<'EOF'
{"metadata": {"name": "auto-cert-lb", "namespace": "test-ns"}, "spec": {"domains": ["auto.example.com"], "https_auto_cert": {"http_redirect": true, "tls_config": {"default_security": {}}, "no_mtls": {}}}}
EOF
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*http_loadbalancers/auto-cert-lb|200|$AUTO_CERT_LB
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant" --namespace=test-ns --lb-name=auto-cert-lb --dry-run
    assert_success
    assert_output --partial "Skipping: LB 'auto-cert-lb' does not use manual certificate"
    assert_output --partial "Skipped:   1"
    rm -f "$AUTO_CERT_LB"
}

# --- Backup file creation ---

@test "creates backup file in backups directory for manual-cert LB" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*http_loadbalancers/manual-cert-lb|200|$FIXTURE_DIR/http_loadbalancer_manual_cert.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant" --namespace=test-ns --lb-name=manual-cert-lb --dry-run
    assert_success
    [[ -f "$TEST_WORKDIR/backups/test-ns/http_loadbalancers/manual-cert-lb.pre-conversion.json" ]]
}

# --- All mode with empty namespace ---

@test "all mode reports no LBs when namespace is empty" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*http_loadbalancers|200|$FIXTURE_DIR/empty_items.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant" --namespace=test-ns --all --dry-run
    assert_success
    assert_output --partial "No HTTP load balancers found"
}

# --- All mode iterates LBs ---

@test "all mode processes each LB in namespace" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*http_loadbalancers|200|$FIXTURE_DIR/http_loadbalancers_list.json
*http_loadbalancers/manual-cert-lb|200|$FIXTURE_DIR/http_loadbalancer_manual_cert.json
*http_loadbalancers/auto-cert-lb|200|$FIXTURE_DIR/http_loadbalancer_manual_cert.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant" --namespace=test-ns --all --dry-run
    assert_success
    assert_output --partial "Processing LB: manual-cert-lb"
    assert_output --partial "Processing LB: auto-cert-lb"
}

# --- Conversion summary ---

@test "prints conversion summary at the end" {
    setup_mock_routes <<ROUTES
*web/namespaces|200|$FIXTURE_DIR/namespaces_list.json
*http_loadbalancers/manual-cert-lb|200|$FIXTURE_DIR/http_loadbalancer_manual_cert.json
ROUTES
    run "$SCRIPT" "fake-key" "test-tenant" --namespace=test-ns --lb-name=manual-cert-lb --dry-run
    assert_success
    assert_output --partial "Conversion Summary"
    assert_output --partial "Converted: 1"
    assert_output --partial "Skipped:   0"
    assert_output --partial "Failed:    0"
}
