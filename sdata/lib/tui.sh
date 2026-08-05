# Terminal UI primitives for the Flash-Impulse installer.
#
# This is NOT a script for execution, but a library to source — no shebang and
# no execute bit, matching the other files in this directory. The directive
# below is what tells shellcheck which shell to check it against in the absence
# of one.
# shellcheck shell=bash
#
# Pure bash + ANSI on purpose. The installer's whole job is to put the
# dependencies on the machine, so it runs before any of them exist — it cannot
# lean on gum, dialog, whiptail or python being there. Everything here uses
# escape sequences that have been in every terminal since the 80s.
#
# The widgets take input on stdin and draw on stdout, and every one of them
# bails out to a plain-text path when stdout is not a terminal, so piping the
# installer into a log still produces something readable.

# ------------------------------------------------------------------ palette --
# Deliberately separate from the STY_* set in environment-variables.sh: those
# are the engine's plain colour codes, these are semantic roles the UI assigns.
TUI_ACCENT=$'\e[38;5;209m'  # the brand orange
TUI_DIM=$'\e[2m'
TUI_BOLD=$'\e[1m'
TUI_RST=$'\e[0m'
TUI_OK=$'\e[32m'
TUI_WARN=$'\e[33m'
TUI_ERR=$'\e[31m'
TUI_INV=$'\e[7m'

# Kept so colour can be turned back on: --color is parsed after the first
# decision has already been made from whether stdout is a terminal, and a
# one-way "blank everything" would make that flag unable to undo it.
TUI_ACCENT_DEF="$TUI_ACCENT" TUI_DIM_DEF="$TUI_DIM" TUI_BOLD_DEF="$TUI_BOLD"
TUI_RST_DEF="$TUI_RST" TUI_OK_DEF="$TUI_OK" TUI_WARN_DEF="$TUI_WARN"
TUI_ERR_DEF="$TUI_ERR" TUI_INV_DEF="$TUI_INV"

tui_no_color() {
    TUI_ACCENT=""; TUI_DIM=""; TUI_BOLD=""; TUI_RST=""
    TUI_OK=""; TUI_WARN=""; TUI_ERR=""; TUI_INV=""
}

tui_use_color() {
    TUI_ACCENT="$TUI_ACCENT_DEF"; TUI_DIM="$TUI_DIM_DEF"; TUI_BOLD="$TUI_BOLD_DEF"
    TUI_RST="$TUI_RST_DEF"; TUI_OK="$TUI_OK_DEF"; TUI_WARN="$TUI_WARN_DEF"
    TUI_ERR="$TUI_ERR_DEF"; TUI_INV="$TUI_INV_DEF"
}

# ------------------------------------------------------------- capabilities --
# A widget is only worth drawing when there is someone to look at it and a
# terminal able to move the cursor. "dumb" is what Emacs shells and some CI
# runners report, and it cannot handle the escape sequences below.
tui_available() {
    [[ -t 0 && -t 1 ]] || return 1
    [[ -n "${TERM:-}" && "${TERM}" != "dumb" ]] || return 1
    return 0
}

# stty is the reliable source, but it reports 0 0 on a pty that never had a
# window size set, and is absent entirely in a few minimal environments — so
# fall through to the shell's own idea, then to something sane.
tui_rows() {
    local s r
    s=$(stty size 2>/dev/null) && r="${s%% *}"
    [[ "${r:-0}" -gt 0 ]] || r="${LINES:-0}"
    [[ "${r:-0}" -gt 0 ]] || r=24
    printf '%s' "$r"
}
tui_cols() {
    local s c
    s=$(stty size 2>/dev/null) && c="${s##* }"
    [[ "${c:-0}" -gt 0 ]] || c="${COLUMNS:-0}"
    [[ "${c:-0}" -gt 0 ]] || c=80
    printf '%s' "$c"
}

# ------------------------------------------------------------ screen control --
TUI_ACTIVE=false
TUI_SAVED_STTY=""

