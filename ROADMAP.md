# Flash-Impulse — Roadmap

Fork of [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) (Illogical Impulse),
merged with [flashback7766/better-ii-ai](https://github.com/flashback7766/better-ii-ai),
redesigned around a One UI 8.5/9-inspired visual language, with a rewritten installer and a
Claude Code-backed AI sidebar.

Status: **planning complete, implementation not started.** This document is the source of
truth from the requirements session on 2026-07-24. Next step for whoever picks this up:
read this fully before writing any code — it resolves most "how should this work" questions
already.

## 0. Identity

- **Name:** Flash-Impulse
- **Repo:** `flashback7766/flash-impulse` on GitHub — not yet created (gh CLI not
  authenticated on this machine as of 2026-07-24). Create with `gh repo create
  flashback7766/flash-impulse --public --source=. --remote=origin` once authenticated, or
  swap in whatever URL is already reserved.
- **License:** GPL-3.0, inherited from end-4/dots-hyprland (copyleft — required for a fork).
- **Git history:** squash end-4/dots-hyprland + better-ii-ai into a single initial commit
  for flash-impulse. No upstream-tracking remote — this fork is independent, no auto-sync
  with end-4 planned.
- **Branding:** logo + "Flash-Impulse" name shown in UI and an About panel. Default
  wallpapers: source/curate existing abstract One-UI-style wallpapers and bundle them in
  the repo (no runtime AI generation of wallpapers).

## 1. Base merge (dots-hyprland + better-ii-ai)

- better-ii-ai's QML files are merged directly into the dots-hyprland tree (drop-in
  replacement over the stock `ii/modules/ai` sidebar), the same way its current
  `install.sh` already does it — just make this the permanent state of the repo instead of
  a post-install step.
- Current personal `custom/*.lua` overrides (incl. the Russian keyboard layout added
  earlier this session — see `custom/general.lua`) become the **default** config shipped
  in the fork.

## 2. Installer rewrite

- Language: **Bash**, but clean and modular (proper structure, logging, flags) — not a
  rewrite into Python/Fish.
- Target distros: Arch/CachyOS (primary, actually tested), Fedora, and ZereneOS/Xenovia2
  (Arch-based, pacman — treat like Arch). Ubuntu/openSUSE not required. Only Arch/CachyOS
  will be hand-tested; other distro codepaths are written from package docs, best-effort,
  not verified live.
- **Selective install**: modular, user-friendly CLI — user can pick components (AI
  sidebar only, theme only, full install, etc.), not just an all-or-nothing script.
- **Migration handling**: if an existing end-4/dots-hyprland (or old flash-impulse)
  install is detected in `~/.config/hypr`, **ask interactively** whether to migrate
  `custom/*` (preserving personal tweaks) or start clean.
- **Backup/rollback**: mandatory. Every install run backs up whatever it's about to
  overwrite under a timestamped directory, and there's a `install.sh rollback` (or
  subcommand) to restore the most recent backup.
- **Secrets**: API keys (Anthropic/OpenAI/Gemini) stored via system keyring (Secret
  Service / libsecret), not plaintext JSON like the current better-ii-ai config.

## 3. AI sidebar architecture

### 3.1 Providers or the model roster

- Google, OpenAI, Anthropic, local/OpenAI-compatible — same provider set as
  better-ii-ai today.
- **Model list must not be hardcoded from memory/README** (the current better-ii-ai
  README already has stale/fictional model names). Before writing provider code:
  - For Anthropic: model list is sourced from Claude Code CLI itself (since Anthropic
    routes through it — see 3.2), not hardcoded.
  - For Gemini/OpenAI: pull current model IDs from each provider's docs/API at
    implementation time, don't trust old README text.
- **Default model: Gemini Flash-Lite** (generous free tier) for a fresh install with no
  keys configured yet.

### 3.2 Anthropic via Claude Code CLI (the big architectural change)

- Anthropic models (Claude) are **not called via raw Anthropic API by default**. Instead,
  the sidebar shells out to the `claude` CLI (Claude Code) as the backend, so the user can
  use their **Claude subscription** instead of burning API credits, and so tool execution
  goes through Claude Code's own (well-audited) permission system.
- Chosen approach for the CLI integration: **whichever the implementer judges best** —
  the user explicitly deferred this to "you pick", but the two live options on the table
  from this session are:
  1. `claude --output-format stream-json` + a custom permission-prompt tool/hook (the
     officially supported mechanism for external integrations).
  2. A small MCP server acting as the permission-prompt instrument, forwarding
     approve/deny prompts into QML.
  Whichever is picked, it must support **multi-turn context** (there's no reason to
  spawn a stateless process per message) — investigate `--resume`/session IDs.
- **Fallback path**: still keep a direct Anthropic API-key path as an alternative for
  users without a Claude subscription. Claude Code is the default; API key is the
  alternative, not removed.
- **Model roster for Claude**: Haiku, Sonnet, Opus, and **Fable** (not yet in
  better-ii-ai — add it). Pull actual current model IDs from Claude Code / API at
  implementation time (as of this session: `claude-opus-4-8`, `claude-sonnet-5`,
  `claude-haiku-4-5-20251001`, `claude-fable-5` — verify these are still current before
  hardcoding).

### 3.3 In-chat interactive question blocks (AskUserQuestion-equivalent)

- The sidebar needs a chat-native "ask the user a multiple-choice question with buttons"
  UI block — the same UX as the `AskUserQuestion` tool used in this very session.
- For **Claude Code**: parse its native `AskUserQuestion` tool call straight out of the
  CLI's structured output and render it — don't reinvent the schema.
