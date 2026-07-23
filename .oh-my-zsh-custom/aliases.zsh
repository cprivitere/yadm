# ============================================================================
# GENERAL ALIASES & CONFIGURATION
# ============================================================================

# Tool aliases
alias tf=terraform
alias kns=kubens
alias kctx=kubectx
alias cat='bat --paging=never -p'
node-root() {
  _node="${1:?Usage: node_root <node-name>}"
  kubectl run node-root --restart=Never --rm -it --image=alpine --privileged \
    --overrides "{\"spec\":{\"hostPID\":true,\"nodeName\":\"${_node}\"}}" \
    --override-type=merge \
    --command -- nsenter --mount=/proc/1/ns/mnt -- /bin/bash
}

# Man page configuration
export MANPAGER="env BATMAN_IS_BEING_MANPAGER=yes /bin/bash batman"
export MANROFFOPT="-c"

# Load kubectl aliases if available
[ -f ~/.kubectl_aliases ] && source ~/.kubectl_aliases

# Shell completions via eval (runs in interactive shell so shell detection works correctly)
if [[ -o interactive ]]; then
  command -v infractl &>/dev/null && eval "$(infractl completion 2>/dev/null)" 2>/dev/null || true
  command -v cwctl &>/dev/null && eval "$(cwctl completion zsh 2>/dev/null)" 2>/dev/null || true
  command -v stern &>/dev/null && eval "$(stern completion zsh 2>/dev/null)" 2>/dev/null || true
fi

# has kubectl && . <(kubectl completion zsh) && compdef _kubectl kubectl && compdef _kubectl k && compdef _kubectl kubecolor
# has gh && . <(gh completion -s zsh) && compdef _gh gh
# has op && . <(op completion zsh) && compdef _op op
