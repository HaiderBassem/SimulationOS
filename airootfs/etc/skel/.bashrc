#
# ~/.bashrc - SimulationOS
#
# Every alias here refers to a command that SimulationOS actually installs.
# The previous version aliased `rm` to trash-put and used nvim/nvidia-smi/
# snapper/auto-cpufreq without shipping any of them, which broke `rm` in the
# live session.
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

PS1='[\u@\h \W]\$ '

[ -r /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion

export EDITOR='nvim'
export VISUAL='nvim'
export HISTCONTROL=ignoreboth:erasedups

# ignore case during TAB completion
bind "set completion-ignore-case on" 2>/dev/null

# ------------------------------------------------------------------- listing
alias ls='eza --color=always --group-directories-first --icons'
alias l='eza --color=always --group-directories-first --icons'
alias la='eza -al --color=always --group-directories-first --icons'
alias ll='eza -l --color=always --group-directories-first --icons'
alias lt='eza -aT --color=always --group-directories-first --icons'

# ------------------------------------------------------------------- general
alias grep='grep --colour=auto'
alias df='df -h'
alias du='du -h --max-depth=1'
alias free='free -m'
alias c='clear'
alias n='nvim'
alias fs='fastfetch'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# ----------------------------------------------------------------------- git
alias gs='git status'
alias ga='git add'
alias gc='git commit -m'
alias gco='git checkout'
alias gb='git branch'
alias gd='git diff'

# -------------------------------------------------------------------- pacman
alias in='sudo pacman -S'
alias re='sudo pacman -Rs'
alias up='sudo pacman -Syu'
alias search='pacman -Ss'
alias belong='pacman -Qo'

# --------------------------------------------------------------- SimulationOS
alias install-simulationos='simulationos-install'
alias kernels='ls /usr/lib/modules'

# extract almost anything
extract() {
  if [ ! -f "$1" ]; then
    printf 'extract: %s is not a valid file\n' "$1" >&2
    return 1
  fi
  case "$1" in
    *.tar.bz2|*.tbz2) tar xjf "$1" ;;
    *.tar.gz|*.tgz)   tar xzf "$1" ;;
    *.tar.xz|*.tar.zst|*.tar) tar xf "$1" ;;
    *.bz2)            bunzip2 "$1" ;;
    *.gz)             gunzip "$1" ;;
    *.zip)            unzip "$1" ;;
    *.7z)             7z x "$1" ;;
    *)                printf 'extract: unsupported archive %s\n' "$1" >&2; return 1 ;;
  esac
}

shopt -s checkwinsize
shopt -s autocd
shopt -s cdspell
shopt -s cmdhist
shopt -s histappend
shopt -s expand_aliases

# Short system summary on the first interactive shell of a session.
if [ -z "$SIMOS_FETCH_SHOWN" ] && [ -t 1 ]; then
  export SIMOS_FETCH_SHOWN=1
  command -v fastfetch >/dev/null 2>&1 && fastfetch
fi
