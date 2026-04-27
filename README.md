# Boon-Pony

`boon-pony` is a native Pony implementation and code generation backend for Boon.

The active implementation contract is [BOON_PONY_TUI_PLAN.md](BOON_PONY_TUI_PLAN.md).

Phase 0 bootstrap target:

```bash
ponyc src/boonpony -o build/bin
build/bin/boonpony --help
build/bin/boonpony tui --help
build/bin/boonpony play --help
```

The project is terminal-first. `SOURCE` is the canonical runtime event/input marker; legacy `LINK` is not accepted as canonical runnable syntax.

