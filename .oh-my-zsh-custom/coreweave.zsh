# CONFIGURATION & CONSTANTS
# ============================================================================

# Configuration constants

# DNS domains for VPN
VPN_DNS_DOMAINS=(
  '~dev.internal.k8s' '~dev.tenant.k8s' '~dev.ngcp.k8s'
  '~dev.workload.k8s' '~dev.mgmt.k8s' '~dev.internal.ingress'
  '~dev.tenant.ingress' '~coreweave.test' '~knative.dev.cloud'
  '~us-dev-01a.int.coreweave.com' '~us-dev-01a.coreweave.com'
)

# Teleport roles
TELEPORT_ROLES_CLUSTER="cpx-cluster-super-admin-resource-access"
TELEPORT_ROLES_LAB="us-lab-01c-super-admin-elevated-access"

# SOCKS proxy port for chrome_proxy
SOCKS_PROXY_PORT=9999

# Proxy bypass list for chrome_proxy
PROXY_NO_PROXY="localhost,127.0.0.0/8,::1,www.*,google.*,docs.*,graphana.*,awx.*,slack*,login.*,git*,teleport.*,vault.,okta.,chat.*,mail.*,notion.*,coreweave.*,*.com,*.org,*.net,*.so,10.37.0.0/16,10.39.0.0/16,10.61.0.0/16,10.65.0.0/16,10.31.0.0/16,10.35.0.0/16"

# ============================================================================
# HELPER FUNCTIONS (Internal - prefixed with _)
# ============================================================================

# Extract region code from cluster name
# Usage: _extract_region "teleport.na.int.coreweave.com"
# Returns: "na"
_extract_region() {
  echo "$1" | sed -e 's/teleport\.//g' -e 's/\.int\.coreweave\.com.*//g'
}

# Get Teleport cluster name by region
# Usage: _get_teleport_cluster "na"
# Returns: full cluster name
_get_teleport_cluster() {
  local region="$1"
  tsh clusters -f yaml | yq '.[].cluster_name' | grep "$region"
}

# Get currently selected Teleport cluster
# Returns: cluster name
_get_current_teleport_cluster() {
  tsh clusters -f json 2>/dev/null | yq '.[] | select(.selected == true) | .cluster_name'
}

# ----------------------------------------------------------------------------
# Teleport access-request helpers (shared by tp-request-* / tp-kubevirt*)
# ----------------------------------------------------------------------------

# Pull a dry-run/echo flag (-n|--dry-run|--echo) out of an arg list.
# Sets globals: _TP_DRY_RUN (0|1), _TP_ARGS (remaining args, spaces preserved).
# Usage: _tp_filter_dryrun "$@"; set -- "${_TP_ARGS[@]}"; local dry_run=$_TP_DRY_RUN
_tp_filter_dryrun() {
  _TP_DRY_RUN=0
  _TP_ARGS=()
  local a
  for a in "$@"; do
    case "$a" in
      -n|--dry-run|--echo) _TP_DRY_RUN=1 ;;
      *) _TP_ARGS+=("$a") ;;
    esac
  done
}

# Pick the Teleport role for a cluster: lab clusters (*-lab-*) get the lab role,
# everything else gets the standard cpx cluster role.
# Usage: _tp_roles_for_cluster <kube-cluster-name>
_tp_roles_for_cluster() {
  case "$1" in
    *-lab-*) echo "$TELEPORT_ROLES_LAB" ;;
    *)       echo "$TELEPORT_ROLES_CLUSTER" ;;
  esac
}

# Resolve a CKS cluster name to its Teleport kube_cluster_name via label query.
# Usage: _tp_resolve_kube_cluster <kube-cluster-name> [teleport-cluster]
# Prints the single match; errors (stderr, return 1) on zero or multiple matches.
_tp_resolve_kube_cluster() {
  local kube_cluster="$1"
  local teleport_cluster="${2:-$(_get_current_teleport_cluster)}"
  local query="labels[\"cks.coreweave.com/cluster\"] == \"$kube_cluster\" || labels[\"cluster\"] == \"$kube_cluster\""
  local matches
  matches=$(TELEPORT_CLUSTER=$teleport_cluster tsh kube ls --query "$query" -f yaml | yq '.[] | .kube_cluster_name')

  if [ -z "$matches" ]; then
    echo "Error: no Teleport kube cluster matched \"$kube_cluster\"" >&2
    return 1
  fi
  if [ "$(printf '%s\n' "$matches" | grep -c .)" -gt 1 ]; then
    echo "Error: query matched multiple clusters, refine \"$kube_cluster\":" >&2
    echo "$matches" >&2
    return 1
  fi
  echo "$matches"
}

