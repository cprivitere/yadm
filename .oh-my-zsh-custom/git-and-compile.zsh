#if [[ -z ${TMUX+X}${ZSH_SCRIPT+X}${ZSH_EXECUTION_STRING+X} ]]; then
#  exec tmux
#fi

#if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
#  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
#fi

function zcompile-many() {
  local f
  for f; do zcompile -R -- "$f".zwc "$f"; done
}

if [[ ! -e ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/fast-syntax-highlighting ]]; then
  git clone --depth=1 https://github.com/zdharma-continuum/fast-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/fast-syntax-highlighting
  zcompile-many ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh
fi
if [[ ! -e ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-syntax-highlighting ]]; then
  git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-syntax-highlighting
  zcompile-many ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-syntax-highlighting/{zsh-syntax-highlighting.zsh,highlighters/*/*.zsh}
fi
if [[ ! -e ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-autosuggestions ]]; then
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-autosuggestions
  zcompile-many ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-autosuggestions/{zsh-autosuggestions.zsh,src/**/*.zsh}
fi
if [[ ! -e ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-autocomplete ]]; then
  git clone --depth=1 https://github.com/marlonrichert/zsh-autocomplete.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-autocomplete
  zcompile-many ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh
fi
if [[ ! -e ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/themes/powerlevel10k ]]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/themes/powerlevel10k
  make -C ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/themes/powerlevel10k pkg
fi

autoload -Uz compinit
compinit -C

[[ ~/.zcompdump.zwc -nt ~/.zcompdump ]] || zcompile-many ~/.zcompdump
#[[ ~/.zshenv.zwc    -nt ~/.zshenv    ]] || zcompile-many ~/.zshenv
[[ ~/.zshrc.zwc     -nt ~/.zshrc     ]] || zcompile-many ~/.zshrc
[[ ~/.p10k.zsh.zwc  -nt ~/.p10k.zsh  ]] || zcompile-many ~/.p10k.zsh
[[ ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh.zwc -nt ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] || zcompile-many ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-syntax-highlighting/{zsh-syntax-highlighting.zsh,highlighters/*/*.zsh}
[[ ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh.zwc -nt ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] || zcompile-many ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-autosuggestions/{zsh-autosuggestions.zsh,src/**/*.zsh}
[[ ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh.zwc -nt ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh ]] || zcompile-many ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh 
[[ ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh.zwc -nt ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh ]] || zcompile-many ${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh
[[ ${ZSH:-$HOME/.oh-my-zsh}/oh-my-zsh.sh.zwc -nt ${ZSH:-$HOME/.oh-my-zsh}/oh-my-zsh.sh ]] || zcompile-many ${ZSH:-$HOME/.oh-my-zsh}/oh-my-zsh.sh

unfunction zcompile-many

ZSH_AUTOSUGGEST_MANUAL_REBIND=1

#source ~/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
#source ~/zsh-autosuggestions/zsh-autosuggestions.zsh
#source ~/powerlevel10k/powerlevel10k.zsh-theme
#source ~/.p10k.zsh