- For **other providers** (Gemini/OpenAI/local): implement an equivalent custom tool in
  the shared function-calling layer, since they don't have this built in.

### 3.4 run_shell_command safety model

Three-tier hybrid, all three tiers active simultaneously:

1. **Whitelist** — obviously-safe commands can run without friction.
2. **Blacklist** — obviously-destructive patterns (existing better-ii-ai regexes:
   `rm -rf /`, `dd of=/dev/…`, `curl … | sh`, fork bombs, `git push --force`, etc.) are
   always blocked/gated.
3. **AI judge** — a Gemini call (Flash-Lite by default) reviews **every** command,
   including whitelisted ones, as a second layer of defense. If no Gemini API key is
   configured, fall back to blacklist-only gating (skip the judge step, don't hard-fail).
- **YOLO / full-trust mode**: an explicit opt-in flag or slash command that disables all
  gating (including for destructive commands), clearly labeled as risky in the UI. Never
  the default.
- All shell invocations, judge verdicts, and outcomes get **logged to a file** (under
  `~/.local/share/flash-impulse/logs/`) for audit/debugging.

## 4. Visual redesign — Material 3 Expressive × One UI 8.5/9

The shell is already Material-based (Material You dynamic palette, MD3-style Quickshell
components), so **Material 3 Expressive is the foundation** and **One UI 8.5/9 is the
flavor layered on top**. Division of responsibility:

- **Foundation — M3 Expressive**: component behavior and motion. Springy physics-based
  animations, emphasized easing, shape morphing on press, bolder type scale. When
  touching any component, the M3 Expressive spec is the default answer for how it moves
  and behaves.
- **Flavor — One UI**: geometry and palette. Large rounded corners, pill shapes,
  generous padding/spacing (bar, popups, buttons), Samsung-style soft pastel accents on
  a dark base.
- **Conflict rule**: where the two disagree (e.g. M3E's loud saturated colors vs One
  UI's restrained pastels), One UI wins on color, M3 Expressive wins on motion and
  component behavior. This keeps the result coherent instead of a mix of two half
  design languages.

All areas matter equally, no single priority:
- **Wallpapers**: curate/bundle existing abstract One-UI-style wallpapers as defaults, no
  runtime generation pipeline needed.

## 5. Configuration & state

- Global fork settings (theme choice, which components were installed, AI provider
  defaults) live in their own namespace: **`~/.config/flash-impulse/`** — explicitly
  *not* mixed into `~/.config/hypr` or `~/.config/quickshell/ii`, so upstream-style
  config files stay clean and distinguishable from fork-specific state.
- API keys: system keyring, not files (see §2).

## 6. Docs & CI

- **README** — install instructions, features, credits to end-4 and better-ii-ai origins.
- **CONTRIBUTING.md**.
- **Architecture docs** for the AI subsystem specifically (provider abstraction, the
  Claude Code bridge, the judge/whitelist/blacklist pipeline, the question-block
  protocol) — this is the part most likely to confuse a future contributor (or future
  Claude session), so it needs the most explanation.
- **CI**: GitHub Actions, basic — `shellcheck` on the installer, lint pass on QML/Lua.
  No test framework beyond that for now.

## 7. Explicitly out of scope / deferred

- No automatic upstream sync with end-4/dots-hyprland.
- No multi-distro real hardware testing beyond Arch/CachyOS.
- No formal versioning/releases — rolling release like the upstream project.
- No AI-generated wallpapers at install time.

## 8. Suggested build order

1. ✅ Scaffold repo (squashed history from both sources), GPL-3.0 LICENSE, README.
2. ✅ Rewrite `install.sh` (component selection, backup/rollback, migration prompt,
   keyring secrets, doctor). Done 2026-07-24.
3. ✅ Merge better-ii-ai QML into the tree (incl. the FileUtils.qml fix its installer
   missed). Done 2026-07-24.
4. ✅ Claude Code CLI bridge (`ClaudeCodeApiStrategy.qml`): stream-json parsing,
   --resume sessions (cwd-pinned), AskUserQuestion rendered as options list, verified
   live against CLI 2.1.217. Remaining: GUI permission-prompt bridge (MCP) and real
   button UI for question blocks.
5. ✅ Whitelist/blacklist/Gemini-judge pipeline + audit log + /yolo. Done 2026-07-24.
6. ✅ Model rosters updated to July 2026 IDs (Gemini 3.5/3.6, Claude Sonnet 5 /
   Opus 4.8 / Fable 5, GPT-5.6); Gemini 3.5 Flash-Lite default.
7. ⬜ Material 3 Expressive × One UI visual pass (colors, shapes, animations).
8. ⬜ Bundle default wallpapers + logo/branding.
9. ✅ Docs (README, CONTRIBUTING, docs/ai-architecture.md) + CI (shellcheck + QML parse
   gate). CI is green (billing lock resolved 2026-07-24).
10. ✅ Setup-engine rewrite (2026-07-24): two-layer library (`sdata/lib/engine.sh`
    driving both `./setup` and `./install.sh`), functions.sh de-crufted (−11 dead
    helpers) with a global DRY_RUN, AUR-helper auto-detection (yay/paru), exp-merge
    removed, exp-update replaced by a thin `update`, and end-4 branding stripped from
    engine output. ~2600 net lines removed; full `--dry-run` walk verified.

Remaining: **7** (Material 3 Expressive × One UI visual pass) and **8** (wallpapers +
logo/branding) — the design work, best done as a dedicated session starting from
`Appearance.qml`.
