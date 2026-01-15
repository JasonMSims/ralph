#!/bin/bash
# Watch ralph logs in real-time

source "$(dirname "$0")/config.sh"

MODE="${1:-latest}"

case "$MODE" in
    latest)
        # Watch the latest log file
        if [ ! -d "${LOGS_DIR}" ]; then
            echo "$(yellow 'Logs directory not found. Waiting for first log...')"
            mkdir -p "${LOGS_DIR}"
        fi

        LATEST_LOG=$(ls -t "${LOGS_DIR}"/*.log 2>/dev/null | head -1)

        if [ -n "$LATEST_LOG" ]; then
            echo "$(blue 'Watching:')" "$LATEST_LOG"
            echo "$(yellow 'Press Ctrl+C to stop')"
            echo ""
            tail -f "$LATEST_LOG"
        else
            echo "$(yellow 'No logs found. Watching for new logs...')"
            echo "$(yellow 'Press Ctrl+C to stop')"

            # Watch for new log files using a simple polling approach
            while true; do
                LATEST_LOG=$(ls -t "${LOGS_DIR}"/*.log 2>/dev/null | head -1)
                if [ -n "$LATEST_LOG" ]; then
                    echo ""
                    echo "$(green 'New log found:')" "$LATEST_LOG"
                    echo ""
                    tail -f "$LATEST_LOG"
                    break
                fi
                sleep 1
            done
        fi
        ;;

    all)
        # Watch all log files as they appear
        echo "$(blue 'Watching all logs in:')" "${LOGS_DIR}"
        echo "$(yellow 'Press Ctrl+C to stop')"
        echo ""

        # Use tail on all existing logs with -F to follow new files
        if command -v multitail &> /dev/null; then
            multitail "${LOGS_DIR}"/*.log 2>/dev/null || tail -f "${LOGS_DIR}"/*.log 2>/dev/null
        else
            # Fallback to watching latest only
            tail -F "${LOGS_DIR}"/*.log 2>/dev/null || \
                echo "$(yellow 'No logs yet. Run ralph-run.sh to create logs.')"
        fi
        ;;

    session)
        # Watch session.json for changes
        echo "$(blue 'Watching session state...')"
        echo "$(yellow 'Press Ctrl+C to stop')"
        echo ""

        if [ -f "${SESSION_FILE}" ]; then
            cat "${SESSION_FILE}" | jq '.'
            echo ""

            # Use fswatch if available, otherwise poll
            if command -v fswatch &> /dev/null; then
                fswatch -o "${SESSION_FILE}" | while read; do
                    clear
                    echo "$(blue 'Session updated at')" "$(date)"
                    echo ""
                    cat "${SESSION_FILE}" | jq '.'
                done
            else
                LAST_MTIME=""
                while true; do
                    CURRENT_MTIME=$(stat -f %m "${SESSION_FILE}" 2>/dev/null || stat -c %Y "${SESSION_FILE}" 2>/dev/null)
                    if [ "$CURRENT_MTIME" != "$LAST_MTIME" ]; then
                        clear
                        echo "$(blue 'Session updated at')" "$(date)"
                        echo ""
                        cat "${SESSION_FILE}" | jq '.'
                        LAST_MTIME="$CURRENT_MTIME"
                    fi
                    sleep 1
                done
            fi
        else
            echo "$(yellow 'No session file. Run ralph-init.sh first.')"
        fi
        ;;

    *)
        echo "Usage: ralph-watch.sh [latest|all|session]"
        echo ""
        echo "Modes:"
        echo "  latest   Watch the most recent log file (default)"
        echo "  all      Watch all log files"
        echo "  session  Watch session.json for state changes"
        ;;
esac
