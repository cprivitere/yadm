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
TELEPORT_ROLES_CLUSTER="cpx-cluster-super-admin-resource-access,prime-cluster-super-admin-resource-access"
TELEPORT_ROLE_SSH_NODE="cpx-cluster-super-admin-resource-access,prime-cluster-super-admin-resource-access"

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
  tsh clusters -f json | yq '.[] | select(.selected == true) | .cluster_name'
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
  echo "${cluster}|${deviceslot}|${serial}"
}


# ============================================================================
# EXPORTS & ENVIRONMENT
# ============================================================================

export TELEPORT_PROXY_NA="teleport.na.int.coreweave.com:443"
export GOPRIVATE='github.com/coreweave/*,bsr.core-services.ingress.coreweave.com/gen/go'

source <(cwctl completion zsh)

alias intd="infractl nt delete --automerge"
alias inta="infractl nt add --automerge"

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




# Search for clusters in Teleport
tp-search-cluster() {
  if [ -z "$1" ]; then
    echo "Usage: tp-search-cluster <cluster-name>"
    return 1
  fi

  tsh request search --kind kube_cluster --search "$1"
}

# Request access to ORD1 cluster (specific use case)
tp-ord1() {
  if [ -z "$1" ]; then
    echo "Usage: tp-ord1 <reason>"
    return 1
  fi

  eval "tsh request create --resource /teleport.ord1.int.coreweave.com/namespace/ord1-tenant/dev-internal-cluster --roles k8s-infrastructure-dev-cluster-super-admin-elevated-access --reason \"$@\""
}

# Request access to kubevirt cluster (specific use case)
tp-kubevirt() {
  if [ -z "$1" ]; then
    echo "Usage: tp-kubevirt <reason>"
    return 1
  fi

  local KUBE_CLUSTER="us-lab-01c-kubevirt"

  # Get node *resource IDs*, ideally like: /teleport/node/<uuid>
  local NODES
  NODES="$(tp-search-nodes-in-cluster "${KUBE_CLUSTER}")"

  # Build a string of repeated --resource <id> flags
  local RESOURCE_FLAGS=""
  while IFS= read -r node; do
    [ -n "$node" ] || continue
    RESOURCE_FLAGS="$RESOURCE_FLAGS --resource /teleport/node/$node"
  done <<EOF
$NODES
EOF

  # Add the kube cluster resource itself
  local CLUSTER="/teleport/kube_cluster/${KUBE_CLUSTER}"
  RESOURCE_FLAGS="$RESOURCE_FLAGS --resource $CLUSTER"

  eval "tsh request create${RESOURCE_FLAGS} --roles us-lab-01c-super-admin-elevated-access --reason \"$*\""

}

tp-request-namespace() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: tp-request-namespace <kube-cluster-name> <namespace1> [namespace2 ...] -- <reason>"
    echo "Example: tp-request-namespace us-east-03-internal calico-system kube-system -- \"Debugging pods\""
    return 1
  fi

  local KUBE_CLUSTER=$1
  shift

  # Collect namespaces until we hit "--" or run out of args
  local NAMESPACES=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    NAMESPACES+=("$1")
    shift
  done

  # Skip the "--" delimiter if present
  if [ "$1" = "--" ]; then
    shift
  fi

  # Everything remaining is the reason
  if [ -z "$*" ]; then
    echo "Error: Reason is required"
    echo "Usage: tp-request-namespace <kube-cluster-name> <namespace1> [namespace2 ...] -- <reason>"
    return 1
  fi

  local QUERY="labels[\"cks.coreweave.com/cluster\"] == \"$KUBE_CLUSTER\" || labels[\"cluster\"] == \"$KUBE_CLUSTER\""
  
  # Build resources for all namespaces
  local ALL_RESOURCES=""
  for NAMESPACE in "${NAMESPACES[@]}"; do
    local CLUSTERS=$(tsh kube ls --query "$QUERY" -f yaml | KUBE_CLUSTER="$KUBE_CLUSTER" NAMESPACE="$NAMESPACE" yq '.[] | .metadata += {"rqn": "--resource /" + env(TELEPORT_CLUSTER) + "/namespace/" + env(KUBE_CLUSTER) + "/" + env(NAMESPACE) } | .metadata.rqn')
    local RESOURCES=$(echo $CLUSTERS | tr '\n' ' ')
    ALL_RESOURCES="${ALL_RESOURCES} ${RESOURCES}"
  done

  eval "tsh request create ${ALL_RESOURCES} --roles $TELEPORT_ROLES_CLUSTER --reason \"$@\""
}

