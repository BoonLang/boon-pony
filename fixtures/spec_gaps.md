# Boon-Pony Spec Gaps

This file tracks implementation-contract gaps that are intentionally not hidden by
passing reports.

## Current Boundary

- Phase 0 through Phase 12 gates are implemented and verified.
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
- The Phase 11 playground has a full-screen terminal host path, deterministic
  script/replay verification, terminal-grid projection, and tmux PTY full-tab
  smoke evidence.
- The Phase 12 source workflow supports `tui --example pong`, working-copy
  editing, reload, rebuild, rerun, external-editor handoff, working diff, and
  invalid-edit diagnostics under PTY verification.
- The final command gate in section 21 passes, including the required
  `bench --all --report build/reports/bench.json` matrix with Pong frame,
  Arkanoid frame, Pong input, and Pong protocol roundtrip entries.
- Parser, corpus verification, canonical SOURCE diagnostics, SOURCE source-shape
  extraction, PASS/PASSED accounting, and Flow IR reporting now run in native
  Pony instead of repo-local Node tooling.
- Manifest checking and expected-file contract verification now run in native
  Pony instead of repo-local Node tooling.
- Terminal-grid verification now runs in native Pony instead of repo-local Node
  tooling.

## Implementation Debt

- Terminal snapshot rendering, benchmark orchestration, playground
  orchestration, upstream import, codegen orchestration, direct-play launchers,
  protocol smoke, and PTY smoke verification currently run through repo-local
  Node tooling launched by the Pony CLI.
- The final contract requires implementation code to move into Pony before
  completion is claimed. The generated terminal applications are Pony, but the
  native Pony parser/runtime/compiler/playground stack is not yet complete.
