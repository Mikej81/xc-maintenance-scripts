#!/usr/bin/env bats

TEST_POLICY_NAME="bats-test-allowlist"

setup_file() {
    load '../test_helper/common_setup'
    load_integration_env

    local base_url="https://${XC_TENANT_NAME}.console.ves.volterra.io"
    local api_path="/api/config/namespaces/${XC_TEST_NAMESPACE}/service_policys"

    curl -s -X DELETE \
        -H "Authorization: APIToken ${XC_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${TEST_POLICY_NAME}\", \"namespace\": \"${XC_TEST_NAMESPACE}\"}" \
        "${base_url}${api_path}/${TEST_POLICY_NAME}" > /dev/null 2>&1 || true

    sleep 2
}

setup() {
    load '../test_helper/common_setup'
    load_integration_env
    SCRIPT="$REPO_DIR/service_policy_allowlist_update.sh"
}

teardown_file() {
    load '../test_helper/common_setup'
    load_integration_env

    local base_url="https://${XC_TENANT_NAME}.console.ves.volterra.io"
    local api_path="/api/config/namespaces/${XC_TEST_NAMESPACE}/service_policys"
    curl -s -X DELETE \
        -H "Authorization: APIToken ${XC_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${TEST_POLICY_NAME}\", \"namespace\": \"${XC_TEST_NAMESPACE}\"}" \
        "${base_url}${api_path}/${TEST_POLICY_NAME}" > /dev/null 2>&1 || true
}

# NOTE: BATS runs tests within a file sequentially in order.

@test "creates new service policy with current IP" {
    run "$SCRIPT" "$TEST_POLICY_NAME" "$XC_TEST_NAMESPACE" "$XC_TENANT_NAME" "$XC_API_TOKEN"
    assert_success
    assert_output --partial "Successfully created"
}

@test "reports IP already present on second run (idempotent)" {
    run "$SCRIPT" "$TEST_POLICY_NAME" "$XC_TEST_NAMESPACE" "$XC_TENANT_NAME" "$XC_API_TOKEN"
    assert_success
    assert_output --partial "already in the allow list"
}

@test "policy exists and contains current IP via GET" {
    local base_url="https://${XC_TENANT_NAME}.console.ves.volterra.io"
    local api_path="/api/config/namespaces/${XC_TEST_NAMESPACE}/service_policys/${TEST_POLICY_NAME}"

    local response
    response=$(curl -s -H "Authorization: APIToken ${XC_API_TOKEN}" "${base_url}${api_path}")

    local prefix_count
    prefix_count=$(echo "$response" | jq '.spec.allow_list.prefix_list.prefixes | length')
    [[ "$prefix_count" -ge 1 ]]

    local my_ip
    my_ip=$(curl -s -4 https://ipv4.icanhazip.com | tr -d '[:space:]')
    echo "$response" | jq -r '.spec.allow_list.prefix_list.prefixes[]' | grep -q "${my_ip}/32"
}
