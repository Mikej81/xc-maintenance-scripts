#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BATS_DIR="$SCRIPT_DIR/bats"
BATS_BIN="$BATS_DIR/bats-core/bin/bats"

MODE="unit"
for arg in "$@"; do
    case "$arg" in
        --unit) MODE="unit" ;;
        --integration) MODE="integration" ;;
        --all) MODE="all" ;;
        *) echo "Usage: $0 [--unit|--integration|--all]"; exit 1 ;;
    esac
done

if [[ ! -x "$BATS_BIN" ]]; then
    echo "Installing BATS test framework..."
    mkdir -p "$BATS_DIR"
    git clone --depth 1 --branch v1.11.1 https://github.com/bats-core/bats-core.git "$BATS_DIR/bats-core"
    git clone --depth 1 --branch v0.3.0 https://github.com/bats-core/bats-support.git "$BATS_DIR/bats-support"
    git clone --depth 1 --branch v2.1.0 https://github.com/bats-core/bats-assert.git "$BATS_DIR/bats-assert"
    echo "BATS installed."
fi

run_unit() {
    echo ""
    echo "========== Running Unit Tests =========="
    "$BATS_BIN" "$SCRIPT_DIR/unit/"*.bats
}

run_integration() {
    if [[ ! -f "$SCRIPT_DIR/.env.test" ]]; then
        echo "Error: tests/.env.test not found."
        echo "Copy tests/.env.test.example to tests/.env.test and fill in your credentials."
        exit 1
    fi
    source "$SCRIPT_DIR/.env.test"
    for var in XC_TENANT_NAME XC_API_TOKEN XC_TEST_NAMESPACE; do
        if [[ -z "${!var:-}" ]]; then
            echo "Error: $var is not set in tests/.env.test"
            exit 1
        fi
    done
    echo ""
    echo "========== Running Integration Tests =========="
    echo "Tenant: $XC_TENANT_NAME | Namespace: $XC_TEST_NAMESPACE"
    "$BATS_BIN" "$SCRIPT_DIR/integration/"*.bats
}

case "$MODE" in
    unit) run_unit ;;
    integration) run_integration ;;
    all) run_unit; run_integration ;;
esac

echo ""
echo "========== Done =========="
