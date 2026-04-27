# Boon-Pony Toolchain

This file is created for Phase 0 of `BOON_PONY_TUI_PLAN.md`.

## Required Tools

- Pony compiler: `ponyc`
- Optional installer/version manager: `ponyup`

## Current Local Probe

On this machine, the Phase 0 probe and install produced:

```text
OS: Pop!_OS 24.04 LTS, Linux x86_64
ponyup: 0.15.4
ponyc: 0.63.3-fa7d7c0 [release]
LLVM: 21.1.8
Clang: 18.1.3-x86_64
ponyup bin dir: /home/martinkavik/.local/share/ponyup/bin
```

For this checkout, use:

```bash
export PATH=/home/martinkavik/.local/share/ponyup/bin:$PATH
```

The compiler was installed with:

```bash
sh -c "$(curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/ponylang/ponyup/latest-release/ponyup-init.sh)"
ponyup update ponyc release
```

## Initial Support Target

- Linux first
- macOS allowed once raw input is verified
- Windows must fail with a clear diagnostic until raw input and ANSI output are implemented

## Terminal Requirements

- UTF-8
- ANSI escape sequences
- alternate screen
- cursor hide/show
- cursor positioning
- SGR attributes
- raw or cbreak input
- resize reporting or polling
