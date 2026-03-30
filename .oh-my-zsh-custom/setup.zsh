# ============================================================================
# ZSH CUSTOM SETUP & COMPILATION UTILITIES
# ============================================================================

zcompile-many() {
  local f
  for f; do zcompile -R -- "$f".zwc "$f" || echo "zcompile failed to compile $f" >&2; done
}

# Usage: _process_plugin <path> <url> <compile_file> <mode>
_process_plugin() {
  local custom_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}"
  local rel_path="$1"
  local url="$2"
  local compile_file="$3"
  local mode="${4:-update}"

  local full_path="$custom_dir/$rel_path"

  case "$mode" in
    setup)
      if [[ ! -e "$full_path" ]]; then
        echo "Cloning $(basename $rel_path)..."
        git clone --depth=1 "$url" "$full_path"
        [[ "$rel_path" == "themes/powerlevel10k" ]] && make -C "$full_path" pkg 2>/dev/null
      fi
      return 0
      ;;
    update)
      if [[ -d "$full_path/.git" ]]; then
        local before=$(git -C "$full_path" rev-parse HEAD 2>/dev/null)
        git -C "$full_path" pull --quiet --rebase || echo "Warning: update failed for $(basename $rel_path)" >&2
        local after=$(git -C "$full_path" rev-parse HEAD 2>/dev/null)
        [[ "$before" != "$after" ]] && return 0  # Signal that update happened
      fi
      return 1
      ;;
    compile)
      if [[ -n "$compile_file" && -f "$full_path/$compile_file" ]]; then
        zcompile-many "$full_path/$compile_file"
      fi
      return 0
      ;;
  esac
}

_for_each_plugin() {
  local mode="$1"
  local callback="${2:-_process_plugin}"

  $callback "plugins/fast-syntax-highlighting" "https://github.com/zdharma-continuum/fast-syntax-highlighting.git" "fast-syntax-highlighting.plugin.zsh" "$mode"
  $callback "plugins/zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions.git" "zsh-autosuggestions.zsh" "$mode"
  $callback "plugins/zsh-completions" "https://github.com/zsh-users/zsh-completions.git" "zsh-completions.plugin.zsh" "$mode"
  $callback "themes/powerlevel10k" "https://github.com/romkatv/powerlevel10k.git" "" "$mode"
}

_compile_plugins() {
  local clean="${1:-false}"

  if [[ "$clean" = true ]]; then
    local custom_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}"
    rm -f "$custom_dir"/{plugins,themes}/*/*.zwc 2>/dev/null
  fi

  _for_each_plugin compile
}

# Compile zsh custom scripts for faster loading
compilecustom() {
  echo "Compiling custom zsh scripts..."
  local custom_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}"

  echo "  Cleaning existing compiled files..."
  for file in "$custom_dir"/*.zsh(N); do
    rm -f "${file}.zwc"
    echo "  Compiling $(basename $file)..."
    zcompile-many "$file"
  done

  _compile_plugins true
  _compile_local_bin true

  echo "✓ Compilation complete!"
}

# Update everything: Homebrew, plugins, themes, and oh-my-zsh
upallthethings() {
  (
    echo "=== Updating Homebrew ==="
    brew update
    brew outdated
    brew upgrade
    brew cleanup

    echo -e "\n=== Cleaning old compiled files ==="
    fd -i -I --glob -H \*.zwc ~/.oh-my-zsh-custom -x rm
    fd -d 2 -i -I --glob -H \*.zwc ${HOME:-/tmp} -x rm

    echo -e "\n=== Updating plugins ==="
    _for_each_plugin update

    echo -e "\n=== Updating oh-my-zsh ==="
    cd ~ && omz update

    echo -e "\n=== Updating mise ==="
    cd ~ && mise up

    echo -e "\n=== Updating Go binaries with gup ==="
    cd ~ && gup update

    echo -e "\n=== Updating cw ==="
    cd ~ && cw update

    echo -e "\n=== Updating claude ==="
    cd ~ && claude update

    echo -e "\n=== Recompiling everything ==="
    compilecustom

    echo -e "\n✓ All updates complete! Reload your shell with: omz reload"
  )
}

# Initial setup - clones plugins if they don't exist
setupcustom() {
  echo "=== Setting up custom plugins ==="
  _for_each_plugin setup

  echo -e "\n✓ Setup complete! Now compiling..."
  compilecustom
  echo -e "\nReload your shell with: exec zsh"
}

_compile_local_bin() {
  local clean="${1:-false}"
  local local_bin="$HOME/.local/bin"
  [[ -d "$local_bin" ]] || return 0

  [[ "$clean" = true ]] && rm -f "$local_bin"/*.zwc 2>/dev/null

  for file in "$local_bin"/*(N-.x); do
    # Only compile files with a zsh shebang
    [[ $(head -1 "$file" 2>/dev/null) == *zsh* ]] || continue
    if [[ "$clean" = true || ! -f "${file}.zwc" || "$file" -nt "${file}.zwc" ]]; then
      zcompile-many "$file"
    fi
  done
}

_autocompile_custom() {
  local custom_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}"

  for file in "$custom_dir"/*.zsh(N); do
    if [[ ! -f "${file}.zwc" || "$file" -nt "${file}.zwc" ]]; then
      zcompile-many "$file"
    fi
  done

  _compile_local_bin
}

_autoupdate_custom_plugins() {
  local update_file="${ZSH_CACHE_DIR:-$HOME/.cache/oh-my-zsh}/.zsh-custom-update"
  local epoch_target=1  # daily, matches omz update frequency

  if [[ -f "$update_file" ]]; then
    local last_update=$(cat "$update_file")
    local current_epoch=$(( $(date +%s) / 86400 ))
    if (( current_epoch - last_update < epoch_target )); then
      return 0
    fi
  fi

  # Claim the update slot immediately so concurrent shells skip it
  echo $(( $(date +%s) / 86400 )) > "$update_file"

  _for_each_plugin setup

  _custom_updated=false
  _update_check() {
    _process_plugin "$@" && _custom_updated=true
  }
  _for_each_plugin update _update_check
  unset -f _update_check

  if [[ "$_custom_updated" = true ]]; then
    _compile_plugins
    rm -f ~/.zcompdump* 2>/dev/null
  fi
  unset _custom_updated
}

_autocompile_custom
_autoupdate_custom_plugins &!
