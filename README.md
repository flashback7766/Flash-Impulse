# Flash-Impulse

A Hyprland desktop built on Quickshell — fork of
[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) (illogical-impulse) merged
with [better-ii-ai](https://github.com/flashback7766/better-ii-ai), heading toward a
**Material 3 Expressive × One UI** design language with a seriously capable AI sidebar.

> Status: working desktop, AI stack integrated. The One UI visual pass and branding are
> still in progress — see [ROADMAP.md](ROADMAP.md).

## Highlights

- **AI sidebar with real function calling** — multi-provider chat (Gemini, OpenAI,
  Anthropic, any local OpenAI-compatible server), streaming, attachments, context
  compression, rotating chat history, cost tracking.
- **Claude Code as a backend** — the `Claude Code · *` models drive the local `claude`
  CLI instead of the HTTP API: your Claude **subscription** powers the sidebar (no API
  key), with Claude Code's own tool suite and permission system. Sessions survive across
  messages via `--resume`.
- **Three-tier command safety** — whitelist / blacklist / Gemini-judge pipeline reviews
  every shell command the AI wants to run; every decision is written to an audit log.
  Explicit `/yolo on` mode for people who like living dangerously.
- **Current model roster** (July 2026): Gemini 3.5 Flash-Lite (default, free tier),
  Gemini 3.6 Flash, Claude Sonnet 5 / Opus 4.8 / Fable 5, GPT-5.6 Luna/Terra/Sol.
- **Real hardware readouts in the bar** — CPU (htop-style per-thread aggregate),
  temperature, frequency, GPU load/temp and system power draw, all read straight from
  sysfs with zero processes spawned on the polling path.
- **Low-end profile** — `performance-mode.sh on` keeps the layout, shapes and colours
  identical while cutting blur passes, dropping window shadows and shortening
  animations, for machines whose GPU is fill-rate starved.
- **Sane installer** — component selection, timestamped backups with one-command
  rollback, migration of your existing configs, API keys in the system keyring.
- **RU layout out of the box** — `us,ru` with Alt+Shift toggle as the shipped default.

## Install

```bash
git clone https://github.com/flashback7766/Flash-Impulse
cd Flash-Impulse
./install.sh
```

Supported: Arch / CachyOS (tested), other pacman-based distros and Fedora (best effort).

Useful subcommands:

```bash
./install.sh doctor              # check distro, deps, claude CLI, stored keys
./install.sh secrets set gemini  # store an API key in the system keyring
./install.sh backups             # list pre-install backups
./install.sh rollback            # restore the latest backup
```

Power users can drive the underlying engine directly via `./setup` (inherited from
upstream, still fully functional).

## AI quick start

Open the left sidebar and just type. Handy commands:

| Command | Effect |
|---|---|
| `/model NAME` | switch model (`Ctrl+1..9` for quick switch) |
| `/key VALUE` | store the API key for the current provider |
| `/tool functions\|search\|none` | select tool mode |
| `/yolo on\|off` | auto-approve **all** AI shell commands (risky) |
| `/new`, `/clear`, `/save`, `/load` | chat management |

For the Claude Code models, install the [claude CLI](https://claude.com/claude-code) and
log in once — `./install.sh doctor` will tell you if anything is missing. Logs live in
`~/.local/share/flash-impulse/logs/`.

Architecture details: [docs/ai-architecture.md](docs/ai-architecture.md).

## Running on older hardware

```bash
~/.config/hypr/hyprland/scripts/performance-mode.sh on     # or off / toggle / status
```

Blur costs roughly `passes × radius × area`, so the profile drops it from 3 passes at
radius 10 to 1 at 4 — still frosted, around an order of magnitude less fill rate. It
also disables window shadows (`render_power 10` is a very soft, very expensive
falloff), shortens every animation to 60% of its duration, and halves the resource
polling rate. Layout, rounding, spacing and colours are untouched.

The setting persists in `~/.config/hypr/custom/variables.lua` as `performanceMode`, so
it survives reloads and updates.

Worth knowing before blaming the shell for GPU load: at idle this desktop draws **0%**
GPU. Spikes come from whatever window is actively repainting (Electron apps are the
usual suspect) and from brief panel animations — not from the bar sitting there.

## Credits & license

- [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) — the illogical-impulse
  desktop this fork stands on. Огромное спасибо.
- [better-ii-ai](https://github.com/flashback7766/better-ii-ai) — the enhanced AI sidebar
  that got merged in.

GPL-3.0, same as upstream. See [LICENSE](LICENSE).
