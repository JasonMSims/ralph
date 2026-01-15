# Ralph

Autonomous task execution orchestrator for Claude.

Ralph breaks down work into discrete tasks defined in a JSON file and orchestrates Claude agent invocations to complete them one by one, maintaining state across iterations.

## Features

- **Task-based execution**: Define tasks in a tasks.json file, Ralph executes them sequentially
- **Fresh agent per iteration**: Each task gets a new Claude instance with full context
- **Real-time visibility**: Stream Claude's work with formatted, colorized output
- **State persistence**: Resume sessions, track progress, maintain audit logs
- **Lock protection**: Prevent concurrent runs
- **Portable**: Works with any project, configurable paths

## Installation

```bash
# Clone the repo
git clone https://github.com/JasonMSims/ralph.git

# Add to your PATH
export PATH="$PATH:$HOME/Code/ralph"

# Or create a symlink
ln -s ~/Code/ralph/ralph /usr/local/bin/ralph
```

## Quick Start

```bash
# Navigate to your project
cd my-project

# Create a tasks.json with your tasks (see format below)

# Initialize ralph
ralph init

# Run iterations
ralph loop 5        # Run 5 iterations
ralph run           # Run single iteration

# Monitor progress
ralph status        # Show progress
ralph watch         # Tail current log
```

## Usage

```
ralph [options] <command> [command-options]

OPTIONS
    --mode <mode>           Execution mode: direct (default) or sandbox
    --permission-mode <m>   Claude permission: acceptEdits (default)
    --task-file <file>      Task file name (default: tasks.json)
    --project-dir <dir>     Project directory (default: current dir)
    --state-dir <dir>       State directory (default: .ralph/)

COMMANDS
    run                 Run a single iteration
    loop [n] [delay]    Run n iterations (default: 10, delay: 5s)
    status              Show current session status
    watch [mode]        Watch logs in real-time (latest/session/all)
    init                Initialize or reset session
    unlock [--force]    Remove lock file
    clean [n|--all]     Clean up old logs (keep n, default: 5)
    help                Show help message
    version             Show version

EXAMPLES
    ralph run                       # Run single iteration
    ralph --mode sandbox run        # Run in sandbox mode
    ralph --task-file my.json run   # Use custom task file
    ralph loop 5                    # Run 5 iterations
    ralph loop 10 10                # Run 10 iterations, 10s delay
    ralph status                    # Check progress
    ralph watch                     # Tail current log
```

## Task File Format (tasks.json)

```json
{
  "name": "My Project Tasks",
  "tasks": [
    {
      "category": "setup",
      "description": "Initialize project structure",
      "steps": [
        "Create src/ directory",
        "Add package.json",
        "Configure TypeScript"
      ],
      "completed": false
    },
    {
      "category": "feature",
      "description": "Implement user authentication",
      "steps": [
        "Create auth module",
        "Add login endpoint",
        "Add tests"
      ],
      "completed": false
    }
  ]
}
```

Tasks are executed in order. When Claude completes a task, it sets `completed: true` and ralph moves to the next incomplete task.

## Configuration

All options can be set via command-line flags or environment variables. Flags take precedence over environment variables.

| Flag | Environment Variable | Default | Description |
|------|---------------------|---------|-------------|
| `--mode` | `RALPH_MODE` | `direct` | Execution mode: `direct` or `sandbox` |
| `--permission-mode` | `RALPH_PERMISSION_MODE` | `acceptEdits` | Claude permission mode |
| `--task-file` | `RALPH_TASK_FILE` | `tasks.json` | Task file name |
| `--project-dir` | `RALPH_PROJECT_DIR` | Current dir | Project directory |
| `--state-dir` | `RALPH_STATE_DIR` | `.ralph/` | State directory |

## State Files

Ralph stores state in `.ralph/` (hidden directory in project root):

```
.ralph/
├── session.json      # Current session state
├── current-task.md   # Current task details
├── ralph.lock        # Lock file
└── logs/             # Iteration logs
    └── 20240115-120000-iter1.log
```

## How It Works

1. **Initialize**: Ralph reads tasks.json and creates a session
2. **Prepare task**: Generates current-task.md with task details
3. **Execute**: Invokes Claude with the task, streaming output
4. **Parse result**: Looks for `<task>COMPLETE</task>` or `<task>BLOCKED:reason</task>`
5. **Update state**: Marks task complete, finds next task
6. **Repeat**: Loop continues until all tasks done or max iterations reached

## Signal Format

Claude signals task completion with:
- `<task>COMPLETE</task>` - Task finished successfully
- `<task>BLOCKED:reason</task>` - Task cannot proceed (stops the loop)

## License

MIT