# Create a Teleport access request, or echo the command when dry-run is set.
# Usage: _tp_request_create <dry_run:0|1> <roles> <reason> <resource-arg...>
_tp_request_create() {
  local dry_run="$1" roles="$2" reason="$3"
  shift 3
  local cmd=(tsh request create "$@" --roles "$roles" --reason "$reason")
  if [ "$dry_run" = "1" ]; then
    print -r -- "${(q)cmd[@]}"
    return 0
  fi
  "${cmd[@]}"
}

# Save current kubectl context and extract region/cluster
# Sets global variables: _saved_kube_cluster, _saved_region, _saved_cluster
_save_context() {
  _saved_kube_cluster=$($actual_kubectl_ctx -c)
  _saved_region=$(_extract_region "$_saved_kube_cluster")
  _saved_cluster=$(_get_teleport_cluster "$_saved_region")
}

# Restore previously saved context
# Requires: _saved_cluster to be set
_restore_context() {
  if [[ -n "${_saved_cluster:-}" ]]; then
    tsh login "$_saved_cluster"
  fi
}

# Get node metadata using yanl
# Usage: _get_node_metadata <node_name>
# Returns: deviceslot|serial separated by pipe
_get_node_metadata_from_yanl() {
  node_name="$1"
  cluster=$(yanl -o cluster "${node_name}")
  deviceslot=$(yanl -o deviceslot "${node_name}")
  serial=$(yanl -o node_serial "${node_name}")
  region=$(yanl -o region "${node_name}")
  echo "${cluster}|${deviceslot}|${serial}|${region}"
}


# ============================================================================
# EXPORTS & ENVIRONMENT
# ============================================================================

export TELEPORT_PROXY_NA="teleport.na.int.coreweave.com:443"
export GOPRIVATE='github.com/coreweave/*,bsr.core-services.ingress.coreweave.com/*'

# Yanl metrics datasource
export YANL_DATA_SOURCE_URIS="http://vmui.us-east.int.coreweave.com/select/0/prometheus,http://vmui.eu-south.int.coreweave.com/select/0/prometheus,http://vmui.us-west.int.coreweave.com/select/0/prometheus,http://vmui.us-lab.int.coreweave.com/select/0/prometheus"

# VPN STUFF

vpn-start() {
  local VPN_CONFIG_FILE=${1:-~/.config/openvpn3/dev-cluster.ovpn}
  [[ ! -e "$VPN_CONFIG_FILE" ]] &&
    echo "VPN Config file not found: $VPN_CONFIG_FILE" && return 1
  openvpn3 session-start --config "$VPN_CONFIG_FILE"
}

vpn-stop() {
  for session_path in $(openvpn3 sessions-list | awk "{ if(\$0 ~ /Path:/){print \$2} else if(\$0 ~ /No sessions available/){print \"none\"} }"); do
    if [[ "${session_path}" =~ ^none$ ]]; then
      echo "No sessions available";
    else echo openvpn3 session-manage --disconnect --session-path $session_path; openvpn3 session-manage --disconnect --session-path "${session_path}"
    fi
  done
  openvpn3 session-manage --cleanup; unset session_path
}

vpn-list() {
  openvpn3 sessions-list
}

