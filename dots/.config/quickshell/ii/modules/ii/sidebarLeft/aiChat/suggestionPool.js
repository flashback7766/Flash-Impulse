.pragma library

/**
 * Things worth asking an assistant that can read the machine it runs on.
 *
 * Entries are [icon, label, prompt, when?]. `when` names a condition the shell
 * evaluates from state it already tracks — no extra processes are spawned to
 * decide what to offer. A conditional entry is only ever offered while its
 * condition holds, and those get first pick of the slots, so a laptop at 8%
 * leads with the battery question rather than burying it in a shuffle.
 *
 * The rest are drawn at random. Four fixed cards stop being read after about a
 * day; a pool this size means the empty chat is rarely the same twice, and the
 * breadth doubles as a map of what this thing is actually for.
 */

var POOL = [
    // ---- context-triggered: the machine is telling you something -----------
    ["battery_alert", "What's draining my battery?", "Check what's using the most power on this laptop right now and tell me what to do about it.", "batteryLow"],
    ["battery_alert", "Make this charge last longer", "I'm on battery and low. Find the cheapest wins for battery life on this machine right now and apply the safe ones.", "batteryLow"],
    ["bolt", "Is anything abusing the CPU while I charge?", "I'm plugged in. Check whether anything is burning CPU in the background that shouldn't be.", "batteryCharging"],
    ["memory_alt", "Why is my memory almost full?", "Memory is nearly full. Find what's holding it and tell me what's safe to kill.", "memoryHigh"],
    ["swap_horiz", "Why am I swapping?", "The system is using swap. Work out what pushed it there and whether it matters.", "swapUsed"],
    ["system_update", "What's in these pending updates?", "There are pending system updates. Summarise what they change and flag anything I should read before upgrading.", "updatesPending"],
    ["system_update", "Is it safe to update right now?", "Check the pending updates for anything that needs manual intervention on Arch before I run them.", "updatesPending"],
    ["monitor", "Set up my second monitor", "Look at my monitor setup and help me configure the second display properly.", "multiMonitor"],
    ["monitor", "Fix the layout of my displays", "My monitors are arranged wrong — check the current layout and fix the positions so the edges line up.", "multiMonitor"],
    ["volume_off", "My audio is muted — is that me?", "Audio is muted. Check whether something muted it and get sound back.", "audioMuted"],
    ["wifi_off", "Get me back online", "I have no network connection. Diagnose it and fix what you can.", "networkDown"],
    ["dark_mode", "Cut the eye strain for tonight", "It's late. Set up the display for night — colour temperature, brightness, anything else that helps.", "night"],
    ["wb_sunny", "What should I look at first today?", "Give me a short status of this machine this morning: updates, disk, anything that broke overnight.", "morning"],
    ["window", "I have too many windows open", "Show me what's running across my workspaces and suggest what to close.", "manyWindows"],

    // ---- Hyprland and the desktop -----------------------------------------
    ["monitor", "Set up my second monitor", "Look at my monitor setup and help me configure the second display properly."],
    ["desktop_windows", "Explain my Hyprland config", "Read my Hyprland configuration and explain how it's organised and what the non-obvious parts do."],
    ["keyboard", "What keybinds do I have?", "List my Hyprland keybinds grouped by what they do, and point out any conflicts."],
    ["keyboard", "Add a keybind for this", "Help me add a Hyprland keybind, and write it into the right custom config file so it survives an update."],
    ["animation", "Make my animations snappier", "My window animations feel sluggish. Show me the current settings and tune them."],
    ["blur_on", "Tune the blur and transparency", "Walk me through the blur and opacity settings in my Hyprland config and help me pick better values."],
    ["grid_view", "Set up workspace rules", "Help me pin certain apps to certain workspaces in Hyprland."],
    ["fullscreen", "Fix a window that opens wrong", "A window keeps opening at the wrong size or workspace. Help me write a window rule for it."],
    ["mouse", "My cursor is the wrong size", "Fix the cursor theme and size across Hyprland, GTK and Qt apps so they match."],
    ["touch_app", "Configure my touchpad", "Show me my touchpad settings and help me get natural scrolling and gestures the way I want."],
    ["language", "Add a keyboard layout", "Help me add a second keyboard layout with a toggle shortcut."],
    ["screenshot_monitor", "Improve my screenshot setup", "Show me how screenshots are bound and configured here, and suggest a better workflow."],
    ["lock", "Check my lockscreen setup", "Look at my hyprlock and hypridle configuration and tell me whether the timings make sense."],
    ["wallpaper", "Change my wallpaper properly", "Help me set a wallpaper the way this setup expects, so the colour theme follows it."],
    ["palette", "Explain how theming works here", "Explain how the colour scheme is generated and applied across this desktop."],
    ["dvr", "What's autostarting?", "List everything that starts with my session and tell me what each one is for."],
    ["tab", "Set up scratchpad windows", "Help me configure a dropdown terminal or scratchpad window in Hyprland."],
    ["pan_tool", "Configure gestures", "Help me set up touchpad gestures for switching workspaces."],
    ["display_settings", "Set fractional scaling", "Help me set up display scaling so text is the right size on both my screens."],
    ["cast", "Share my screen", "Screen sharing doesn't work in some apps. Diagnose the portal setup."],
    ["notifications", "Tune my notifications", "Show me how notifications are configured here and help me quiet the noisy ones."],
    ["bolt", "Reduce input latency", "Check for anything adding input lag on this desktop and fix what you can."],
    ["view_carousel", "Explain my bar setup", "Explain what's on my status bar, where it's configured, and how to change it."],
    ["settings_applications", "What can I configure here?", "Give me a tour of what's configurable in this desktop setup and where each thing lives."],
    ["restart_alt", "Reload config without logging out", "Show me how to apply config changes to this desktop without restarting my session."],

    // ---- diagnostics -------------------------------------------------------
    ["monitor_heart", "Give me a health check", "Run a general health check on this machine and tell me if anything looks wrong."],
    ["memory", "What are my specs?", "Gather the full hardware and software specs of this machine and summarise them."],
    ["thermostat", "Am I running hot?", "Check temperatures and fan behaviour and tell me whether they're normal for this hardware."],
    ["speed", "Why does this feel slow?", "The machine feels sluggish. Find out why."],
    ["memory_alt", "What's using my RAM?", "Show me what's using memory and whether anything is leaking."],
    ["storage", "What's eating my disk space?", "Find what's taking up the most disk space on this machine and summarise it."],
    ["cleaning_services", "Help me free up space", "Find safe things to delete to reclaim disk space, and tell me how much each would save."],
    ["hourglass_top", "Why is boot slow?", "Analyse my boot time and tell me what's slowing it down."],
    ["error", "Anything crashing?", "Check the journal for crashes and errors from the last day and explain the important ones."],
    ["warning", "Explain this error in my logs", "Look through my recent system logs and explain anything that looks like a real problem."],
    ["usb", "What's plugged in?", "List my USB and PCI devices and tell me if anything is unrecognised or misbehaving."],
    ["videogame_asset", "Is my GPU set up right?", "Check my graphics stack — driver, acceleration, Vulkan — and tell me if anything is missing."],
    ["print", "My printer doesn't work", "Diagnose printing on this machine."],
    ["bluetooth", "Bluetooth is being difficult", "Diagnose my Bluetooth setup and help me pair a device."],
    ["sd_card", "Check my disk health", "Check SMART data for my drives and tell me if anything is failing."],
    ["timer", "What's running on a timer?", "List systemd timers and cron jobs on this machine and explain what each does."],
    ["dns", "What services are running?", "List running services and flag anything I probably don't need."],
    ["update", "Did something break after an update?", "Something changed recently. Check what was updated lately and whether it explains the problem."],
    ["thermostat", "Tune my fan curve", "Look at my fan and thermal setup and tell me whether it can be improved."],
    ["battery_charging_full", "Check my battery health", "Report the wear level and health of this laptop battery."],

    // ---- audio -------------------------------------------------------------
    ["volume_up", "My audio stopped working", "My sound stopped working. Check the audio stack and help me fix it."],
    ["headphones", "My headphones aren't detected", "Diagnose why my headphones aren't showing up as an output."],
    ["mic", "Fix my microphone", "Check my microphone setup and fix the input level and device selection."],
    ["graphic_eq", "Set up an equaliser", "Help me set up EasyEffects or similar for my speakers."],
    ["speaker", "Why does audio crackle?", "My audio crackles or drops out. Diagnose the pipewire configuration."],
    ["volume_down", "Make per-app volume work", "Help me control volume per application properly."],
    ["surround_sound", "Route audio to a specific device", "Help me send one app's audio to a different output device."],
    ["bluetooth_audio", "Bluetooth audio sounds bad", "My Bluetooth headphones sound low quality. Check the codec in use and improve it."],
    ["hearing", "Reduce background noise on my mic", "Set up noise suppression for my microphone."],
    ["music_note", "What's playing?", "Tell me what's currently playing and where it's coming from."],

    // ---- network -----------------------------------------------------------
    ["wifi", "My wifi keeps dropping", "Diagnose why my wifi connection keeps dropping."],
    ["speed", "Test my connection", "Check my network speed and latency and tell me whether it's reasonable."],
    ["vpn_key", "Set up a VPN", "Help me configure a VPN connection on this machine."],
    ["dns", "Fix my DNS", "Check my DNS configuration and whether resolution is working properly."],
    ["router", "What's on my network?", "Scan my local network and tell me what devices are on it."],
    ["lan", "Share a folder over the network", "Help me share a directory with another machine on my network."],
    ["cloud_off", "Something can't reach the internet", "One app has no network access but everything else works. Diagnose it."],
    ["security", "Check my firewall", "Show me my firewall rules and tell me whether they make sense."],
    ["swap_calls", "Set up an SSH key", "Walk me through setting up an SSH key for a server, and do the parts you safely can."],
    ["terminal", "Make SSH less painful", "Help me set up SSH config entries so I stop typing long commands."],

    // ---- packages ----------------------------------------------------------
    ["inventory_2", "What did I install recently?", "Show me what packages were installed or updated recently on this system."],
    ["delete_sweep", "Clean up orphan packages", "Find orphaned and unused packages and tell me what's safe to remove."],
    ["search", "Find a package for this", "Help me find the right package for something I want to do."],
    ["build", "Explain the AUR", "Explain how the AUR works and what the risks are, in the context of my setup."],
    ["cached", "Clear my package cache", "Show me how much space the package cache uses and clean it safely."],
    ["lock_open", "A package is held back", "Something isn't updating. Work out why and what to do about it."],
    ["extension", "What AUR packages do I have?", "List my AUR packages and flag any that look unmaintained."],
    ["compare_arrows", "Compare two packages", "Help me pick between two packages that do the same thing on Arch."],
    ["history", "Roll back a package", "Help me downgrade a package that broke after an update."],
    ["fact_check", "Check for partial upgrades", "Verify my system isn't in a partial-upgrade state."],

    // ---- files and shell ---------------------------------------------------
    ["folder_open", "Find these files for me", "Help me find files matching something I'll describe."],
    ["find_in_page", "Search my files by content", "Help me search inside my files for a phrase."],
    ["content_copy", "Find duplicate files", "Find duplicate files in my home directory and show me the biggest wins."],
    ["drive_file_rename_outline", "Bulk rename some files", "Help me rename a batch of files following a pattern."],
    ["folder_zip", "Extract this archive", "Help me extract an archive and put the contents somewhere sensible."],
    ["backup", "Set up backups", "Help me set up a simple backup for my important directories."],
    ["schedule", "Schedule a task", "Help me run something on a schedule with a systemd timer."],
    ["terminal", "Write me a shell script", "Help me write a shell script for something I'll describe."],
    ["code", "Explain this command", "Explain a shell command I'll paste, piece by piece."],
    ["bug_report", "My script doesn't work", "Help me debug a shell script that isn't behaving."],
    ["alt_route", "Make this a one-liner", "Turn something I'm doing by hand into a single command."],
    ["keyboard_command_key", "Set up shell aliases", "Help me add useful aliases to my shell config."],
    ["auto_awesome", "Improve my shell prompt", "Look at my shell setup and suggest improvements."],
    ["history", "What did I run earlier?", "Help me find a command I ran recently but can't remember."],
    ["rule", "Explain this regex", "Explain a regular expression I'll paste and tell me if it has holes."],
    ["transform", "Convert between formats", "Help me convert a file from one format to another."],
    ["compress", "Shrink these images", "Help me batch-compress images without visibly losing quality."],
    ["movie", "Convert a video", "Help me re-encode a video with ffmpeg for a specific purpose."],
    ["picture_as_pdf", "Do something with a PDF", "Help me split, merge or extract text from a PDF."],
    ["table_chart", "Process a CSV", "Help me filter and summarise a CSV from the command line."],

    // ---- coding ------------------------------------------------------------
    ["code", "Review this code", "Review code I'll paste for bugs and for anything that will bite later."],
    ["bug_report", "Explain this error", "Explain an error message I'll paste and tell me the likely cause."],
    ["speed", "Make this faster", "Help me find why some code is slow and what to do about it."],
    ["architecture", "Design this with me", "Talk through the design of something I'm about to build."],
    ["quiz", "Explain this code", "Explain a piece of code I'll paste, including why it's written that way."],
    ["science", "Write tests for this", "Help me write tests for code I'll paste, including the cases I'd forget."],
    ["cleaning_services", "Refactor this", "Suggest how to restructure code I'll paste, with the trade-offs."],
    ["published_with_changes", "Port this to another language", "Help me translate code from one language to another idiomatically."],
    ["data_object", "Design a data model", "Help me model some data properly."],
    ["api", "Help me with an API", "Help me call an API correctly, including auth and error handling."],
    ["terminal", "Set up a dev environment", "Help me set up a development environment for a project on this machine."],
    ["dashboard", "Explain this stack trace", "Read a stack trace I'll paste and tell me where the real problem is."],
    ["schema", "Write a regex for this", "Write and explain a regex for a pattern I'll describe."],
    ["memory", "Find the memory leak", "Help me track down a memory leak."],
    ["merge_type", "Resolve this conflict", "Help me resolve a merge conflict sensibly."],
    ["build_circle", "My build is broken", "Help me work out why a build is failing."],
    ["settings_suggest", "Explain this config file", "Explain a configuration file I'll paste and what the important options do."],
    ["difference", "Compare two approaches", "Compare two ways of doing something and recommend one for my case."],
    ["stairs", "Teach me this concept", "Explain a programming concept properly, with an analogy and a real example."],
    ["checklist", "Turn this into a plan", "Break something I want to build into ordered steps."],

    // ---- git ---------------------------------------------------------------
    ["commit", "Write my commit message", "Look at my staged changes and write a commit message that explains why."],
    ["history", "What changed here?", "Summarise the recent history of a repository and what it means."],
    ["undo", "Undo my last commit", "Help me undo something in git without losing work."],
    ["account_tree", "Explain git branching to me", "Explain a branching workflow that would suit how I work."],
    ["search", "Find when this broke", "Help me bisect a repository to find where something broke."],
    ["cleaning_services", "Clean up my branches", "Show me stale branches and help me tidy the repository."],
    ["visibility", "Review my own diff", "Review my uncommitted changes before I commit them."],
    ["merge", "Rebase this safely", "Walk me through a rebase without breaking anything."],
    ["backup", "I lost some work in git", "Help me recover work I think I lost in git."],
    ["upload_file", "Set up a new repository", "Help me start a repository properly, including a sensible ignore file."],

    // ---- security and privacy ---------------------------------------------
    ["security", "Audit my setup", "Look for obvious security problems in how this machine is configured."],
    ["key", "Check my SSH keys", "Show me what SSH keys I have and whether any are weak or unused."],
    ["visibility_off", "What can see my screen?", "Tell me which applications can capture my screen or audio."],
    ["folder_supervised", "Check these permissions", "Look for files with permissions that are more open than they should be."],
    ["shield", "Explain this security warning", "Explain a security warning I'll describe and whether I should care."],
    ["password", "Set up a password manager", "Help me set up a password manager on this machine."],
    ["fingerprint", "Set up disk encryption", "Explain my options for encrypting a drive on this system."],
    ["gpp_maybe", "Is this script safe?", "Read a script I'll paste and tell me honestly what it does before I run it."],
    ["policy", "Harden my SSH server", "Review my SSH server configuration for anything risky."],
    ["no_accounts", "Reduce telemetry", "Find anything on this machine phoning home and tell me how to stop it."],

    // ---- performance -------------------------------------------------------
    ["speed", "Make my system faster", "Find the biggest performance wins available on this machine right now."],
    ["monitor_heart", "Profile something slow", "Help me profile a slow program and read the results."],
    ["rocket_launch", "Optimise for gaming", "Tune this machine for games — driver, scheduler, compositor settings."],
    ["battery_saver", "Optimise for battery", "Set this laptop up to last as long as possible on battery."],
    ["memory", "Tune swap and zram", "Look at my swap setup and tell me whether zram would help."],
    ["hourglass_disabled", "Reduce stutter", "I get occasional stutter. Find out what causes it."],
    ["compress", "Shrink my install", "Find the biggest space users in my installed system and what's safe to drop."],
    ["tune", "Explain performance mode", "Explain what this desktop's performance mode changes and whether I should use it."],

    // ---- learning ----------------------------------------------------------
    ["school", "Explain Wayland vs X11", "Explain the practical differences between Wayland and X11 for someone using this desktop."],
    ["school", "How does systemd work?", "Explain systemd units in a way I can actually use."],
    ["school", "Explain Linux permissions", "Explain the Linux permission model, including the parts people get wrong."],
    ["school", "How does the boot process work?", "Walk me through what happens between power-on and my desktop appearing on this machine."],
    ["school", "Explain containers", "Explain containers from first principles, and how they differ from VMs."],
    ["school", "How does DNS actually work?", "Explain DNS resolution end to end, including what my machine does locally."],
    ["school", "Explain filesystems", "Compare the filesystems available on Linux and tell me which suits what."],
    ["school", "How does the kernel schedule?", "Explain CPU scheduling on Linux and what the tunables actually do."],
    ["school", "Explain memory management", "Explain virtual memory, page cache and swap in practical terms."],
    ["school", "What is a display server?", "Explain what a compositor does and where Hyprland fits."],
    ["school", "Explain pipewire", "Explain how PipeWire replaced PulseAudio and JACK, and what that means for me."],
    ["school", "How do fonts work on Linux?", "Explain font rendering and configuration on Linux."],
    ["school", "Explain the FHS", "Explain what each top-level directory on a Linux system is for."],
    ["school", "How does package management work?", "Explain what a package manager actually does, using pacman as the example."],
    ["school", "Explain shell quoting", "Explain shell quoting and word splitting properly, with the traps."],
    ["school", "What are cgroups?", "Explain cgroups and namespaces and what they're used for."],
    ["school", "Explain SSH", "Explain how SSH authentication works, keys and agents included."],
    ["school", "How does git store things?", "Explain git's object model — what's actually on disk."],
    ["school", "Explain Unicode", "Explain Unicode, encodings and why text sometimes breaks."],
    ["school", "What is D-Bus?", "Explain D-Bus and what depends on it in a desktop session."],

    // ---- odds and ends -----------------------------------------------------
    ["lightbulb", "Suggest something I'd like", "Based on how this machine is set up, suggest a tool I'm probably missing."],
    ["auto_fix_high", "Improve my workflow", "Look at how this desktop is configured and suggest workflow improvements."],
    ["checklist", "Review my dotfiles", "Look through my dotfiles and tell me what's unusual, redundant or risky."],
    ["tips_and_updates", "Teach me a shortcut", "Show me a keyboard shortcut or trick in this setup I probably don't know."],
    ["extension", "What's this process?", "Tell me what an unfamiliar process on my system is."],
    ["query_stats", "Explain this output", "Explain the output of a command I'll paste."],
    ["translate", "Translate this", "Translate something for me and explain any nuance."],
    ["summarize", "Summarise this for me", "Summarise a piece of text I'll paste."],
    ["edit_note", "Help me write this", "Help me write something — I'll tell you what and for whom."],
    ["forum", "Rubber-duck with me", "I'm stuck on something. Ask me questions until we find the problem."],
    ["hub", "Explain what MCP would give me", "Explain what an MCP server is and which ones would actually be useful on this desktop."],
    ["monitor", "Set a refresh rate", "Check what refresh rates my displays support and set the best one permanently."],
    ["nightlight", "Set up a night-light schedule", "Configure a colour temperature schedule that follows sunset here."],
    ["view_column", "Explain my workspace setup", "Explain how workspaces are configured on this desktop and suggest a better arrangement."],
    ["photo_camera", "Record my screen", "Help me record a screen capture with audio on Wayland."],
    ["content_paste", "Fix my clipboard", "Clipboard behaviour is inconsistent between apps. Diagnose the clipboard setup."],
    ["swap_vert", "Move a config to the right place", "I edited a file that gets overwritten on update. Help me move the change somewhere it survives."],
    ["rule_folder", "Explain this systemd unit", "Explain a systemd unit file I'll paste, line by line."],
    ["troubleshoot", "Something worked yesterday", "Something worked yesterday and doesn't today. Help me find what changed."],
    ["insights", "Read this benchmark for me", "Interpret benchmark results I'll paste in the context of this hardware."],
    ["water_drop", "Reduce my idle power draw", "Find what's keeping this machine awake or drawing power while idle."],
    ["home_repair_service", "Fix my file associations", "The wrong applications open my files. Fix the default associations."],
    ["input", "Remap a key", "Help me remap a key or add a compose sequence on Wayland."]
];