tui_enter() {
    tui_available || return 1
    TUI_SAVED_STTY="$(stty -g 2>/dev/null)"
    printf '\e[?1049h\e[?25l'   # alternate screen buffer, hide cursor
    TUI_ACTIVE=true
    # Restore on every way out, including Ctrl-C and being killed, so a crash
    # mid-draw can never leave the user staring at a terminal with no cursor.
    trap 'tui_leave' EXIT
    trap 'tui_leave; exit 130' INT
    trap 'tui_leave; exit 143' TERM
    return 0
}

tui_leave() {
    [[ "$TUI_ACTIVE" == true ]] || return 0
    TUI_ACTIVE=false
    printf '\e[?25h\e[?1049l'   # show cursor, back to the normal screen
    [[ -n "$TUI_SAVED_STTY" ]] && stty "$TUI_SAVED_STTY" 2>/dev/null
    trap - EXIT INT TERM
    return 0
}

tui_home()  { printf '\e[H'; }
tui_clear_eol() { printf '\e[K'; }
tui_clear_below() { printf '\e[J'; }

# Draw a line of the frame: content plus erase-to-end-of-line. Redrawing this
# way rather than clearing the whole screen first is what keeps the menu from
# flickering on every keypress.
tui_line() { printf '%b\e[K\n' "$1"; }

tui_repeat() {
    # tui_repeat <string> <count>
    local out="" i
    for (( i = 0; i < $2; i++ )); do out+="$1"; done
    printf '%s' "$out"
}

# ------------------------------------------------------------------- chrome --
tui_header() {
    # tui_header <subtitle>
    local cols; cols=$(tui_cols)
    tui_line ""
    tui_line "  ${TUI_ACCENT}${TUI_BOLD}Flash-Impulse${TUI_RST}${TUI_DIM} · installer${TUI_RST}"
    tui_line "  ${TUI_DIM}$(tui_repeat '─' $(( cols > 6 ? cols - 4 : 20 )))${TUI_RST}"
    [[ -n "${1:-}" ]] && tui_line "  $1"
    tui_line ""
}

tui_footer() {
    # tui_footer <hint>
    tui_line ""
    tui_line "  ${TUI_DIM}$1${TUI_RST}"
}

# --------------------------------------------------------------- key reading --
# Returns a symbolic name for one keypress: up/down/enter/space/esc/q/... or the
# literal character.
tui_key() {
    local k rest
    IFS= read -rsn1 k 2>/dev/null || return 1
    if [[ "$k" == $'\e' ]]; then
        # An escape sequence and a bare Esc look identical until the next byte
        # fails to arrive, hence the timeout rather than a blocking read.
        IFS= read -rsn2 -t 0.05 rest 2>/dev/null
        case "$rest" in
            '[A') printf 'up' ;;
            '[B') printf 'down' ;;
            '[C') printf 'right' ;;
            '[D') printf 'left' ;;
            *)    printf 'esc' ;;
        esac
        return 0
    fi
    case "$k" in
        '')  printf 'enter' ;;
        ' ') printf 'space' ;;
        *)   printf '%s' "$k" ;;
    esac
}

