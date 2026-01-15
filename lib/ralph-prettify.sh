#!/bin/bash
# Pretty-print Claude stream-json output for human readability
# Parses JSON events and displays formatted, colorized output

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
DIM='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Icons (using unicode)
ICON_READ="📖"
ICON_EDIT="✏️ "
ICON_WRITE="📝"
ICON_BASH="🖥️ "
ICON_SEARCH="🔍"
ICON_TODO="📋"
ICON_TASK="🤖"
ICON_CHECK="✅"
ICON_WARN="⚠️ "
ICON_ERROR="❌"
ICON_THINK="💭"

# Track state
CURRENT_TOOL=""
IN_TEXT_BLOCK=false

# Format file path - shorten if too long
format_path() {
    local path="$1"
    local max_len=60
    if [ ${#path} -gt $max_len ]; then
        echo "...${path: -$((max_len-3))}"
    else
        echo "$path"
    fi
}

# Format tool input for display
format_tool_input() {
    local tool="$1"
    local input="$2"

    case "$tool" in
        Read)
            local file_path=$(echo "$input" | jq -r '.file_path // empty' 2>/dev/null)
            if [ -n "$file_path" ]; then
                echo -e "${ICON_READ} ${CYAN}Read${NC} $(format_path "$file_path")"
            fi
            ;;
        Edit)
            local file_path=$(echo "$input" | jq -r '.file_path // empty' 2>/dev/null)
            if [ -n "$file_path" ]; then
                echo -e "${ICON_EDIT}${YELLOW}Edit${NC} $(format_path "$file_path")"
            fi
            ;;
        Write)
            local file_path=$(echo "$input" | jq -r '.file_path // empty' 2>/dev/null)
            if [ -n "$file_path" ]; then
                echo -e "${ICON_WRITE} ${GREEN}Write${NC} $(format_path "$file_path")"
            fi
            ;;
        Bash)
            local cmd=$(echo "$input" | jq -r '.command // empty' 2>/dev/null)
            local desc=$(echo "$input" | jq -r '.description // empty' 2>/dev/null)
            if [ -n "$desc" ]; then
                echo -e "${ICON_BASH}${MAGENTA}Bash${NC} $desc"
            elif [ -n "$cmd" ]; then
                # Truncate long commands
                if [ ${#cmd} -gt 80 ]; then
                    cmd="${cmd:0:77}..."
                fi
                echo -e "${ICON_BASH}${MAGENTA}Bash${NC} ${DIM}${cmd}${NC}"
            fi
            ;;
        Grep)
            local pattern=$(echo "$input" | jq -r '.pattern // empty' 2>/dev/null)
            local path=$(echo "$input" | jq -r '.path // "."' 2>/dev/null)
            if [ -n "$pattern" ]; then
                echo -e "${ICON_SEARCH} ${BLUE}Grep${NC} \"$pattern\" in $(format_path "$path")"
            fi
            ;;
        Glob)
            local pattern=$(echo "$input" | jq -r '.pattern // empty' 2>/dev/null)
            if [ -n "$pattern" ]; then
                echo -e "${ICON_SEARCH} ${BLUE}Glob${NC} $pattern"
            fi
            ;;
        TodoWrite)
            local todos=$(echo "$input" | jq -r '.todos // []' 2>/dev/null)
            local in_progress=$(echo "$todos" | jq -r '[.[] | select(.status=="in_progress")] | .[0].content // empty' 2>/dev/null)
            local completed=$(echo "$todos" | jq -r '[.[] | select(.status=="completed")] | length' 2>/dev/null)
            local total=$(echo "$todos" | jq -r 'length' 2>/dev/null)
            if [ -n "$in_progress" ]; then
                echo -e "${ICON_TODO} ${CYAN}Todo${NC} [${completed}/${total}] ${WHITE}${in_progress}${NC}"
            else
                echo -e "${ICON_TODO} ${CYAN}Todo${NC} Updated (${completed}/${total} done)"
            fi
            ;;
        Task)
            local desc=$(echo "$input" | jq -r '.description // empty' 2>/dev/null)
            if [ -n "$desc" ]; then
                echo -e "${ICON_TASK} ${MAGENTA}Task${NC} $desc"
            fi
            ;;
        *)
            # Generic tool display
            echo -e "${DIM}[${tool}]${NC}"
            ;;
    esac
}

