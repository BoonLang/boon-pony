# Boon-Pony Spec Gaps

This file tracks implementation-contract gaps that are intentionally not hidden by
passing reports.

## Current Boundary

- Phase 0 through Phase 3 gates are implemented and verified.
- Phase 4 is the next incomplete gate: expected-file execution and action
  semantics are not implemented yet.
- Terminal backend, generated runtime, protocol mode, games, playground, live
  PTY proof, and benchmarks remain later-phase work.

## Implementation Debt

- Parser and source-shape verification currently run through repo-local Node
  tooling launched by the Pony CLI. The final contract requires implementation
  code to move into Pony before completion is claimed.
