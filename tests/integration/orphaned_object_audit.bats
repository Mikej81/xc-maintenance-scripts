#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    load_integration_env
    SCRIPT="$REPO_DIR/orphaned_object_audit.sh"
}

@test "orphaned_object_audit runs successfully" {
    run "$SCRIPT" "$XC_API_TOKEN" "$XC_TENANT_NAME"
    assert_success
    assert_output --partial "Audit complete"
}

@test "orphaned_object_audit with --type filter runs successfully" {
    run "$SCRIPT" "$XC_API_TOKEN" "$XC_TENANT_NAME" "--type=origin_pool"
    assert_success
    assert_output --partial "Checking origin_pool"
    assert_output --partial "Audit complete"
}
