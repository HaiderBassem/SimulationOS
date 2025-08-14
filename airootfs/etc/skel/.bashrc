#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Change the window title
PS1='[\u@\h \W]\$ '

[ -r /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion

# Export
export EDITOR='nvim'
export VISUAL='nvim'
export HISTCONTROL=ignoreboth:erasedups

#ignore upper and lowercase when TAB completion
bind "set completion-ignore-case on"

#system
alias edital='$EDITOR ~/.bashrc'
alias applyal='source ~/.bashrc'
alias please='sudo'



alias l='eza --color=always --group-directories-first --icons'
alias l.='eza -a | grep -e '\''^\.'\'''
alias la='eza -al --color=always --group-directories-first --icons'
alias ll='eza -l --color=always --group-directories-first --icons'
alias ls='eza -a --color=always --group-directories-first --icons'
alias lt='eza -aT --color=always --group-directories-first --icons'
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
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'


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

#pacman
alias belong='sudo pacman -Qo'
alias in='sudo pacman -S'
alias qu='sudo pacman -Sii'
alias re='sudo pacman -Rs'
alias search='pacman -Ss'
alias up='sudo pacman -Syyu'

#etc
alias kernel='ls /usr/lib/modules'
alias kernels='ls /usr/lib/modules'
alias rm='trash-put'
alias snapchome='sudo snapper -c home create-config /home'
alias snapcroot='sudo snapper -c root create-config /'
alias sound='pavucontrol'


ex ()
{
  if [ -f $1 ] ; then
    case $1 in
      *.tar.bz2)   tar xjf $1   ;;
      *.tar.gz)    tar xzf $1   ;;
      *.bz2)       bunzip2 $1   ;;
      *.rar)       unrar x $1   ;;
      *.gz)        gunzip $1    ;;
      *.tar)       tar xf $1    ;;
      *.tbz2)      tar xjf $1   ;;
      *.tgz)       tar xzf $1   ;;
      *.zip)       unzip $1     ;;
      *.Z)         uncompress $1;;
      *.7z)        7z x $1      ;;
      *.deb)       ar x $1      ;;
      *.tar.xz)    tar xf $1    ;;
      *.tar.zst)   tar xf $1    ;;
      *)           echo "'$1' cannot be extracted via ex()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# Bash won't get SIGWINCH if another process is in the foreground.
# Enable checkwinsize so that bash will check the terminal size when
# it regains control.  #65623
# http://cnswww.cns.cwru.edu/~chet/bash/FAQ (E11)
shopt -s checkwinsize

#beautiful stuff
shopt -s autocd # change to named directory
shopt -s cdspell # autocorrects cd misspellings
shopt -s cmdhist # save multi-line commands in history as single line
shopt -s dotglob
shopt -s histappend # do not overwrite history
shopt -s expand_aliases # expand aliases



#fastfetch
