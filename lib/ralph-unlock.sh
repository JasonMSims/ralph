#!/bin/bash
# Manually remove ralph lock file
# Use when a lock is stuck after a crash

source "$(dirname "$0")/config.sh"

FORCE=false
if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
    FORCE=true
fi

if [ ! -f "$LOCK_FILE" ]; then
    echo "$(green 'No lock file exists')"
    exit 0
fi

# Read lock info
LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null | head -1)
LOCK_TIME=$(cat "$LOCK_FILE" 2>/dev/null | tail -1)
CURRENT_TIME=$(date +%s)

echo "$(blue '=== Ralph Lock Status ===')"
echo ""

if [ -n "$LOCK_PID" ]; then
    echo "Lock PID: $LOCK_PID"

    if [ -n "$LOCK_TIME" ]; then
        AGE=$((CURRENT_TIME - LOCK_TIME))
        echo "Lock age: ${AGE}s"
    fi

    if kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "Process:  $(green 'RUNNING')"
        echo ""

        if [ "$FORCE" = true ]; then
            echo "$(yellow 'Force removing lock while process is running...')"
            rm -f "$LOCK_FILE"
            echo "$(green 'Lock removed')"
            echo ""
            echo "$(yellow 'Warning: The running process may behave unexpectedly.')"
            echo "Consider killing it: $(blue 'kill '${LOCK_PID})"
        else
            echo "$(red 'Cannot remove lock - process is still running')"
            echo ""
            echo "Options:"
            echo "  1. Wait for the process to finish"
            echo "  2. Kill the process: $(blue 'kill '${LOCK_PID})"
            echo "  3. Force remove:     $(blue './ralph/ralph-unlock.sh --force')"
            exit 1
        fi
    else
        echo "Process:  $(red 'DEAD')"
        echo ""
        echo "$(yellow 'Removing stale lock...')"
        rm -f "$LOCK_FILE"
        echo "$(green 'Lock removed')"
    fi
else
    echo "$(yellow 'Invalid lock file, removing...')"
    rm -f "$LOCK_FILE"
    echo "$(green 'Lock removed')"
fi
