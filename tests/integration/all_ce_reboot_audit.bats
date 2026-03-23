#!/usr/bin/env bats

setup() {
    load '../test_helper/common_setup'
    load_integration_env
    SCRIPT="$REPO_DIR/all_ce_reboot_audit.sh"
}

@test "all_ce_reboot_audit runs successfully" {
    run "$SCRIPT" "$XC_API_TOKEN" "$XC_TENANT_NAME"
    assert_success
}
