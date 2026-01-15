#!/bin/bash
# Run a single ralph iteration with real-time streaming output
# This is the core script that invokes Claude

source "$(dirname "$0")/config.sh"

PREPARE_ONLY=false
SKIP_LOCK=false
if [ "$1" = "--prepare-only" ]; then
    PREPARE_ONLY=true
    SKIP_LOCK=true
fi

# Acquire lock (unless in prepare-only mode or called from loop)
if [ "$SKIP_LOCK" = false ] && [ "$RALPH_LOOP_OWNS_LOCK" != "true" ]; then
    if ! acquire_lock; then
        exit 1
    fi
    setup_lock_trap
fi

ensure_state_dirs

# Initialize session if it doesn't exist
if [ ! -f "${SESSION_FILE}" ]; then
    echo "$(yellow 'No session found, initializing...')"
    "$(dirname "$0")/ralph-init.sh"
    if [ $? -ne 0 ]; then
        exit $?
    fi
fi

# Read current session state
SESSION=$(cat "${SESSION_FILE}")
CURRENT_TASK_INDEX=$(echo "$SESSION" | jq -r '.current_task_index')
ITERATION=$(echo "$SESSION" | jq -r '.iteration')
TOTAL_TASKS=$(echo "$SESSION" | jq -r '.total_tasks')
COMPLETED_TASKS=$(echo "$SESSION" | jq -r '.completed_tasks')

# Check if all tasks are complete
if [ "$CURRENT_TASK_INDEX" = "null" ] || [ -z "$CURRENT_TASK_INDEX" ]; then
    # Re-check PRD for any remaining tasks
    NEXT_TASK_INDEX=$(get_next_incomplete_task_index)
    if [ -z "$NEXT_TASK_INDEX" ]; then
        echo "$(green 'All tasks complete!')"
        exit 2
    fi
    CURRENT_TASK_INDEX=$NEXT_TASK_INDEX
fi

# Get current task details
TASK=$(get_task_by_index "$CURRENT_TASK_INDEX")
TASK_CATEGORY=$(echo "$TASK" | jq -r '.category')
TASK_DESCRIPTION=$(echo "$TASK" | jq -r '.description')
TASK_STEPS=$(echo "$TASK" | jq -r '.steps | to_entries | map("\(.key + 1). \(.value)") | join("\n")')

# Get completed tasks for context
COMPLETED_SUMMARY=$(jq -r '[.testCases | to_entries[] | select(.value.passes == true) | "- \(.value.category): \(.value.description)"] | join("\n")' "${PRD_FILE}")

# Generate current-task.md
cat > "${CURRENT_TASK_FILE}" << EOF
# Current Task

## Task Details
- **Category**: ${TASK_CATEGORY}
- **Description**: ${TASK_DESCRIPTION}
- **Task Index**: $((CURRENT_TASK_INDEX + 1)) of ${TOTAL_TASKS}

## Steps
${TASK_STEPS}

## Context
Previous tasks completed: ${COMPLETED_TASKS}
${COMPLETED_SUMMARY}

