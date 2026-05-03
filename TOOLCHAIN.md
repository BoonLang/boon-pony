# Boon-Pony Toolchain

This file is created for Phase 0 of `BOON_PONY_TUI_PLAN.md`.

## Required Tools

- Pony compiler: `ponyc`
- Optional installer/version manager: `ponyup`
- Shell/build tools for repo-local GUI bootstrap: `bash`, `curl`, `sha256sum`, `tar`, `cmake`, `ninja`, `cc`, and `pkg-config`

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

## Project-Local GUI Dependencies

The native graphical playground addendum keeps project-specific rendering
libraries local to the checkout. Global developer tools such as `ponyc`,
`ponyup`, `tmux`, `git`, `cmake`, `ninja`, `pkg-config`, `cc`, and normal shell
utilities remain normal global prerequisites.

Project-specific GUI artifacts are installed under:

```bash
.boon-local/gui/
```

Tracked dependency pins live in:

```bash
fixtures/gui_dependency_pins.json
```

The bootstrap command is:

```bash
tools/bootstrap_gui_deps.sh
```

It fetches and verifies pinned SDL3, SDL_ttf, GUI fonts, and builds a small C
bridge smoke executable used by `verify-gui --backend sdl3`. The bootstrap
directory is ignored by git and must not be committed.

To run commands with the repo-local GUI environment:

```bash
tools/gui_env.sh build/bin/boonpony verify-gui --all --backend sdl3 --report build/reports/verify-gui-sdl3.json
```

`boonpony gui --doctor` reports which dependency mode is active. By default,
GUI verification uses `.boon-local/gui` and fails clearly when the bootstrap has
not run.

For quick local experiments only, system SDL3 can be explicitly enabled:

```bash
BOON_PONY_USE_SYSTEM_SDL3=1 build/bin/boonpony verify-gui --all --backend sdl3
```

System SDL3 is never used silently. The full native SDL3 window path is not
complete until a real Pony-to-SDL window bridge is built and verified; current
SDL3 verification proves the renderer-neutral scene plus local dependency/C
smoke path.