vpn-reset() {
  local session_path="$(openvpn3 sessions-list | awk "{ if(\$0 ~ /Path:/){print \$2} else if(\$0 ~ /No sessions available/){print \"none\"} }")"
  if [[ "${session_path}" -eq "none" ]]; then
    vpn-start
  elif [[ $(echo "${session_path}" | wc -l) -eq 1 ]]; then
    openvpn3 session-manage --restart --path "${session_path}"
  else
    vpn-stop && vpn-start
  fi
}

vpn-set-ip() {
    local IP=$1
    local VPN_CONFIG_FILE=${2:-~/.config/openvpn3/dev-cluster.ovpn}
    [[ -z "$IP" ]] && echo No IP given && return 1
    [[ ! -e "$VPN_CONFIG_FILE" ]] &&
      echo "VPN Config file not found: $VPN_CONFIG_FILE" && return 1
    sed -E -i".bak" -e "s/^remote +([^ ]+)/remote $IP/" $VPN_CONFIG_FILE
    grep "^remote $IP" $VPN_CONFIG_FILE || {
        echo "IP Update Failed"
        return 1
    }
}

# ============================================================================
# KUBERNETES NODE MANAGEMENT
# ============================================================================

# Custom column definitions for node queries
local cluster="CLUSTER:metadata.labels['cks\.coreweave\.com\/cluster']"
local cordon="CORDON:spec.unschedulable"
local k8sversion="K8SVER:status.nodeInfo.kubeletVersion"
local name="NAME:metadata.name"
local ncore="NCORE:metadata.labels['node\.coreweave\.cloud\/version']"
local node_ip="IP:status.addresses[?(@.type=='InternalIP')].address"
local node_type="TYPE:metadata.labels['node\.coreweave\.cloud\/type']"
local owner="INT-OWNER:metadata.labels['private\.coreweave\.cloud/internal-owner']"
local payload="PAYLOAD:metadata.labels['node\.coreweave\.cloud\/payload-version']"
local rack="RACK:metadata.labels['node\.coreweave\.cloud\/rack']"
local ready="READY:status.conditions[?(@.type=='Ready')].status"
local region="REGION:metadata.labels['topology\.kubernetes\.io\/region']"
local reserved="RESERVED:metadata.labels['node\.coreweave\.cloud\/reserved']"
local ru="RU:metadata.labels['node\.coreweave\.cloud\/rack-unit']"
local state="STATE:metadata.labels['node\.coreweave\.cloud\/state']"
local taint="TAINT:spec.taints[?(@)].effect"
local admincond="ADMINCOND:metadata.annotations['cwnc\.coreweave\.com\/admin-conditions']"
local draining="DRAINING:metadata.annotations['draino\.coreweave\.cloud\/draining']"

# Quick node view with common columns
alias nodes="k get nodes -o=custom-columns=\"${name},${node_ip},${ready},${cordon},${taint},${draining},${ncore},${payload},${k8sversion},${owner},${state},${reserved},${cluster},${rack},${ru}\""
alias nodes2="k get nodes -o=custom-columns=\"${name},${node_ip},${ready},${cordon},${taint},${owner},${state},${reserved},${cluster}\""

# Infractl aliases
alias ic="infractl"
alias icduty="infractl pagerduty tui --user-email cprivitere@coreweave.com"

# kubectl get nodes with multiple label columns safely
kgnl() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: kgnl <label-key1> [label-key2 ...] [-- extra kubectl options]"
    return 1
  fi

  local labels=()
  local extra_args=()
  local found_double_dash=false

  # Separate label keys from extra kubectl options (anything after --)
  for arg in "$@"; do
    if [[ "$arg" == "--" ]]; then
      found_double_dash=true
      continue
    fi

    if [[ "$found_double_dash" == false ]]; then
      labels+=("$arg")
    else
      extra_args+=("$arg")
    fi
  done

  # Build custom-columns string
  local cols="NAME:.metadata.name"
  for lbl in "${labels[@]}"; do
    local esc_key="${lbl//\./\\.}"
    esc_key="${esc_key//\//\\/}"
    local col_name=$(echo "$lbl" | awk -F/ '{print toupper($NF)}')
    cols+=",${col_name}:.metadata.labels['$esc_key']"
  done

  kubectl get nodes -o=custom-columns="$cols" "${extra_args[@]}"
}

# Check node conditions - shows only nodes with problems
kchecknodes() {
  kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.conditions[?(@.status=="True")]}{.type}{"\n"}{end}{"\n"}{end}' \
  | awk '
    BEGIN { RS="\n\n+"; FS="\n" }
    {
      for (i=2; i<=NF; i++) {
        if ($i != "Ready" && $i != "PhaseState" && $i != "PendingPhaseState" && $i != "CWActive" && $i != "CWRegistered") {
          print $0;
          print "";
          break
        }
      }
    }
  '
}

# Check for mismatches between Kubernetes nodes and Katalyst deviceslots
kcheckmismatch() {
  if [[ -z "${1:-}" ]]; then
    echo "Usage: kcheckmismatch <node-role>"
    return 1
  fi

  local node_role="$1"
  local NODE_IPS=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')

  kubectl get deviceslot -o json | jq -r ".items[] | select(.spec.node.role == \"$node_role\") | \"\(.metadata.name)\t\(.spec.node.ip.mgmt)\"" | \
  while read -r name ip; do
    if ! echo "$NODE_IPS" | grep -q -w "$ip"; then
      echo "Missing Node for katalyst deviceslot: $name (IP: $ip)"
    fi
  done
}


# ============================================================================
# TELEPORT ACCESS MANAGEMENT
# ============================================================================