# ---------------------------------------------------------------- checklist --
# Multi-select. Caller fills these arrays, then reads TUI_CL_STATE back:
#   TUI_CL_LABEL=(...)  TUI_CL_DESC=(...)  TUI_CL_STATE=(on off ...)
# Returns 0 on confirm, 1 if the user backed out.
tui_checklist() {
    local title="$1" hint="${2:-}"
    local n=${#TUI_CL_LABEL[@]}
    local cur=0 key i

    while true; do
        tui_home
        tui_header "$title"
        for (( i = 0; i < n; i++ )); do
            local mark="${TUI_DIM}[ ]${TUI_RST}"
            [[ "${TUI_CL_STATE[$i]}" == "on" ]] && mark="${TUI_OK}[x]${TUI_RST}"
            if (( i == cur )); then
                tui_line "  ${TUI_ACCENT}❯${TUI_RST} ${mark} ${TUI_BOLD}${TUI_CL_LABEL[$i]}${TUI_RST}"
            else
                tui_line "    ${mark} ${TUI_CL_LABEL[$i]}"
            fi
            [[ -n "${TUI_CL_DESC[$i]:-}" ]] && tui_line "        ${TUI_DIM}${TUI_CL_DESC[$i]}${TUI_RST}"
        done
        tui_footer "${hint:-↑↓ move · space toggle · a all · n none · enter continue · q quit}"
        tui_clear_below

        key="$(tui_key)" || return 1
        case "$key" in
            up|k)    (( cur = cur > 0 ? cur - 1 : n - 1 )) ;;
            down|j)  (( cur = cur < n - 1 ? cur + 1 : 0 )) ;;
            space)
                if [[ "${TUI_CL_STATE[cur]}" == "on" ]]; then
                    TUI_CL_STATE[cur]="off"
                else
                    TUI_CL_STATE[cur]="on"
                fi ;;
            a) for (( i = 0; i < n; i++ )); do TUI_CL_STATE[i]="on"; done ;;
            n) for (( i = 0; i < n; i++ )); do TUI_CL_STATE[i]="off"; done ;;
            enter) return 0 ;;
            q|esc) return 1 ;;
        esac
    done
}

# -------------------------------------------------------------------- radio --
# Single-select. Caller fills TUI_RD_LABEL / TUI_RD_DESC; the chosen index comes
# back in TUI_RD_CHOICE. Returns 0 on confirm, 1 if the user backed out.
tui_radio() {
    local title="$1" hint="${2:-}"
    local n=${#TUI_RD_LABEL[@]}
    local cur="${TUI_RD_CHOICE:-0}" key i

    while true; do
        tui_home
        tui_header "$title"
        for (( i = 0; i < n; i++ )); do
            local mark="${TUI_DIM}( )${TUI_RST}"
            (( i == cur )) && mark="${TUI_ACCENT}(•)${TUI_RST}"
            if (( i == cur )); then
                tui_line "  ${TUI_ACCENT}❯${TUI_RST} ${mark} ${TUI_BOLD}${TUI_RD_LABEL[$i]}${TUI_RST}"
            else
                tui_line "    ${mark} ${TUI_RD_LABEL[$i]}"
            fi
            [[ -n "${TUI_RD_DESC[$i]:-}" ]] && tui_line "        ${TUI_DIM}${TUI_RD_DESC[$i]}${TUI_RST}"
        done
        tui_footer "${hint:-↑↓ move · enter select · q quit}"
        tui_clear_below

        key="$(tui_key)" || return 1
        case "$key" in
            up|k)   (( cur = cur > 0 ? cur - 1 : n - 1 )) ;;
            down|j) (( cur = cur < n - 1 ? cur + 1 : 0 )) ;;
            enter)  TUI_RD_CHOICE=$cur; return 0 ;;
            q|esc)  return 1 ;;
        esac
    done
}

# ------------------------------------------------------------------- review --
# A plain scrolling-free page of lines with a yes/no at the bottom. Caller fills
# TUI_PAGE_LINE=(...). Returns 0 for yes, 1 for no.
tui_review() {
    local title="$1" question="${2:-Proceed?}"
    local key i

    while true; do
        tui_home
        tui_header "$title"
        for (( i = 0; i < ${#TUI_PAGE_LINE[@]}; i++ )); do
            tui_line "  ${TUI_PAGE_LINE[$i]}"
        done
        tui_line ""
        tui_line "  ${TUI_BOLD}${question}${TUI_RST}"
        tui_footer "y confirm · n / q go back"
        tui_clear_below

        key="$(tui_key)" || return 1
        case "$key" in
            y|Y|enter) return 0 ;;
            n|N|q|esc) return 1 ;;
        esac
    done
}
