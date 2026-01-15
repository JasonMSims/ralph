#!/bin/bash
# Quick status check for ralph session

source "$(dirname "$0")/config.sh"

echo "$(blue '=== Ralph Session Status ===')"
echo ""

# Lock status
if [ -f "$LOCK_FILE" ]; then
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null | head -1)
    if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "$(yellow 'Lock:') ACTIVE (PID: ${LOCK_PID})"
    else
        echo "$(yellow 'Lock:') STALE (dead process)"
    fi
    echo ""
fi

# Session info
if [ -f "${SESSION_FILE}" ]; then
    echo "$(blue 'Session:')"
    STARTED=$(jq -r '.started_at' "${SESSION_FILE}")
    ITERATION=$(jq -r '.iteration' "${SESSION_FILE}")
    LAST_RUN=$(jq -r '.last_iteration_at // "never"' "${SESSION_FILE}")
    LAST_RESULT=$(jq -r '.last_result // "n/a"' "${SESSION_FILE}")

    echo "  Started: ${STARTED}"
    echo "  Iterations: ${ITERATION}"
    echo "  Last run: ${LAST_RUN}"
    echo "  Last result: ${LAST_RESULT}"
else
    echo "$(yellow 'No active session')"
    echo "Run $(blue 'ralph-init.sh') to start a new session"
fi

echo ""

# PRD Progress
if [ -f "${PRD_FILE}" ]; then
    TOTAL=$(get_total_tasks)
    COMPLETED=$(get_completed_tasks)
    REMAINING=$((TOTAL - COMPLETED))
    PERCENT=$((COMPLETED * 100 / TOTAL))

    echo "$(blue 'PRD Progress:')"
    echo "  Completed: ${COMPLETED}/${TOTAL} (${PERCENT}%)"
    echo "  Remaining: ${REMAINING}"

    # Progress bar
    BAR_WIDTH=40
    FILLED=$((COMPLETED * BAR_WIDTH / TOTAL))
    EMPTY=$((BAR_WIDTH - FILLED))
    printf "  ["
    printf '%*s' "$FILLED" | tr ' ' '='
    printf '%*s' "$EMPTY" | tr ' ' '-'
    printf "]\n"
else
    echo "$(red 'PRD.json not found')"
fi

echo ""

# Current task
if [ -f "${CURRENT_TASK_FILE}" ]; then
    echo "$(blue 'Current Task:')"
    # Extract just the task details section
    sed -n '/^## Task Details/,/^## Steps/p' "${CURRENT_TASK_FILE}" | head -5
else
    echo "$(yellow 'No current task file')"
fi

echo ""

# Blockers
if [ -f "${SESSION_FILE}" ]; then
    BLOCKERS=$(jq -r '.blockers | length' "${SESSION_FILE}")
    if [ "$BLOCKERS" -gt 0 ]; then
        echo "$(red 'Blockers:')"
        jq -r '.blockers[] | "  - \(.at): \(.reason)"' "${SESSION_FILE}"
        echo ""
    fi
fi

# Recent logs
echo "$(blue 'Recent Logs:')"
if [ -d "${LOGS_DIR}" ]; then
    RECENT_LOGS=$(ls -t "${LOGS_DIR}"/*.log 2>/dev/null | head -3)
    if [ -n "$RECENT_LOGS" ]; then
        for log in $RECENT_LOGS; do
            LOG_NAME=$(basename "$log")
            LOG_SIZE=$(wc -c < "$log" | tr -d ' ')
            echo "  ${LOG_NAME} (${LOG_SIZE} bytes)"
        done
    else
        echo "  No logs yet"
    fi
else
    echo "  Logs directory not found"
fi

echo ""

# Recent git commits
echo "$(blue 'Recent Commits:')"
cd "${PROJECT_DIR}"
git log --oneline -5 2>/dev/null || echo "  No git history"

echo ""
echo "$(blue 'Commands:')"
echo "  ralph-run.sh        Run single iteration"
echo "  ralph-loop.sh <n>   Run n iterations"
echo "  ralph-watch.sh      Watch current log"
echo "  ralph-init.sh       Reset session"
