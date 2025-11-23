export ZSH="$HOME/.oh-my-zsh"
export GOPATH="$HOME/go"

if [[ $(uname) == "Darwin" ]]; then
  source "$HOME/.zshrc_mac"
else
  source "$HOME/.zshrc_linux"
fi

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git zoxide mise npm ssh tmuxinator vi-mode vscode dotenv fzf docker node)

source $ZSH/oh-my-zsh.sh

# User configuration

export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

export EDITOR='nvim'

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# Exports
export ASDF_DIR="$HOME/.asdf"
export ASDF_DATA_DIR="$HOME/.asdf"
export PATH="$PATH:$HOME/bin"
export PATH="$HOME/.local/bin:$PATH"
export PATH="$GOPATH/bin:$PATH"

bindkey -v

# Aliases

## Git
alias ls="eza"
alias gs="git status"
alias gc="git commit"
alias ga="git add"
alias gcl="git clone"
alias gd="git diff"
alias gl="git log --pretty=tformat:\"%C(yellow)%h %C(cyan)%ad %Cblue%an%C(auto)%d %Creset%s\" --graph --date=format:\"%Y-%m-%d %H:%M\""
alias gcan="git commit --amend --no-edit"
alias gca="git commit --amend"
alias gpf="git push -f"
alias gcaan="git commit -a --amend --no-edit && git push -f"
alias upkan="gc -a -m \"update kanbans\" && git push"

## Jujutsu

alias jjd="jj describe -m"
alias jjn="jj new"
### forward bookmark to commit previous to working copy
alias jjmv="jj bookmark move --from 'heads(::@- & bookmarks())' --to @-"

## Misc
alias jq-less="jq -C '.' | less -R"
alias remind="tasks remind"
alias vim=nvim
alias tat="tmux attach-session -t"
alias mux="tmuxinator"

## Navigation
alias "cd ..."="cd ../.."
alias "cd ...."="cd ../../.."
alias "cd ....."="cd ../../../.."
alias "cd ......"="cd ../../../../.."

eval "$(mise activate zsh)"
eval "$(zoxide init zsh)"

source ~/.env

# jj autocompletion
source <(COMPLETE=zsh jj)

# opencode
export PATH=$HOME/.opencode/bin:$PATH