## Instructions
- Focus ONLY on this task
- Run tests after implementation (\`bun test\` or \`bunx vitest run\`)
- Run type checks (\`bun run check\`)
- When tests and checks pass, update PRD.json to set this task's \`passes\` field to \`true\`
- Append your progress summary to progress.txt
- Commit your changes with a descriptive message
- Output \`<task>COMPLETE</task>\` when done
- Output \`<task>BLOCKED:reason</task>\` if you cannot proceed
EOF

echo "$(blue 'Current task prepared:')" "[${TASK_CATEGORY}] ${TASK_DESCRIPTION}"

if [ "$PREPARE_ONLY" = true ]; then
    echo "Task file written to: ${CURRENT_TASK_FILE}"
    exit 0
fi

# Update session for this iteration
NEW_ITERATION=$((ITERATION + 1))
update_session_number "iteration" "$NEW_ITERATION"
update_session "last_iteration_at" "$(get_timestamp)"
update_session "current_task_category" "$TASK_CATEGORY"
update_session "current_task_description" "$TASK_DESCRIPTION"
update_session_number "current_task_index" "$CURRENT_TASK_INDEX"

# Create log file for this iteration
LOG_FILE="${LOGS_DIR}/$(date +%Y%m%d-%H%M%S)-iter${NEW_ITERATION}.log"

echo ""
echo "$(blue '=== Starting Iteration')" "${NEW_ITERATION} $(blue '===')"
echo "Task: [${TASK_CATEGORY}] ${TASK_DESCRIPTION}"
echo "Log: ${LOG_FILE}"
echo ""

# Build the prompt
# Use relative paths from project dir so @ references work
PROMPT="@.ralph/current-task.md @PRD.json @CLAUDE.md
Read current-task.md for your specific task assignment.

Your job:
1. Implement the task described in current-task.md
2. Run tests (\`bunx vitest run\`) and type checks (\`bun run check\`)
3. When all tests pass, update PRD.json: set the \`passes\` field to \`true\` for task index ${CURRENT_TASK_INDEX}
4. Append a brief progress summary to progress.txt
5. Commit your changes with a descriptive message

IMPORTANT:
- Focus ONLY on the current task
- Do not work on other tasks
- Output \`<task>COMPLETE</task>\` when finished successfully
- Output \`<task>BLOCKED:reason</task>\` if you encounter an issue you cannot resolve"

# Change to project directory for @ references to work
cd "${PROJECT_DIR}"

# Run Claude with streaming output (no variable capture!)
if [ "$RALPH_MODE" = "sandbox" ]; then
    echo "$(yellow 'Running in sandbox mode...')"
    docker sandbox run claude --permission-mode "${RALPH_PERMISSION_MODE}" --verbose --output-format stream-json -p "$PROMPT" 2>&1 | \
        tee "$LOG_FILE" | \
        "${RALPH_LIB_DIR}/ralph-prettify.sh"
    CLAUDE_EXIT=${PIPESTATUS[0]}
else
    claude --permission-mode "${RALPH_PERMISSION_MODE}" --verbose --output-format stream-json -p "$PROMPT" 2>&1 | \
        tee "$LOG_FILE" | \
        "${RALPH_LIB_DIR}/ralph-prettify.sh"
    CLAUDE_EXIT=${PIPESTATUS[0]}
fi

echo ""
echo "$(blue '=== Iteration')" "${NEW_ITERATION} $(blue 'Complete ===')"

# Parse the result from the log
if grep -q "<task>COMPLETE</task>" "$LOG_FILE"; then
    echo "$(green 'Task completed successfully!')"
    update_session "last_result" "COMPLETE"

    # Update completed count and find next task
    NEW_COMPLETED=$(get_completed_tasks)
    update_session_number "completed_tasks" "$NEW_COMPLETED"

    NEXT_TASK_INDEX=$(get_next_incomplete_task_index)
    if [ -z "$NEXT_TASK_INDEX" ]; then
        echo "$(green 'All tasks complete!')"
        update_session "current_task_index" "null"
        exit 2
    fi

    update_session_number "current_task_index" "$NEXT_TASK_INDEX"
    exit 0

elif grep -q "<task>BLOCKED:" "$LOG_FILE"; then
    BLOCKER=$(grep -o "<task>BLOCKED:[^<]*</task>" "$LOG_FILE" | sed 's/<task>BLOCKED:\(.*\)<\/task>/\1/')
    echo "$(red 'Task blocked:')" "$BLOCKER"
    update_session "last_result" "BLOCKED:${BLOCKER}"

    # Add to blockers array
    jq --arg blocker "$BLOCKER" --arg timestamp "$(get_timestamp)" \
        '.blockers += [{"reason": $blocker, "at": $timestamp}]' \
        "${SESSION_FILE}" > "${SESSION_FILE}.tmp"
    mv "${SESSION_FILE}.tmp" "${SESSION_FILE}"

    exit 3
else
    echo "$(yellow 'Task did not signal completion')"
    update_session "last_result" "UNKNOWN"

    # Check if Claude exited with error
    if [ $CLAUDE_EXIT -ne 0 ]; then
        echo "$(red 'Claude exited with error code:')" "$CLAUDE_EXIT"
        exit 1
    fi

    exit 0
fi
