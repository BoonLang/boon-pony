# Boon-Pony Spec Gaps

This file tracks implementation-contract gaps that are intentionally not hidden by
passing reports.

## Current Boundary

- Phase 0 through Phase 10 gates are implemented and verified.
- Phase 4 expected-file verification is an expected-contract runner: it parses
  every checked-in expected file, executes every scripted action into a
  deterministic report, and fails unsupported/malformed actions. It does not
  yet execute generated app runtime state; later terminal/runtime gates must
  provide that evidence.
- Phase 5 terminal verification is headless-grid based.
- Phase 6 raw-input safety is PTY-verified through a tmux harness.
- Phase 7 codegen/runtime/protocol currently covers the counter terminal target.
- Phase 8 terminal canvas smoke currently covers interval and cells.
- Pong and Arkanoid have generated Pony direct/protocol mode, headless terminal
  verification, frame benchmarks, and tmux PTY smoke evidence.
- The full playground, source editing, full final-gate verification, and broad
  benchmark matrix remain later-phase work.

## Implementation Debt

- Parser and source-shape verification currently run through repo-local Node
  tooling launched by the Pony CLI. The final contract requires implementation
  code to move into Pony before completion is claimed.
- Expected-runner, terminal-grid, PTY-smoke, and codegen orchestration are also
  currently repo-local Node tooling launched by the Pony CLI. The generated
  application for Phase 7 is Pony and does not parse Boon at runtime.
