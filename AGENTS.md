# Boon-Pony Agent Instructions

`BOON_PONY_TUI_PLAN.md` is the authoritative implementation contract for this repository.

When changing this repo:

- follow `BOON_PONY_TUI_PLAN.md` phase by phase
- do not treat this file as a replacement for the plan
- keep `SOURCE` canonical and reject legacy `LINK` as described in the plan
- preserve generated/supporting docs as subordinate to the plan
- run the relevant phase acceptance commands before claiming a phase is complete
- do not run git-modifying commands, including `git add`, `git commit`, `git push`, `git reset`, `git checkout`, or equivalent staging/history/remote operations, unless the user explicitly asks for that exact git action
- when launching the native SDL GUI playground manually from an agent session, use `cosmic-background-launch -- ...` or `tools/run_gui_background.sh` so the window opens in the agent/background workspace and does not steal the user's focus
