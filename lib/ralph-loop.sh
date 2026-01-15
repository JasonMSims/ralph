#!/bin/bash
# Main ralph loop orchestrator
# Runs multiple iterations until completion or max iterations reached

source "$(dirname "$0")/config.sh"

MAX_ITERATIONS="${1:-10}"
DELAY_BETWEEN="${2:-5}"

echo "$(blue '=== Ralph Loop Starting ===')"
echo "Max iterations: ${MAX_ITERATIONS}"
echo "Delay between iterations: ${DELAY_BETWEEN}s"
echo "Mode: ${RALPH_MODE}"
echo ""

# Acquire lock for the entire loop
if ! acquire_lock; then
    exit 1
fi
setup_lock_trap

# Export flag so ralph-run.sh knows we own the lock
export RALPH_LOOP_OWNS_LOCK=true

ensure_state_dirs

# Initialize session if needed
if [ ! -f "${SESSION_FILE}" ]; then
    "$(dirname "$0")/ralph-init.sh"
    INIT_EXIT=$?
    if [ $INIT_EXIT -eq 2 ]; then
        echo "$(green 'All tasks already complete!')"
        exit 0
    elif [ $INIT_EXIT -ne 0 ]; then
        echo "$(red 'Failed to initialize session')"
        exit 1
    fi
fi

CONSECUTIVE_FAILURES=0
MAX_CONSECUTIVE_FAILURES=3

for ((i=1; i<=MAX_ITERATIONS; i++)); do
    echo ""
    echo "$(blue '=========================================')"
    echo "$(blue 'Loop Iteration')" "$i" "$(blue 'of')" "${MAX_ITERATIONS}"
    echo "$(blue '=========================================')"
    echo ""

    # Run single iteration
    "$(dirname "$0")/ralph-run.sh"
    EXIT_CODE=$?

    case $EXIT_CODE in
        0)
            echo ""
            echo "$(green 'Task completed, continuing to next...')"
            CONSECUTIVE_FAILURES=0
            ;;
        2)
            echo ""
            echo "$(green '=== All Tasks Complete! ===')"
            echo "Finished after $i iterations"
            exit 0
            ;;
        3)
            echo ""
            echo "$(red 'Task blocked, stopping loop')"
            echo "Check logs and session.json for blocker details"
            echo "Run $(blue 'ralph-status.sh') for current state"
            exit 1
            ;;
        *)
            echo ""
            echo "$(yellow 'Iteration ended with unknown status')"
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))

            if [ $CONSECUTIVE_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]; then
                echo "$(red 'Too many consecutive failures, stopping')"
                exit 1
            fi
            ;;
    esac

    # Don't sleep after last iteration
    if [ $i -lt $MAX_ITERATIONS ]; then
        echo ""
        echo "Waiting ${DELAY_BETWEEN}s before next iteration..."
        sleep "$DELAY_BETWEEN"
    fi
done

echo ""
echo "$(yellow '=== Max Iterations Reached ===')"
echo "Completed $MAX_ITERATIONS iterations"
echo "Run $(blue 'ralph-status.sh') to see progress"
echo "Run $(blue 'ralph-loop.sh <n>') to continue with more iterations"
