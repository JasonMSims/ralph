#!/bin/bash
# Initialize a new ralph session
# Creates session.json and prepares first task

source "$(dirname "$0")/config.sh"

echo "$(blue '=== Initializing Ralph Session ===')"

# Ensure state directories exist
ensure_state_dirs

# Check if task file exists
if [ ! -f "${PRD_FILE}" ]; then
    echo "$(red 'Error: Task file not found at')" "${PRD_FILE}"
    exit 1
fi

# Get task counts
TOTAL_TASKS=$(get_total_tasks)
COMPLETED_TASKS=$(get_completed_tasks)
NEXT_TASK_INDEX=$(get_next_incomplete_task_index)

if [ -z "$NEXT_TASK_INDEX" ]; then
    echo "$(green 'All tasks are already complete!')"
    exit 2
fi

NEXT_TASK=$(get_task_by_index "$NEXT_TASK_INDEX")
TASK_CATEGORY=$(echo "$NEXT_TASK" | jq -r '.category')
TASK_DESCRIPTION=$(echo "$NEXT_TASK" | jq -r '.description')

# Create session.json
cat > "${SESSION_FILE}" << EOF
{
  "started_at": "$(get_timestamp)",
  "iteration": 0,
  "current_task_index": ${NEXT_TASK_INDEX},
  "current_task_category": "${TASK_CATEGORY}",
  "current_task_description": "${TASK_DESCRIPTION}",
  "total_tasks": ${TOTAL_TASKS},
  "completed_tasks": ${COMPLETED_TASKS},
  "last_iteration_at": null,
  "last_result": null,
  "blockers": [],
  "failed_attempts": []
}
EOF

echo "Session created:"
echo "  Total tasks: ${TOTAL_TASKS}"
echo "  Completed: ${COMPLETED_TASKS}"
echo "  Next task: [${TASK_CATEGORY}] ${TASK_DESCRIPTION}"
echo ""

# Generate initial current-task.md
"$(dirname "$0")/ralph-run.sh" --prepare-only

echo "$(green 'Session initialized successfully!')"
echo "Run $(blue 'ralph-run.sh') to start the first iteration"
echo "Run $(blue 'ralph-loop.sh <n>') to run n iterations"
