# Flash-Impulse — Roadmap

Fork of [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) (Illogical Impulse),
merged with [flashback7766/better-ii-ai](https://github.com/flashback7766/better-ii-ai),
redesigned around Material 3 Expressive, with a rewritten installer and a Claude
Code-backed AI sidebar.

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
  wallpapers: source/curate existing abstract wallpapers and bundle them in
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

## 4. Visual redesign — Material 3 Expressive

**Material 3 Expressive is the design language, full stop.** The shell was already
Material-based (Material You dynamic palette, MD3-style Quickshell components), so this
is a matter of following the spec rather than layering a second one on top of it. An
earlier version of this section named Samsung's One UI as a "flavor layer" for geometry
and color; that only ever produced arguments about which language won a given decision.
The spec answers the question on its own.

- **Motion**: springy physics-based animations, emphasized easing, shape morphing on
  press. Upstream already ships the M3 Expressive spring curves (`expressive*Spatial`).
- **Shape**: the M3 Expressive shape scale, which is generously rounded and pill-leaning
  in its own right — the values here did not need to change when the One UI framing went
  away.
- **Color**: a Material You palette derived from the wallpaper, seeded from the brand
  orange. Restrained rather than loud, because the accent has to survive being on screen
  all day.

All areas matter equally, no single priority:
- **Wallpapers**: curate/bundle existing abstract wallpapers as defaults, no runtime
  generation pipeline needed.

## 5. Configuration & state

- Global fork settings (theme choice, which components were installed, AI provider
  defaults) live in their own namespace: **`~/.config/flash-impulse/`** — explicitly
  *not* mixed into `~/.config/hypr` or `~/.config/quickshell/flash-impulse`, so upstream-style
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

## 7. Direction (not yet scheduled)

Two standing goals from 2026-08-06. Neither is a task with a finish line; both are
tie-breakers for how to do the next piece of work.

### 7.1 Diverge from the inherited code

Being a fork is fine and is stated plainly in the README — the objection is not to the
attribution, it is that most of the tree is still recognisably upstream's. The share of
code that is obviously inherited should go down over time.

This does **not** mean renaming things to look different, or rewriting working code for
the sake of a diff. It means: when a module has to be touched anyway, it gets rebuilt
around how this fork actually works rather than patched in upstream's shape. The settings
app and the bar module system are the pattern to follow — both started as a change to an
inherited file and ended as something that is ours, with the old design's specific
failures named in the commit.

Priority order when picking what to rebuild: the things a user interacts with most (bar,
sidebars, launcher, overview) before the plumbing.

### 7.2 Data-oriented layout for weak CPUs

Prefer contiguous, sequentially-scanned data over graphs of small objects. QML encourages
the opposite — one object per list item, each with its own bindings and its own place in
memory — and on a slow CPU the cost shows up as cache misses on every frame, not as one
slow function you can find in a profile.

Concretely, when rewriting a hot path: keep values in flat typed arrays indexed in
parallel rather than in an array of objects; iterate in index order; do the work in one
pass over the array instead of per-item bindings that each re-evaluate independently. The
resource chips, workspace list, notification list and launcher results are the obvious
candidates — all of them are lists rebuilt often, on a machine where the shell has to
share the CPU with whatever the user is actually doing.

Measure before and after. The claim to beat is frame time on the weakest machine
available, not lines of code.

## 8. Explicitly out of scope / deferred

- No automatic upstream sync with end-4/dots-hyprland.
- No multi-distro real hardware testing beyond Arch/CachyOS.
- No formal versioning/releases — rolling release like the upstream project.
- No AI-generated wallpapers at install time.

## 9. Suggested build order

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
7. ✅ Material 3 Expressive visual pass (2026-07-24):
   - Shapes: rounding scale bumped throughout (Appearance.rounding, window
     rounding 18→26, gentle squircle power 3.0), roomier gaps (6/10).
   - Color: matugen seeded from brand orange #ff7a1a with scheme-content →
     pastel-orange primary on warm dark neutrals.
     Note for posterity: `auto` washes out on our pastel wallpaper and
     scheme-expressive hue-rotates to pink — content + explicit accent is
     the combo that works.
   - Motion: upstream already ships the M3 Expressive spring curves
     (expressive*Spatial), so nothing to change.
   Deployed live and verified (hyprctl options, qs restart clean, screenshot).
8. ✅ Wallpaper + logo/branding (2026-07-24): original abstract SVG art
   (brand/wallpaper.svg → default_wallpaper.png, brand/logo.svg → flash-impulse
   icon), About panel rebranded to Flash-Impulse. Note: the reference was a
   Samsung update-screen wallpaper — NOT redistributed; the shipped art is drawn
   from scratch to stay GPL-clean.
9. ✅ Docs (README, CONTRIBUTING, docs/ai-architecture.md) + CI (shellcheck + QML parse
   gate). CI is green (billing lock resolved 2026-07-24).
10. ✅ Setup-engine rewrite (2026-07-24): two-layer library (`sdata/lib/engine.sh`
    driving both `./setup` and `./install.sh`), functions.sh de-crufted (−11 dead
    helpers) with a global DRY_RUN, AUR-helper auto-detection (yay/paru), exp-merge
    removed, exp-update replaced by a thin `update`, and end-4 branding stripped from
    engine output. ~2600 net lines removed; full `--dry-run` walk verified.

11. ✅ Settings & first-run rewritten (2026-08-06): the eight-page settings app
    became 37 topic pages behind a Material 3 navigation drawer with search, and
    the welcome scroll became a seven-step wizard. Every one of the 273 config
    options is now editable in the app — including the ones that previously had
    no UI at all (default apps, night light, scroll tuning, update thresholds,
    tray/keyword/pinned lists, MCP servers, extra models), which is what let the
    "check config.json for the rest" notice go away. Text fields were redrawn
    compact and fully rounded; the Qt Material container is a 56px phone control
    and looked it. Along the way: `notifications.forceMonitor.*` in the old
    Interface page pointed at a config path that does not exist, so the
    force-monitor switch had never done anything.

**All build-order items complete.** Future niceties (not blockers): GUI
permission-prompt MCP bridge for Claude Code, real button UI for AskUserQuestion
blocks, deeper M3 Expressive component polish.