# Quick login to Teleport region
tln() {
  local region="${1:-na}"
  local proxy="teleport.${region}.int.coreweave.com:443"
  local cluster="teleport.${region}.int.coreweave.com"

  if [[ "$region" == "na" ]]; then
    tsh login --proxy="$proxy" teleport
  else
    tsh login --proxy="$proxy" "$cluster"
  fi
}

# List available Kubernetes clusters in Teleport
tks() {
  tsh kube ls
}

# Login to a specific Kubernetes cluster
tkl() {
  if [ -z "$1" ]; then
    echo "Usage: tkl <cluster-name>"
    return 1
  fi
  tsh kube login "$1"
}

# Search for nodes in Teleport
tp-search-node() {
  if [ $# -eq 0 ]; then
    echo "Usage: tp-search-node <node-name> [<node-name> ...]"
    return 1
  fi

  for node in "$@"; do
    tsh ls -f json | jq -r ".[] | select(.spec.hostname == \"$node\") | .metadata.name"
    #tctl get nodes --format=json | jq -r ".[] | select(.spec.hostname == \"$node\") | .metadata.name"
  done
}

# Search for nodes in by cluster in Teleport
tp-search-nodes-in-cluster() {
  if [ $# -eq 0 ]; then
    echo "Usage: tp-search-nodes-in-cluster <cluster-name>"
    return 1
  fi

  #tsh ls -f names --query "labels[\"cks.coreweave.com/cluster\"] == \"${1}\""
  tsh ls -f json --query "labels[\"cks.coreweave.com/cluster\"] == \"${1}\"" | jq -r ".[].metadata.name"
  #tctl get nodes --format=json | jq -r ".[] | select(.spec.cmd_labels.\"cks.coreweave.com/cluster\".result == \"$1\") | .metadata.name"
}




# Search for clusters in Teleport (label query, matches tp-request-* style)
tp-search-cluster() {
  if [ -z "$1" ]; then
    echo "Usage: tp-search-cluster <cluster-name>"
    return 1
  fi

  local query="labels[\"cks.coreweave.com/cluster\"] == \"$1\" || labels[\"cluster\"] == \"$1\""
  TELEPORT_CLUSTER=$(_get_current_teleport_cluster) tsh kube ls --query "$query"
}

# Request access to kubevirt cluster (specific use case)
tp-kubevirt() {
  _tp_filter_dryrun "$@"
  set -- "${_TP_ARGS[@]}"
  local dry_run=$_TP_DRY_RUN

  if [ -z "$1" ]; then
    echo "Usage: tp-kubevirt [-n|--echo] <reason>"
    return 1
  fi

  local KUBE_CLUSTER="us-lab-01c-kubevirt"

  _tp_request_create "$dry_run" "$(_tp_roles_for_cluster "$KUBE_CLUSTER")" "$*" \
    --resource "/teleport/kube_cluster/${KUBE_CLUSTER}"
}

# Request access to kubevirt cluster and its nodes (specific use case)
tp-kubevirt-all() {
  _tp_filter_dryrun "$@"
  set -- "${_TP_ARGS[@]}"
  local dry_run=$_TP_DRY_RUN

  if [ -z "$1" ]; then
    echo "Usage: tp-kubevirt-all [-n|--echo] <reason>"
    return 1
  fi

  local KUBE_CLUSTER="us-lab-01c-kubevirt"

  local resources=(--resource "/teleport/kube_cluster/${KUBE_CLUSTER}")
  local node
  while IFS= read -r node; do
    [ -n "$node" ] || continue
    resources+=(--resource "/teleport/node/$node")
  done < <(tp-search-nodes-in-cluster "${KUBE_CLUSTER}")

  _tp_request_create "$dry_run" "$(_tp_roles_for_cluster "$KUBE_CLUSTER")" "$*" "${resources[@]}"
}

tp-request-namespace() {
  local USAGE="Usage: tp-request-namespace [-n|--echo] <cluster1> [cluster2 ...] -- <namespace1> [namespace2 ...] -- <reason>"
  local EXAMPLE="Example: tp-request-namespace us-east-03-internal us-east-04-internal -- calico-system kube-system -- \"Debugging pods\""

  _tp_filter_dryrun "$@"
  set -- "${_TP_ARGS[@]}"
  local dry_run=$_TP_DRY_RUN

  if [ -z "$1" ]; then
    echo "$USAGE"
    echo "$EXAMPLE"
    return 1
  fi

  local TELEPORT_CLUSTER
  TELEPORT_CLUSTER=$(_get_current_teleport_cluster)

  local KUBE_CLUSTERS=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    KUBE_CLUSTERS+=("$1")
    shift
  done
  [ "$1" = "--" ] && shift

  local NAMESPACES=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    NAMESPACES+=("$1")
    shift
  done
  [ "$1" = "--" ] && shift

  local REASON="$*"

  if [ ${#KUBE_CLUSTERS[@]} -eq 0 ]; then
    echo "Error: at least one cluster is required"
    echo "$USAGE"
    return 1
  fi
  if [ ${#NAMESPACES[@]} -eq 0 ]; then
    echo "Error: at least one namespace is required (separate clusters and namespaces with '--')"
    echo "$USAGE"
    return 1
  fi
  if [ -z "$REASON" ]; then
    echo "Error: Reason is required (did you forget the second '--'?)"
    echo "$USAGE"
    return 1
  fi

  local ALL_RESOURCES=()
  local ROLES=""
  local KUBE_CLUSTER CLUSTER NAMESPACE ROLE
  for KUBE_CLUSTER in "${KUBE_CLUSTERS[@]}"; do
    CLUSTER=$(_tp_resolve_kube_cluster "$KUBE_CLUSTER" "$TELEPORT_CLUSTER") || return 1
    ROLE=$(_tp_roles_for_cluster "$KUBE_CLUSTER")
    if [ -n "$ROLES" ] && [ "$ROLES" != "$ROLE" ]; then
      echo "Error: cannot mix lab and non-lab clusters in one request (different roles)" >&2
      return 1
    fi
    ROLES="$ROLE"
    for NAMESPACE in "${NAMESPACES[@]}"; do
      ALL_RESOURCES+=(--resource "/$TELEPORT_CLUSTER/namespace/$CLUSTER/$NAMESPACE")
    done
  done

  _tp_request_create "$dry_run" "$ROLES" "$REASON" "${ALL_RESOURCES[@]}"
}

# Request access to a cluster
tp-request-cluster() {
  _tp_filter_dryrun "$@"
  set -- "${_TP_ARGS[@]}"
  local dry_run=$_TP_DRY_RUN

  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: tp-request-cluster [-n|--echo] <kube-cluster-name> <reason>"
    return 1
  fi

  local TELEPORT_CLUSTER
  TELEPORT_CLUSTER=$(_get_current_teleport_cluster)

  local KUBE_CLUSTER=$1
  shift

  local CLUSTER
  CLUSTER=$(_tp_resolve_kube_cluster "$KUBE_CLUSTER" "$TELEPORT_CLUSTER") || return 1

  _tp_request_create "$dry_run" "$(_tp_roles_for_cluster "$KUBE_CLUSTER")" "$*" \
    --resource "/$TELEPORT_CLUSTER/kube_cluster/$CLUSTER"
}

# Request access to a cluster and its nodes
tp-request-cluster-and-friends() {
  _tp_filter_dryrun "$@"
  set -- "${_TP_ARGS[@]}"
  local dry_run=$_TP_DRY_RUN

  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: tp-request-cluster-and-friends [-n|--echo] <kube-cluster-name> <reason>"
    return 1
  fi

  local TELEPORT_CLUSTER
  TELEPORT_CLUSTER=$(_get_current_teleport_cluster)

  local KUBE_CLUSTER=$1
  shift

  local CLUSTER
  CLUSTER=$(_tp_resolve_kube_cluster "$KUBE_CLUSTER" "$TELEPORT_CLUSTER") || return 1

  local RESOURCES=(--resource "/$TELEPORT_CLUSTER/kube_cluster/$CLUSTER")
  local node
  while IFS= read -r node; do
    [ -n "$node" ] || continue
    RESOURCES+=(--resource "/$TELEPORT_CLUSTER/node/$node")
  done < <(tp-search-nodes-in-cluster "$KUBE_CLUSTER")

  _tp_request_create "$dry_run" "$(_tp_roles_for_cluster "$KUBE_CLUSTER")" "$*" "${RESOURCES[@]}"
}

# Create SSH access request for nodes
tp-request-ssh() {
  _tp_filter_dryrun "$@"
  set -- "${_TP_ARGS[@]}"
  local dry_run=$_TP_DRY_RUN

  if [ $# -lt 2 ]; then
    echo "Usage: tp-request-ssh [-n|--echo] \"<reason>\" <node-name> [<node-name> ...]"
    echo "Note: Put the reason in quotes as the first argument"
    return 1
  fi

  local reason="$1"
  shift

  local args=()
  local found_nodes=0

  for node in "$@"; do
    local node_id
    node_id="/teleport/node/$(tp-search-node "$node")"

    if [ -z "$node_id" ]; then
      echo "Error: Node '$node' not found."
      continue
    fi

    echo "Found node: $node (ID: $node_id)"
    args+=(--resource="$node_id")
    ((found_nodes++))
  done

  if [ $found_nodes -eq 0 ]; then
    echo "No valid nodes found. Request not created."
    return 1
  fi

  echo "Creating request for $found_nodes nodes with reason: '$reason'"
  _tp_request_create "$dry_run" "$TELEPORT_ROLES_CLUSTER" "$reason" "${args[@]}"
}

# ============================================================================
# KUBECTL CONTEXT INTEGRATION
# ============================================================================

actual_kubectl_ctx=$(whereis kubectl-ctx | awk '{print $2}')

# Wrap kubectl-ctx to auto-login to Teleport
#kubectl-ctx() {
#  $actual_kubectl_ctx "$@"
#
#  local kube_cluster=$($actual_kubectl_ctx -c)
#  local region=$(_extract_region "$kube_cluster")
#  local cluster=$(_get_teleport_cluster "$region")
#
#  tsh login "$cluster"
#}
#
#alias kctx="kubectl-ctx"
#
## Login to all Teleport clusters and all kube clusters
#tlogin() {
#  tsh logout
#  echo "Logging in to North American teleport"
#  tsh login --proxy=$TELEPORT_PROXY_NA --auth=okta
#
#  local clusters=$(tsh clusters -f yaml | yq '.[].cluster_name')
#  for cluster in $(echo $clusters); do
#    tsh login "$cluster"
#    local kube_clusters=$(tsh kube ls -f yaml | yq '.[].kube_cluster_name')
#    for kube_cluster in $(echo $kube_clusters); do
#      tsh kube login "$kube_cluster"
#    done
#  done
#
#  kubectl-ctx
#}

# Teleport Request NameSpace - Interactive namespace access request
trns() {
  local kube_cluster=$(kubectx -c)
  local region=$(_extract_region "$kube_cluster")
  local cluster=$(_get_teleport_cluster "$region")
  local kube_cluster_without_url=$(echo $kube_cluster | rev | cut -d. -f 1 | rev | cut -d- -f 2-)

  tsh login "$cluster"

  # Interactive namespace selection
  local namespaces=$(tsh request search --kind=namespace | head -n -5 | tail -n+3 | awk '{print $1}')
  local namespace=$(echo "$namespaces" | fzf --height 20% --prompt "Select a namespace: ")

  # Interactive role selection
  local role=$(printf '%s\n' "${TELEPORT_ROLES_NAMESPACE[@]}" | fzf --height 20% --prompt "Select a role: ")

  # Check for existing approved request (state == 2)
  local request_id=$(tsh request ls --format=json | jq -r '(.[] | select(.spec.state == 2 and .spec.resource_ids[].kind == "namespace")) | .metadata.name' 2>/dev/null | tail -n 1)

  if [[ "$request_id" == "null" ]] || [[ -z "$request_id" ]]; then
    local reason=""
    vared -p 'Please provide a justification for your request: ' reason
    tsh request create --resource "/$cluster/namespace/$kube_cluster_without_url/$namespace" --roles="$role" --reason="$reason"
    kubectl-ns "$namespace"

    # Get the newly created request ID
    request_id=$(tsh request ls --format=json | jq -r '(.[] | select(.spec.state == 2 and .spec.resource_ids[].kind == "namespace")) | .metadata.name' 2>/dev/null | tail -n 1)
  fi

  tsh login "$cluster" --request-id="$request_id"
}

# Jump to a bare metal jumpbox
jump() {
  _save_context

  tsh login teleport

  local bmjb=""
  if [ $# -eq 0 ]; then
    local bmjbs=$(tsh ls | grep metal-jump | awk '{print $1}')
    bmjb=$(echo "$bmjbs" | fzf --height 20% --prompt "Select a jump box: ")
  else
    local region=$1
    bmjb=$(tsh ls | grep metal-jump | grep "$region" | awk '{print $1}')
    echo "Selected jumpbox: $bmjb"
  fi

  tsh ssh acc@$bmjb
  _restore_context
}

# Start Chrome with SOCKS proxy through jumpbox
chrome_proxy() {
  _save_context

  tsh login teleport
  pkill -2 chrome
  pkill tsh

  local bmjbs=$(tsh ls | grep metal-jump | awk '{print $1}')
  local bmjb=$(echo "$bmjbs" | fzf --height 20% --prompt "Select a jump box: ")

  sleep 4
  tsh ssh -D $SOCKS_PROXY_PORT -N acc@$bmjb &>/dev/null & disown

  export http_proxy="socks5://127.0.0.1:$SOCKS_PROXY_PORT"
  export https_proxy="socks5://127.0.0.1:$SOCKS_PROXY_PORT"
  export no_proxy="$PROXY_NO_PROXY"

  google-chrome-stable --password-store=gnome --proxy-server="$https_proxy" --proxy-bypass-list="$no_proxy" &>/dev/null & disown

  unset http_proxy https_proxy no_proxy

  _restore_context
}


# ============================================================================
# INFRASTRUCTURE UTILITIES
# ============================================================================

# Generate DPU cable reseat request message
# Helper: Get node info in pipe-delimited format
_get_node_info() {
  local node_name=$1
  local metadata_result=$(_get_node_metadata_from_yanl "$node_name")
  IFS='|' read -r cluster deviceslot serial region <<< "$metadata_result"
  echo "$node_name|$cluster|$deviceslot|$serial|$region"
}

# Display node information
node-info() {
  if (( $# != 1 )); then
    echo "Usage: node-info <nodename>"
    return 1
  fi
  local node_name=$1
  IFS='|' read -r gmac cluster deviceslot serial region <<< "$(_get_node_info "$node_name")"
  cat << EOF
gmac: $gmac
cluster: $cluster
deviceslot: $deviceslot
serialnum: $serial
region: $region
EOF
}

# Generate DPU cable reseat request message
dpu-clean() {
  if (( $# < 2 )); then
    echo "Usage: dpu-clean <nodename> <dpu_port>"
    return 1
  fi
  local node_name=$1
  local dpu_port=${2:-}
  IFS='|' read -r gmac cluster deviceslot serial region <<< "$(_get_node_info "$node_name")"
  cat << EOF
cwctl ticket dct-action device "$gmac" \
  -m "Please clean and reseat both the cable and optic in $dpu_port on node: $gmac, deviceslot: $deviceslot, serial: $serial, cluster: $cluster." \
  -r "$region"
EOF
}

# Create DCT ticket for NVMe drive replacement
nvme-replace() {
  if (( $# != 3 )); then
    echo "Usage: nvme-replace <nodename> <drive> <driveserial>"
    return 1
  fi
  local node_name=$1
  local drive=$2
  local driveserial=$3
  local region=$4
  IFS='|' read -r gmac cluster deviceslot serial region <<< "$(_get_node_info "$node_name")"
  cat << EOF  
cwctl ticket dct-action device "$gmac" \
  -m "Failed NVMe ($drive) with serial $driveserial on node: $gmac, deviceslot: $deviceslot, serial: $serial. Node drained; please replace drive." \
  -r "$region"
EOF
}

# Delete pods from Calico
calico_pod_delete() {
  usage_text() {
    echo "Usage: calico_pod_delete [-d|--delete] [-c|--confirm] <calico_pod>"
    echo "  -d, --delete   Actually delete the pods (default is dry-run)"
    echo "  -c, --confirm  Skip confirmation prompt when deleting"
    return 1
  }

  delete=false
  confirm=false

  # Parse flags
  while [ $# -gt 0 ]; do
    case "$1" in
      -d|--delete)
        delete=true
        shift
        ;;
      -c|--confirm)
        confirm=true
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        echo "Unknown option: $1"
        usage_text
        return 1
        ;;
      *)
        break
        ;;
    esac
  done

  # Positional argument: calico_pod
  if [ $# -ne 1 ]; then
    usage_text
    return 1
  fi

  calico_pod=$1

  # Extract "namespace/pod" lines from logs.
  # Note: grep -P is not POSIX and may not exist everywhere. Use sed instead.
  pods=$(
    kubectl logs -n calico-system "$calico_pod" --tail=500 2>/dev/null \
      | sed -n 's/.*workload_id:"\([^"]*\)".*/\1/p' \
      | sort -u
  )

  if [ -z "$pods" ]; then
    echo "No pods found for deletion."
    return 0
  fi

  echo "The following pods were found:"
  echo "$pods" | while IFS= read -r i; do
    [ -n "$i" ] || continue
    namespace=$(printf '%s\n' "$i" | cut -d/ -f1)
    pod=$(printf '%s\n' "$i" | cut -d/ -f2)
    echo "- Namespace: $namespace, Pod: $pod"
  done

  if [ "$delete" != "true" ]; then
    echo
    echo "Dry run mode. No pods were deleted."
    echo "Use -d or --delete to actually delete them."
    return 0
  fi

  if [ "$confirm" != "true" ]; then
    echo
    printf "Are you sure you want to delete these pods? Type 'yes' to proceed: "
    IFS= read -r response
    if [ "$response" != "yes" ]; then
      echo "Aborted."
      return 0
    fi
  fi

  # Proceed with deletion
  echo "$pods" | while IFS= read -r i; do
    [ -n "$i" ] || continue
    namespace=$(printf '%s\n' "$i" | cut -d/ -f1)
    pod=$(printf '%s\n' "$i" | cut -d/ -f2)
    echo "Deleting pod $pod in namespace $namespace..."
    kubectl delete pod -n "$namespace" "$pod" --wait=false
  done

  echo "Deletion complete."
}

node-maintenance() {
if [ -z "$1" ]; then
    echo -e "Error: Node name is required"
    echo "Usage: $0 <node-name> [message] [silence-duration]"
    echo ""
    echo "Arguments:"
    echo "  node-name          : Name of the node to put into maintenance"
    echo "  message            : Message describing the maintenance (optional)"
    echo "  silence-duration   : Duration for alert silence, e.g., '24h', '2d' (optional, default: 24h)"
    exit 1
fi

NODE="$1"
MESSAGE="${2:-Node under maintenance - setting to triage}"
SILENCE_DURATION="${3:-24h}"

infractl alertmanager add-silence --comment "Node maintenance: ${MESSAGE}" --duration "${SILENCE_DURATION}" "node=${NODE}"

cwctl conditioner upsert "${NODE}" --condition AdminMaintenanceMode --status True --message "${MESSAGE}"

cwctl conditioner upsert "${NODE}" --condition AdminPermanentFailure --status True --message "${MESSAGE}"
}

node-drain-triage-maintenance() {
if [ -z "$1" ]; then
    echo -e "Error: Node name is required"
    echo "Usage: $0 <node-name> [message] [silence-duration]"
    echo ""
    echo "Arguments:"
    echo "  node-name          : Name of the node to put into maintenance"
    echo "  message            : Message describing the maintenance (optional)"
    echo "  silence-duration   : Duration for alert silence, e.g., '24h', '2d' (optional, default: 24h)"
    exit 1
fi

NODE="$1"
MESSAGE="${2:-Node under maintenance - setting to triage}"
SILENCE_DURATION="${3:-24h}"

infractl alertmanager add-silence --comment "Node maintenance: ${MESSAGE}" --duration "${SILENCE_DURATION}" "node=${NODE}"

cwctl conditioner upsert "${NODE}" --condition AdminMaintenanceMode --status True --message "${MESSAGE}"

cwctl conditioner upsert "${NODE}" --condition AdminPermanentFailure --status True --message "${MESSAGE}"

cwctl nlcc "${NODE}" --state triage --message "${MESSAGE}" -o

cwctl drain "${NODE}" --message "${MESSAGE}"
}

node-return-to-production() {
if [ -z "$1" ]; then
    echo -e "Error: Node name is required${NC}"
    echo "Usage: $0 <node-name> [message]"
    exit 1
fi

NODE="$1"
MESSAGE="${2:-Maintenance complete - returning to production}"

cwctl drain "${NODE}" --unset true --message "${MESSAGE}"
cwctl conditioner remove "${NODE}" --condition AdminPermanentFailure
cwctl conditioner remove "${NODE}" --condition AdminMaintenanceMode
cwctl nlcc "${NODE}" --state production --message "${MESSAGE}" -o

SILENCE_IDS=$(infractl alertmanager list-silences --matchers "node=${NODE}" --id-only 2>/dev/null || true)
if [ -n "${SILENCE_IDS}" ]; then
    echo "${SILENCE_IDS}" | while read -r silence_id; do
        if [ -n "${silence_id}" ]; then
            infractl alertmanager expire-silence "${silence_id}"
        fi
    done
fi
}

cloudsmith-versions() {
  local pkg=${1:?usage: cloudsmith-versions <package>}
  cloudsmith list packages coreweave/${pkg} -F json \
    --page-size 50 --page 1 \
    -q "name:^${pkg}$ format:docker" \
    | jq -r '[.data[].tags.version? | arrays | .[]] | unique | sort_by(
        ltrimstr("v") | split("-")[0] | split(".") | map(tonumber? // 0)
      ) | reverse[]'
}
