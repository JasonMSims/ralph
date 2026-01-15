#!/bin/bash
# Configuration for ralph
# Source this file from other ralph scripts

set -e

# ============================================================================
# Configuration (override via environment variables)
# ============================================================================

# Execution mode: "sandbox" or "direct"
RALPH_MODE="${RALPH_MODE:-direct}"

# Permission mode for Claude
RALPH_PERMISSION_MODE="${RALPH_PERMISSION_MODE:-acceptEdits}"

# Task file (default: tasks.json in current directory)
RALPH_TASK_FILE="${RALPH_TASK_FILE:-tasks.json}"

# ============================================================================
# Paths
# ============================================================================

# Where ralph is installed
RALPH_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RALPH_LIB_DIR="${RALPH_BIN_DIR}/lib"

# Project directory (where ralph is being run from)
PROJECT_DIR="${RALPH_PROJECT_DIR:-$(pwd)}"

# State directory (hidden in project root)
STATE_DIR="${RALPH_STATE_DIR:-${PROJECT_DIR}/.ralph}"
LOGS_DIR="${STATE_DIR}/logs"

# State files
SESSION_FILE="${STATE_DIR}/session.json"
CURRENT_TASK_FILE="${STATE_DIR}/current-task.md"

# Project files
PRD_FILE="${PROJECT_DIR}/${RALPH_TASK_FILE}"
PROGRESS_FILE="${PROJECT_DIR}/progress.txt"
CLAUDE_MD="${PROJECT_DIR}/CLAUDE.md"

# Lock file
LOCK_FILE="${STATE_DIR}/ralph.lock"
LOCK_STALE_SECONDS=3600  # Consider lock stale after 1 hour

# ============================================================================
# Helper Functions
# ============================================================================

# Ensure state directories exist
ensure_state_dirs() {
    mkdir -p "${STATE_DIR}"
    mkdir -p "${LOGS_DIR}"
}

# Get current timestamp in ISO format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ============================================================================
# Task File Functions
# ============================================================================

get_total_tasks() {
    jq '.tasks | length' "${PRD_FILE}"
}

get_completed_tasks() {
    jq '[.tasks[] | select(.completed == true)] | length' "${PRD_FILE}"
}

get_next_incomplete_task_index() {
    jq '.tasks | to_entries | .[] | select(.value.completed != true) | .key' "${PRD_FILE}" | head -1
}

get_task_by_index() {
    local index=$1
    jq ".tasks[$index]" "${PRD_FILE}"
}

# ============================================================================
# Session Management
# ============================================================================

update_session() {
    local key=$1
    local value=$2
    local tmp_file="${SESSION_FILE}.tmp"

    if [ -f "${SESSION_FILE}" ]; then
        jq --arg key "$key" --arg value "$value" '.[$key] = $value' "${SESSION_FILE}" > "${tmp_file}"
        mv "${tmp_file}" "${SESSION_FILE}"
    fi
}

update_session_number() {
    local key=$1
    local value=$2
    local tmp_file="${SESSION_FILE}.tmp"

    if [ -f "${SESSION_FILE}" ]; then
        jq --arg key "$key" --argjson value "$value" '.[$key] = $value' "${SESSION_FILE}" > "${tmp_file}"
        mv "${tmp_file}" "${SESSION_FILE}"
    fi
}

# ============================================================================
# Lock Management
# ============================================================================

acquire_lock() {
    ensure_state_dirs

    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null | head -1)
        local lock_time=$(cat "$LOCK_FILE" 2>/dev/null | tail -1)
        local current_time=$(date +%s)

        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            if [ -n "$lock_time" ]; then
                local age=$((current_time - lock_time))
                if [ $age -gt $LOCK_STALE_SECONDS ]; then
                    echo "$(yellow 'Warning: Stale lock detected (running for '${age}'s)')"
                    echo "$(yellow 'Previous process PID:') $lock_pid"
                    echo ""
                    echo "If you're sure no other ralph process is running:"
                    echo "  $(blue 'ralph unlock')"
                    return 1
                fi
            fi
            echo "$(red 'Error: Another ralph process is running (PID: '${lock_pid}')')"
            echo ""
            echo "To check its status: $(blue 'ps -p '${lock_pid})"
            echo "To force unlock:     $(blue 'ralph unlock --force')"
            return 1
        else
            echo "$(yellow 'Removing stale lock from dead process')"
            rm -f "$LOCK_FILE"
        fi
    fi

    echo "$$" > "$LOCK_FILE"
    echo "$(date +%s)" >> "$LOCK_FILE"

    return 0
}

