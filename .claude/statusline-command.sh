#!/bin/bash
# Claude Code status line — model, directory, git branch, repo/PR, context bar, lines changed
INPUT=$(cat)
# Single jq pass — one field per line, positional (empty lines preserved)
i=0; while IFS= read -r line; do F[$i]="$line"; i=$((i+1)); done < <(printf '%s' "$INPUT" | jq -r '[
  .model.display_name // "Claude",
  (.workspace.current_dir // .cwd),
  (.cost.total_cost_usd // 0),
  (.cost.total_lines_added // 0),
  (.cost.total_lines_removed // 0),
  (.workspace.repo | if . then .owner + "/" + .name else "" end),
  (.pr.number // ""),
  (.pr.review_state // "open"),
  (.context_window.used_percentage // 0)
] | .[]')
MODEL=${F[0]}; CWD=${F[1]}; COST=${F[2]}; ADDED=${F[3]}; REMOVED=${F[4]}
REPO=${F[5]}; PR_NUM=${F[6]}; PR_STATE=${F[7]}; CTX_RAW=${F[8]}
DIR=$(basename "$CWD")
BRANCH=$(cd "$CWD" 2>/dev/null && git --no-optional-locks branch --show-current 2>/dev/null)
# Drop repo name when it just echoes the dir
[ "${REPO##*/}" = "$DIR" ] && REPO=""
# caveman plugin badge — cache the rendered string, keyed on the two flag-file mtimes.
# Badge only changes when .caveman-active / .caveman-statusline-suffix change, so on a
# cache hit we skip the glob + bash subprocess entirely. No flag file → no badge, short-circuit.
CAVEMAN_BADGE=""
CM_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CM_FLAG="$CM_DIR/.caveman-active"
if [ -f "$CM_FLAG" ]; then
  CM_KEY=$(stat -f '%Fm' "$CM_FLAG" "$CM_DIR/.caveman-statusline-suffix" 2>/dev/null | tr '\n' '-')
  CM_CACHE="$CM_DIR/.statusline-caveman-cache"
  if [ -f "$CM_CACHE" ] && [ "$(head -n1 "$CM_CACHE")" = "$CM_KEY" ]; then
    CAVEMAN_BADGE=$(tail -n +2 "$CM_CACHE")
  else
    CM_SCRIPT=$(ls "$HOME/.claude/plugins/cache/caveman/caveman/"*/src/hooks/caveman-statusline.sh 2>/dev/null | head -n1)
    [ -n "$CM_SCRIPT" ] && [ -f "$CM_SCRIPT" ] && CAVEMAN_BADGE=$(bash "$CM_SCRIPT" 2>/dev/null)
    printf '%s\n%s' "$CM_KEY" "$CAVEMAN_BADGE" > "$CM_CACHE"
  fi
fi
CTX=$(printf '%.0f' "$CTX_RAW")
BAR_WIDTH=10
FILLED=$(( CTX * BAR_WIDTH / 100 ))
EMPTY=$(( BAR_WIDTH - FILLED ))
if [ "$CTX" -lt 50 ]; then BAR_COLOR="\033[32m"
elif [ "$CTX" -lt 75 ]; then BAR_COLOR="\033[33m"
else BAR_COLOR="\033[31m"; fi
BAR="${BAR_COLOR}$(printf '%*s' "$FILLED" '' | tr ' ' '█')$(printf '%*s' "$EMPTY" '' | tr ' ' '░')\033[0m"
printf "\033[1m%s\033[0m in \033[36m%s\033[0m" "$MODEL" "$DIR"
[ -n "$BRANCH" ] && printf " on \033[33m⎇ %s\033[0m" "$BRANCH"
[ -n "$REPO" ] && printf " \033[2m(%s)\033[0m" "$REPO"
[ -n "$PR_NUM" ] && printf " \033[35mPR #%s (%s)\033[0m" "$PR_NUM" "$PR_STATE"
[ -n "$CAVEMAN_BADGE" ] && printf " %s" "$CAVEMAN_BADGE"
printf " · ${BAR} %s%%" "$CTX"
awk "BEGIN{exit !($COST>0)}" && printf " · \033[38;5;220m\$%.2f\033[0m" "$COST"
if [ "$ADDED" -gt 0 ] || [ "$REMOVED" -gt 0 ]; then
  printf " · \033[32m+%s\033[0m \033[31m-%s\033[0m" "$ADDED" "$REMOVED"
fi
echo
