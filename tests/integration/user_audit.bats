#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    load_integration_env
    SCRIPT="$REPO_DIR/user_audit.sh"

    # Check if token has access to users API
    local check
    check=$(curl -s -H "Authorization: APIToken ${XC_API_TOKEN}" \
        "https://${XC_TENANT_NAME}.console.ves.volterra.io/api/web/custom/namespaces/system/users")
    if echo "$check" | grep -q "could not be determined"; then
        skip "API token lacks permission for users endpoint"
    fi
}

@test "user_audit runs successfully in table format" {
    run "$SCRIPT" "$XC_API_TOKEN" "$XC_TENANT_NAME"
    assert_success
    assert_output --partial "User Audit Report"
    assert_output --partial "Total Users:"
}

@test "user_audit CSV format produces headers" {
    run "$SCRIPT" "$XC_API_TOKEN" "$XC_TENANT_NAME" "--format=csv"
    assert_success
    assert_output --partial "Email,Name,Type,Domain,Last Login,Days Inactive,Roles,Status"
}