# Request access to a cluster
tp-request-cluster() {
  if [ -z "$1" ]; then
    echo "Usage: tp-request-cluster <kube-cluster-name> <reason>"
    return 1
  fi

  #local TELEPORT_CLUSTER=$(_get_current_teleport_cluster)
  local KUBE_CLUSTER=$1
  shift

  local QUERY="labels[\"cks.coreweave.com/cluster\"] == \"$KUBE_CLUSTER\" || labels[\"cluster\"] == \"$KUBE_CLUSTER\""
  local CLUSTERS=$(tsh kube ls --query "$QUERY" -f yaml | yq '.[] | .metadata += {"rqn": "--resource /" + env(TELEPORT_CLUSTER) + "/kube_cluster/" + .kube_cluster_name } | .metadata.rqn')
  local RESOURCES=$(echo $CLUSTERS | tr '\n' ' ')

  eval "tsh request create ${RESOURCES} --roles $TELEPORT_ROLES_CLUSTER --reason \"$@\""
}

# Request access to a cluster and its nodes
tp-request-cluster-and-friends() {
  if [ -z "$1" ]; then
    echo "Usage: tp-request-cluster-and-friends <kube-cluster-name> <reason>"
    return 1
  fi

  #local TELEPORT_CLUSTER=$(_get_current_teleport_cluster)
  local KUBE_CLUSTER=$1
  shift

  NODES=$(tp-search-nodes-in-cluster $KUBE_CLUSTER)
  CLUSTER=$(tp-search-cluster "$1" | grep -o '/teleport[^ ]*/kube_cluster/[^ ]*' | sed -E 's|^/||; s|/kube_cluster/.*||' | head -n1)
  local RESOURCES=$(echo $NODES $CLUSTERS | tr '\n' ' ')

  eval "tsh request create ${RESOURCES} --roles $TELEPORT_ROLES_CLUSTER --reason \"$@\""
}

# Create SSH access request for nodes
tp-request-ssh() {
  if [ $# -lt 2 ]; then
    echo "Usage: tp-create-ssh-request \"<reason>\" <node-name> [<node-name> ...]"
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
  tsh request create "${args[@]}" --roles "$TELEPORT_ROLE_SSH_NODE" --reason "$reason"  
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
dpu-request() {
  if (( $# < 1 )); then
    echo "Usage: dpu-request <nodename> [dpu_port]"
    return 1
  fi

  local node_name=$1
  local dpu_port=${2:-}

  # Get node metadata
  local metadata_result=$(_get_node_metadata_from_yanl "$node_name")
  IFS='|' read -r cluster deviceslot serial <<< "$metadata_result"

  cat << EOF
Hi there, I need a DCT to do a clean and reseat on the following node's DPU cable
gmac: $node_name
cluster: $cluster
deviceslot: $deviceslot
serialnum: $serial
DPU port that needs cleaning: $dpu_port
EOF
}

# Display node information
node-info() {
  if (( $# != 1 )); then
    echo "Usage: node-info <nodename>"
    return 1
  fi

  local node_name=$1

  # Get node metadata
  local metadata_result=$(_get_node_metadata_from_yanl "$node_name")
  IFS='|' read -r deviceslot serial <<< "$metadata_result"

  cat << EOF
gmac: $node_name
cluster: $cluster
deviceslot: $deviceslot
serialnum: $serial
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
