# Commands to run in interactive sessions can go here
if status is-interactive
    # No greeting
    set fish_greeting

    # Use starship
    function starship_transient_prompt_func
        starship module character
    end
    if test "$TERM" != "linux"
        starship init fish | source
        enable_transience
    end
    
    # Colors
    if test -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt
        cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    end

    # Aliases
    # kitty doesn't clear properly so we need to do this weird printing
    alias clear "printf '\033[2J\033[3J\033[1;1H'"
    alias celar "printf '\033[2J\033[3J\033[1;1H'"
    alias claer "printf '\033[2J\033[3J\033[1;1H'"
    alias pamcan pacman
    alias prod 'ssh prod'
    alias q 'qs -c flash-impulse'
    if test "$TERM" != "linux"
        alias ls 'eza --icons=auto'
        alias cat 'bat --paging=never'
    end
    if test "$TERM" = "xterm-kitty"
        alias ssh 'kitten ssh'
    end

    # Zoxide fast navigation
    if command -q zoxide
        zoxide init fish | source
    end
end

# FlashAgent
fish_add_path /home/flashback/.local/bin


# Added by Antigravity CLI installer
set -gx PATH "/home/flashback/.local/bin" $PATH
