#!/usr/bin/env bash
# tests/lib.sh — shared helpers for the void-fortress test suite.
# Source this from any test script: . "$(dirname "$0")/lib.sh"

set -uo pipefail

# Colors
T_RED='\033[0;31m'
T_GREEN='\033[0;32m'
T_YELLOW='\033[1;33m'
T_CYAN='\033[0;36m'
T_BOLD='\033[1m'
T_NC='\033[0m'

# Counters (per test file, reset on `init_suite`)
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_NAMES=()

# Paths (assume tests/ is sibling of voidnx.sh)
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
SCRIPT_UNDER_TEST="$PROJECT_DIR/voidnx.sh"

init_suite() {
    local name="$1"
    echo
    echo -e "${T_BOLD}${T_CYAN}═══ $name ═══${T_NC}"
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    FAILED_NAMES=()
}

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${T_GREEN}✓${T_NC} $*"
}

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_NAMES+=("$*")
    echo -e "  ${T_RED}✗${T_NC} $*"
}

skip() {
    echo -e "  ${T_YELLOW}~${T_NC} skip: $*"
}

# assert_eq EXPECTED ACTUAL [name]
assert_eq() {
    local expected="$1" actual="$2" name="${3:-assert_eq}"
    if [[ "$expected" == "$actual" ]]; then
        pass "$name"
    else
        fail "$name (expected='$expected', actual='$actual')"
    fi
}

# assert_contains HAYSTACK NEEDLE [name]
assert_contains() {
    local haystack="$1" needle="$2" name="${3:-assert_contains}"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$name"
    else
        fail "$name (needle='$needle' not found)"
    fi
}

# assert_not_contains HAYSTACK NEEDLE [name]
assert_not_contains() {
    local haystack="$1" needle="$2" name="${3:-assert_not_contains}"
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$name"
    else
        fail "$name (needle='$needle' present but should not be)"
    fi
}

# assert_file_exists PATH [name]
assert_file_exists() {
    local path="$1" name="${2:-assert_file_exists $1}"
    if [[ -e "$path" ]]; then
        pass "$name"
    else
        fail "$name (path '$path' missing)"
    fi
}

# assert_cmd_succeeds "command line" [name]
assert_cmd_succeeds() {
    local cmd="$1" name="${2:-assert_cmd_succeeds}"
    if eval "$cmd" >/dev/null 2>&1; then
        pass "$name"
    else
        fail "$name (cmd: $cmd)"
    fi
}

# Print suite summary; exits 1 if any failure.
finish_suite() {
    echo
    if (( TESTS_FAILED == 0 )); then
        echo -e "${T_GREEN}${T_BOLD}PASS${T_NC} — $TESTS_PASSED/$TESTS_RUN"
    else
        echo -e "${T_RED}${T_BOLD}FAIL${T_NC} — $TESTS_FAILED failed, $TESTS_PASSED passed (of $TESTS_RUN)"
        for n in "${FAILED_NAMES[@]}"; do
            echo -e "  ${T_RED}- $n${T_NC}"
        done
        return 1
    fi
}

# Run a function in a subshell so that `set -e` exits and mocks don't leak.
run_in_subshell() {
    ( "$@" )
}

# Create a temporary mock bin dir, prepend to PATH. Returns the dir.
# Use mock_cmd "name" "shell body" inside.
make_mock_bin() {
    local d
    d=$(mktemp -d)
    export PATH="$d:$PATH"
    echo "$d"
}

mock_cmd() {
    local mockdir="$1" name="$2" body="$3"
    cat > "$mockdir/$name" << EOF
#!/usr/bin/env bash
$body
EOF
    chmod +x "$mockdir/$name"
}
