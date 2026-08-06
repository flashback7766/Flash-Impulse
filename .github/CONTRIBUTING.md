# Contributing to Flash-Impulse

## Repo map

| Path | What it is |
|---|---|
| `dots/` | The actual dotfiles deployed to `~` (Hyprland, Quickshell shell, terminals, …) |
| `dots/.config/quickshell/flash-impulse/services/Ai.qml` | AI sidebar orchestrator |
| `dots/.config/quickshell/flash-impulse/services/ai/` | Provider strategies + command safety pipeline |
| `install.sh` | User-facing installer (backup/rollback/secrets/doctor) |
| `setup`, `sdata/` | Lower-level install engine inherited from upstream |
| `docs/` | Architecture docs |
| `ROADMAP.md` | Direction and design decisions — read this first |

## Fork rules

- **Bash** must pass `shellcheck`; **QML** must parse (`qmlformat --check`). CI enforces
  both.
- **AI subsystem changes**: read [docs/ai-architecture.md](../docs/ai-architecture.md)
  first, and update it when you change the architecture.
- **Model IDs / pricing**: never from memory — check the provider's official docs and put
  the date in the commit message.
- **No upstream-sync PRs**: this fork is independent from end-4/dots-hyprland; discuss in
  an issue first if you think something should be pulled in.
- Make multiple PRs if you have many features/fixes; don't shove personal changes
  (including changed defaults) along with a PR.
- Commits: imperative subject, body explains *why*. One logical change per commit.

# Translations

See `dots/.config/quickshell/flash-impulse/translations/tools`

# Code

## Dynamic loading

- If something's not always necessary, especially when guarded by a config option to enable/disable, put it in a `Loader`
  - Note that you will need to declare positioning properties (like `anchors`) in the `Loader`, not the `sourceComponent`
  - When something that's to be dynamically loaded doesn't affect its parent layout, you can have a fading animation by using FadeLoader and set the `shown` prop instead of `active` and `visible`

## Practical concerns

- Make sure what you add does not require significant resources for a minor purpose or harm usability just for the sake of looking nice. The dotfiles must remain practical for daily driving.
- If there is something really fancy and impractical anyway, add a config option for it and make sure it's disabled by default (example: constantly rotating background clock)

## Style

- Spaces
  - Space properties and children data into meaningful groups. (but of course, don't use 2+ blanks in a row)
  - Put spaces between text and operators: `if (condition) { ... } else { ... }` instead of `if(condition){ ... }else{ ... }`
- It's pretty easy to use lots of nesting. There's no hard limit, but avoid/mitigate that:
  - Prefer early return: Use something like `if (!condition) return; doStuff();` instead of `if (condition) { doStuff() }`
  - If you feel it's a bother to refactor something into a new file, remember there's `component` to declare reusable components in the same file.

# Setting up

The following instruction assumes that you have an Arch(-based) Linux system.

## Complete

_Might not be necessary depending on what you change, but this is recommended._

- Install the dotfiles with `./install.sh` (if you don't wanna replace your stuff completely, do it on a new user).
- Make changes, copy changes to a fork, create PR.

## Partially working shell

_Most stuff in the shell will work but not everything._

- Install Hyprland and the development version of Quickshell (`yay -S hyprland quickshell-git`).
- Copy `dots/.config/quickshell` folder to your home directory.

## Extra setup for Quickshell
- Quickshell-specific LSP setup: Run `touch ~/.config/quickshell/flash-impulse/.qmlls.ini` for proper LSP support.
- Hint for VSCode: Get the official "Qt Qml" extension, go to its settings and change custom exe path to `/usr/bin/qmlls6`.

## Python
If your changes involves using python package or script, please use the virtual environment created by uv as described in `sdata/uv/README.md`.

# Running

- Launch Hyprland (not the "uwsm-managed" one)
- For the shell:
  - Open `~/.config/quickshell/flash-impulse` in your code editor.
  - In a terminal run `pkill qs; qs -c flash-impulse` to start the shell in the terminal (for logs).
  - Make edits in the opened folder. Changes are reloaded live.

# Testing the installer

1. `bash -n` / `shellcheck` your shell changes.
2. Run with `--dry-run` first; then on a spare user account verify that
   `install.sh backups` shows a backup and `install.sh rollback` restores it.