release_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null | head -1)
        if [ "$lock_pid" = "$$" ]; then
            rm -f "$LOCK_FILE"
        fi
    fi
}

setup_lock_trap() {
    trap 'release_lock; exit 130' INT
    trap 'release_lock; exit 143' TERM
    trap 'release_lock' EXIT
}

# ============================================================================
# Color Output
# ============================================================================

red() { echo -e "\033[0;31m$1\033[0m"; }
green() { echo -e "\033[0;32m$1\033[0m"; }
yellow() { echo -e "\033[0;33m$1\033[0m"; }
blue() { echo -e "\033[0;34m$1\033[0m"; }

# ============================================================================
# Test Verification
# ============================================================================

# Check if tests passed in log file
# Returns 0 if tests passed, 1 if tests failed, 2 if no test output found
verify_tests_passed() {
    local log_file="$1"

    # Check for common test failure patterns
    # Vitest/Jest failures
    if grep -qE "(FAIL|Failed|failed)\s+.*\.(test|spec)\.(ts|js|tsx|jsx)" "$log_file" 2>/dev/null; then
        return 1
    fi

    # Vitest summary showing failures
    if grep -qE "Tests?\s+[0-9]+\s+failed" "$log_file" 2>/dev/null; then
        return 1
    fi

    # Jest/Vitest red X failures
    if grep -qE "✗|✕|×" "$log_file" 2>/dev/null && grep -qE "(test|spec|describe|it)\(" "$log_file" 2>/dev/null; then
        return 1
    fi

    # Check for test success patterns
    # Vitest/Jest success
    if grep -qE "(PASS|passed|✓|✔)" "$log_file" 2>/dev/null && grep -qE "(test|spec)" "$log_file" 2>/dev/null; then
        return 0
    fi

    # Vitest "All tests passed" or similar
    if grep -qiE "(all.*tests.*pass|tests.*passed|test.*pass)" "$log_file" 2>/dev/null; then
        return 0
    fi

    # No test output detected
    return 2
}

# Check if type checks passed in log file
# Returns 0 if passed, 1 if failed, 2 if no type check output found
verify_typecheck_passed() {
    local log_file="$1"

    # TypeScript errors
    if grep -qE "error TS[0-9]+:" "$log_file" 2>/dev/null; then
        return 1
    fi

    # tsc errors
    if grep -qE "Found [1-9][0-9]* errors?" "$log_file" 2>/dev/null; then
        return 1
    fi

    # Bun type check failures
    if grep -qE "type.*(error|Error)" "$log_file" 2>/dev/null; then
        return 1
    fi

    # Check for success patterns
    if grep -qiE "(no.*errors|0 errors|type.*check.*pass|tsc.*success)" "$log_file" 2>/dev/null; then
        return 0
    fi

    # No type check output detected
    return 2
}

# Comprehensive build verification
# Returns 0 if all checks pass, 1 if any check fails
verify_build_passed() {
    local log_file="$1"
    local strict="${2:-false}"

    local test_result
    local typecheck_result

    verify_tests_passed "$log_file"
    test_result=$?

    verify_typecheck_passed "$log_file"
    typecheck_result=$?

    # If tests explicitly failed, reject
    if [ $test_result -eq 1 ]; then
        echo "tests_failed"
        return 1
    fi

    # If type check explicitly failed, reject
    if [ $typecheck_result -eq 1 ]; then
        echo "typecheck_failed"
        return 1
    fi

    # In strict mode, require evidence of passing (not just absence of failure)
    if [ "$strict" = "true" ]; then
        if [ $test_result -eq 2 ] && [ $typecheck_result -eq 2 ]; then
            echo "no_verification_found"
            return 1
        fi
    fi

    echo "passed"
    return 0
}
