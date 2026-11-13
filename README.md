# claude-exit-code

Study project showing how **exit codes** in a Claude Code **Stop hook** control whether Claude can finish its turn. The hook runs `go test` and gates completion on the result.

## Exit codes

| Exit code | Meaning | Effect |
|-----------|---------|--------|
| `0` | Success | Claude stops normally |
| `2` | Blocking error | Claude is **prevented from stopping**; stderr is fed back to it so it can fix the problem |
| `1` (other) | Non-blocking error | User sees a warning; Claude stops anyway |

## Project layout

```
.
├── calc/
│   ├── calc.go                  # Soma() with an intentional bug (a - b)
│   └── calc_test.go             # Test that fails because of the bug
├── main.go
├── go.mod
└── .claude/
    ├── settings.json            # Registers the Stop hook
    └── hooks/
        ├── run-tests.sh         # Basic hook
        └── run-tests-robust.sh  # Hook with retry limit
```

## Hooks

### `run-tests.sh` (basic)

Runs `go test ./...` when Claude tries to stop. On failure it writes the output to stderr and exits with the code set in `HOOK_FAIL_EXIT` (`1` or `2`). Useful for comparing blocking vs. non-blocking behavior.

### `run-tests-robust.sh` (recommended)

Blocks with `exit 2` on failing tests, but only up to `HOOK_MAX_RETRIES` times per turn, avoiding an infinite loop when Claude cannot fix the failure.

- `stop_hook_active=false` in the stdin JSON: new turn, counter reset
- Tests pass: counter cleared, `exit 0`
- Tests fail, attempts `<` max: counter incremented, `exit 2` (Claude goes back to fix)
- Tests fail, attempts `>=` max: gives up, `exit 1` (warns the user, Claude stops)
- Missing dependency (`jq`, `go`): `exit 1`, never blocks
- Counter is stored per `session_id`, so parallel sessions don't interfere

## Configuration

Hook registration in `.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-tests-robust.sh" }
        ]
      }
    ]
  }
}
```

Environment variables:

| Variable | Description |
|----------|-------------|
| `HOOK_FAIL_EXIT` | Enables the hook (any value). Empty or unset means disabled (kill switch) |
| `HOOK_MAX_RETRIES` | Max blocks per turn for the robust hook (default `3`) |

## Try it

Requirements: `go`, `jq`, Claude Code.

```bash
export HOOK_FAIL_EXIT=2
export HOOK_MAX_RETRIES=2
claude
```

Ask Claude to do anything. Since `Soma` returns `a - b`, the test fails and the hook blocks the stop:

1. Attempt 1: tests fail, `exit 2`, Claude is sent back to fix
2. Attempt 2: tests fail, `exit 2`
3. Limit reached: `exit 1`, Claude stops and you are warned

Follow the trace in another terminal:

```bash
tail -f .claude/hooks/hook.log
```

## Takeaway

Hooks turn "please run the tests" into "the agent cannot finish until tests pass". Always cap retries when using `exit 2`, otherwise a failure Claude can't fix traps it in a loop.
