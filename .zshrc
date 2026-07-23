# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:/usr/local/bin:$HOME/.docker/cli-plugins:$HOME/.krew/bin:$HOME/.local/bin:$HOME/go/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
DISABLE_MAGIC_FUNCTIONS="true"

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
ZSH_CUSTOM=~/.oh-my-zsh-custom

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(brew mise git vi-mode aliases common-aliases docker fzf gh golang terraform vscode fzf-tab zsh-autosuggestions fast-syntax-highlighting zsh-history-substring-search eza uv helm kubectl)

# Add zsh-completions to fpath BEFORE sourcing oh-my-zsh (to avoid double compinit)
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/completions
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src
typeset -U fpath  # Ensure no duplicates in fpath

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi
export EDITOR='vim'

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

# If there's already a kubeconfig file in ~/.kube/config it will import that too and all the contexts
#DEFAULT_KUBECONFIG_FILE="$HOME/.kube/config"
#if test -f "${DEFAULT_KUBECONFIG_FILE}"
#then
#  export KUBECONFIG="$DEFAULT_KUBECONFIG_FILE"
#fi
# Your additional kubeconfig files should be inside ~/.kube/
# Use zsh globbing instead of find - much faster, no external process
#for kubeconfigFile in ~/.kube/(dev-*.yaml|kubeconfig.*.yml|kubeconfig.*.yaml|config.*.yaml|teleport-*.yaml|oidc-*.yaml)(N); do
#  export KUBECONFIG="$kubeconfigFile:$KUBECONFIG"
#done

# Completion stuff
# Uncomment if you need bash completions for tools that don't have zsh completions
# autoload -U +X bashcompinit && bashcompinit

# Tool-specific completions (uncomment as needed)
compdef _kubectl kubecolor

# Enhanced completion styling
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"  # Use LS_COLORS for file completions
zstyle ':completion:*' group-name ''                      # Group completions by type
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'  # Add category headers

#Something to import libraries from homebrew
#export LD_LIBRARY_PATH="$HOMEBREW_PREFIX/lib:$LD_LIBRARY_PATH"
export HOMEBREW_GITHUB_API_TOKEN=

# No, Homebrew
export HOMEBREW_NO_ANALYTICS=1

# Disable teleport SSH agent stuff
export TELEPORT_USE_LOCAL_SSH_AGENT=false

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Disable error on unmatched *
setopt no_nomatch

[[ "$TERM_PROGRAM" == "vscode" ]] && . "/Applications/Visual Studio Code.app/Contents/Resources/app/out/vs/workbench/contrib/terminal/common/scripts/shellIntegration-rc.zsh"

# Change zsh autosuggestions behavior to only trigger on manual rebind (e.g. Ctrl+Space) ??
ZSH_AUTOSUGGEST_MANUAL_REBIND=1

# CoreWeave Netskope SSL fix — combined CA bundle for Node.js, Go and Python tools (re-run setup.sh to refresh)
export NODE_EXTRA_CA_CERTS="/Users/cprivitere/.certs/ca-bundle.pem"
export SSL_CERT_FILE="/Users/cprivitere/.certs/ca-bundle.pem"
export REQUESTS_CA_BUNDLE="/Users/cprivitere/.certs/ca-bundle.pem"

# Source Coreweave teleport helpers
[[ -f $HOME/coreweave/cw-fleet-tools/scripts/teleport/helpers/tls ]] && source $HOME/coreweave/cw-fleet-tools/scripts/teleport/helpers/tls
[[ -f $HOME/coreweave/cw-fleet-tools/scripts/teleport/helpers/tlk ]] && source $HOME/coreweave/cw-fleet-tools/scripts/teleport/helpers/tlk


# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/cprivitere/.lmstudio/bin"
# End of LM Studio CLI section


# pnpm
export PNPM_HOME="/Users/cprivitere/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end
alias cavemem="node /Users/cprivitere/coreweave/cavemem/apps/cli/dist/index.js"
