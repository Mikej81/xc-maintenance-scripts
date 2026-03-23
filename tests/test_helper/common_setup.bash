REPO_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
TESTS_DIR="$REPO_DIR/tests"
FIXTURE_DIR="$TESTS_DIR/fixtures"

load "$TESTS_DIR/bats/bats-support/load"
load "$TESTS_DIR/bats/bats-assert/load"

enable_mock_curl() {
    export PATH="$TESTS_DIR/test_helper/bin:$PATH"
    export MOCK_CURL_LOG="$(mktemp)"
    unset MOCK_CURL_RESPONSE MOCK_CURL_HTTP_CODE MOCK_CURL_ROUTES
    unset MOCK_CURL_DEFAULT_RESPONSE MOCK_CURL_DEFAULT_HTTP_CODE MOCK_CURL_FAIL
}

disable_mock_curl() {
    [[ -f "${MOCK_CURL_LOG:-}" ]] && rm -f "$MOCK_CURL_LOG"
}

setup_mock_routes() {
    export MOCK_CURL_ROUTES="$(mktemp)"
    cat > "$MOCK_CURL_ROUTES"
}

assert_curl_called() {
    local pattern="$1"
    grep -q "$pattern" "$MOCK_CURL_LOG"
}

assert_curl_method() {
    local method="$1"
    local pattern="$2"
    grep "^${method}|" "$MOCK_CURL_LOG" | grep -q "$pattern"
}

curl_call_count() {
    local pattern="$1"
    grep -c "$pattern" "$MOCK_CURL_LOG" || echo "0"
}

path_without_jq() {
    local result=""
    local IFS=':'
    for dir in $PATH; do
        [[ -x "$dir/jq" ]] && continue
        result="${result:+$result:}$dir"
    done
    echo "$result"
}

load_integration_env() {
    if [[ -f "$TESTS_DIR/.env.test" ]]; then
        source "$TESTS_DIR/.env.test"
    else
        skip "tests/.env.test not found — skipping integration test"
    fi
    for var in XC_TENANT_NAME XC_API_TOKEN XC_TEST_NAMESPACE; do
        if [[ -z "${!var:-}" ]]; then
            skip "$var not set in tests/.env.test"
        fi
    done
}
