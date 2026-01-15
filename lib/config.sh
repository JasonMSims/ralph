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

# Task file (default: PRD.json in current directory)
RALPH_TASK_FILE="${RALPH_TASK_FILE:-PRD.json}"

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
    jq '.testCases | length' "${PRD_FILE}"
}

get_completed_tasks() {
    jq '[.testCases[] | select(.passes == true)] | length' "${PRD_FILE}"
}

get_next_incomplete_task_index() {
    jq '.testCases | to_entries | .[] | select(.value.passes != true) | .key' "${PRD_FILE}" | head -1
}

get_task_by_index() {
    local index=$1
    jq ".testCases[$index]" "${PRD_FILE}"
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