# Process each JSON line
while IFS= read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue

    # Try to parse as JSON
    type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
    [ -z "$type" ] && continue

    case "$type" in
        system)
            subtype=$(echo "$line" | jq -r '.subtype // empty' 2>/dev/null)
            if [ "$subtype" = "init" ]; then
                model=$(echo "$line" | jq -r '.model // "unknown"' 2>/dev/null)
                echo -e "${DIM}━━━ Session started (${model}) ━━━${NC}"
            fi
            ;;

        assistant)
            # Process content array
            content=$(echo "$line" | jq -c '.message.content // []' 2>/dev/null)

            # Check for text content
            text=$(echo "$content" | jq -r '.[] | select(.type=="text") | .text // empty' 2>/dev/null)
            if [ -n "$text" ]; then
                # Check for task completion signals
                if echo "$text" | grep -q "<task>COMPLETE</task>"; then
                    echo ""
                    echo -e "${GREEN}${BOLD}${ICON_CHECK} TASK COMPLETE${NC}"
                    echo ""
                elif echo "$text" | grep -q "<task>BLOCKED:"; then
                    blocker=$(echo "$text" | grep -o '<task>BLOCKED:[^<]*</task>' | sed 's/<task>BLOCKED:\(.*\)<\/task>/\1/')
                    echo ""
                    echo -e "${RED}${BOLD}${ICON_ERROR} BLOCKED: ${blocker}${NC}"
                    echo ""
                else
                    # Regular text - print it
                    echo -e "${WHITE}${text}${NC}"
                fi
                echo ""
            fi

            # Check for tool use
            tool_uses=$(echo "$content" | jq -c '.[] | select(.type=="tool_use")' 2>/dev/null)
            if [ -n "$tool_uses" ]; then
                echo "$tool_uses" | while IFS= read -r tool_use; do
                    tool_name=$(echo "$tool_use" | jq -r '.name // empty' 2>/dev/null)
                    tool_input=$(echo "$tool_use" | jq -c '.input // {}' 2>/dev/null)
                    if [ -n "$tool_name" ]; then
                        format_tool_input "$tool_name" "$tool_input"
                    fi
                done
            fi
            ;;

        user)
            # Tool results - we can show success/failure
            tool_result=$(echo "$line" | jq -c '.message.content[]? | select(.type=="tool_result")' 2>/dev/null)
            if [ -n "$tool_result" ]; then
                is_error=$(echo "$tool_result" | jq -r '.is_error // false' 2>/dev/null)
                if [ "$is_error" = "true" ]; then
                    echo -e "  ${RED}${ICON_ERROR} Tool returned error${NC}"
                fi
            fi
            ;;

        result)
            # Final result
            result_text=$(echo "$line" | jq -r '.result // empty' 2>/dev/null)
            cost_usd=$(echo "$line" | jq -r '.cost_usd // empty' 2>/dev/null)
            duration=$(echo "$line" | jq -r '.duration_ms // empty' 2>/dev/null)

            echo ""
            echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

            if [ -n "$cost_usd" ] && [ "$cost_usd" != "null" ]; then
                duration_sec=$(echo "scale=1; $duration / 1000" | bc 2>/dev/null || echo "?")
                echo -e "${DIM}Cost: \$${cost_usd} | Duration: ${duration_sec}s${NC}"
            fi

            if [ -n "$result_text" ]; then
                # Truncate very long results
                if [ ${#result_text} -gt 500 ]; then
                    result_text="${result_text:0:497}..."
                fi
                echo -e "${GREEN}${result_text}${NC}"
            fi
            ;;
    esac
done