/**
 * Four suggestions: everything the context justifies first, then random fill.
 * @param context object of boolean condition keys
 * @param count how many to return
 */
function pick(context, count) {
    var contextual = [];
    var general = [];
    for (var i = 0; i < POOL.length; i++) {
        var entry = POOL[i];
        var condition = entry[3];
        if (condition === undefined) general.push(entry);
        else if (context && context[condition]) contextual.push(entry);
    }

    var chosen = [];
    var seen = {};
    var usedCondition = {};
    function take(list, limit, onePerCondition) {
        var pool = list.slice();
        while (pool.length > 0 && chosen.length < limit) {
            var at = Math.floor(Math.random() * pool.length);
            var candidate = pool.splice(at, 1)[0];
            // Contextual and general lists overlap by label on purpose — the
            // monitor question exists in both — so don't offer it twice.
            if (seen[candidate[1]]) continue;
            // One card per reason. Two monitors plugged in is one thing to say
            // something about, not two of the four things on offer.
            if (onePerCondition && usedCondition[candidate[3]]) continue;
            usedCondition[candidate[3]] = true;
            seen[candidate[1]] = true;
            chosen.push({ icon: candidate[0], label: candidate[1], prompt: candidate[2] });
        }
    }
    // At most half the slots go to context, so a low battery doesn't crowd out
    // everything else the assistant can do.
    take(contextual, Math.min(count, Math.ceil(count / 2)), true);
    take(general, count, false);
    return chosen;
}
