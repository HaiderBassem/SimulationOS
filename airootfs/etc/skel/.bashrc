#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

[ -r /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion

# Change the window title of X terminals
case ${TERM} in
    xterm*|rxvt*|Eterm*|aterm|kterm|gnome*|interix|konsole*)
        PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME%%.*}:${PWD/#$HOME/\~}\007"'
        ;;
    screen*)
        PROMPT_COMMAND='echo -ne "\033_${USER}@${HOSTNAME%%.*}:${PWD/#$HOME/\~}\033\\"'
        ;;
esac
#system
alias edital='nvim ~/.config/fish/config.fish'
alias applyal='source ~/.config/fish/config.fish'
alias please='sudo'

alias ls='ls --color=auto'
alias la='ls -a'
alias ll='ls -la'
alias l='ls'
alias l.="ls -A | egrep '^\.'"
alias grep='grep --colour=auto'
alias egrep='egrep --colour=auto'
alias fgrep='fgrep --colour=auto'
alias df='df -h'                          # human-readable sizes
alias free='free -m'  
alias c="clear"
alias n="nvim"
alias ex="exit"
alias fs="fastfetch"
alias nv='nvidia-smi'
alias ..='cd ..'
alias ll='ls -lah'


# git
alias du='du -h --max-depth=1'
alias gc='git commit -m'
alias gco='git checkout'
alias gb='git branch'
alias gd='git diff'
alias ga='git add'
alias gs='git status'
alias gp='git push'
alias gpm='git push origin main'
alias gl='git pull'
alias gn='git clone'
alias gpr='git pull --rebase'

#newtworks
alias ports='netstat -tulanp'








# show sizes in MB
PS1='[\u@\h \W]\$ '

# Bash won't get SIGWINCH if another process is in the foreground.
# Enable checkwinsize so that bash will check the terminal size when
# it regains control.  #65623
# http://cnswww.cns.cwru.edu/~chet/bash/FAQ (E11)
shopt -s checkwinsize

shopt -s expand_aliases

# export QT_SELECT=4

# Enable history appending instead of overwriting.  #139609
shopt -s histappend


#fastfetch
