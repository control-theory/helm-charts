#!/bin/bash
# Analyze Kubernetes cluster nodes for DaemonSet placement
# Shows taints, available resources, and generates helm install guidance
#
# Usage: ./node-resources.sh [options]
#   -k, --kubeconfig    Path to kubeconfig (default: ~/.kube/config)
#   -c, --cpu           DaemonSet CPU request (default: 100m)
#   -m, --memory        DaemonSet memory request (default: 500Mi)
#   -h, --help          Show this help message
#
# Examples:
#   ./node-resources.sh -k ~/.kube/ctstage
#   ./node-resources.sh -k ~/.kube/ctstage -c 250m -m 1Gi

set -e

# Defaults (from k8s-agent-daemonset values.yaml)
KUBECONFIG_PATH="$HOME/.kube/config"
DS_CPU_REQUEST="100m"
DS_MEMORY_REQUEST="500Mi"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--kubeconfig)
            KUBECONFIG_PATH="$2"
            shift 2
            ;;
        -c|--cpu)
            DS_CPU_REQUEST="$2"
            shift 2
            ;;
        -m|--memory)
            DS_MEMORY_REQUEST="$2"
            shift 2
            ;;
        -h|--help)
            head -17 "$0" | tail -15
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
    echo "Error: kubeconfig not found at $KUBECONFIG_PATH"
    exit 1
fi

KUBECTL="kubectl --kubeconfig=$KUBECONFIG_PATH"

# Convert CPU to millicores
cpu_to_millicores() {
    local cpu="$1"
    if [[ "$cpu" =~ ^([0-9]+)m$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$cpu" =~ ^([0-9]+)$ ]]; then
        echo "$((${BASH_REMATCH[1]} * 1000))"
    elif [[ "$cpu" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        # Handle decimals like 0.5, 1.5
        local whole="${BASH_REMATCH[1]}"
        local frac="${BASH_REMATCH[2]}"
        # Pad or truncate fraction to 3 digits for millicores
        frac=$(printf "%-3s" "$frac" | tr ' ' '0' | cut -c1-3)
        echo "$((whole * 1000 + frac))"
    else
        echo "0"
    fi
}

# Convert memory to Mi (mebibytes)
memory_to_mi() {
    local mem="$1"
    if [[ -z "$mem" ]]; then
        echo "0"
        return
    fi

    if [[ "$mem" =~ ^([0-9]+)Ki$ ]]; then
        echo "$((${BASH_REMATCH[1]} / 1024))"
    elif [[ "$mem" =~ ^([0-9]+)Mi$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$mem" =~ ^([0-9]+)Gi$ ]]; then
        echo "$((${BASH_REMATCH[1]} * 1024))"
    elif [[ "$mem" =~ ^([0-9]+)$ ]]; then
        # Bytes
        echo "$((${BASH_REMATCH[1]} / 1024 / 1024))"
    else
        echo "0"
    fi
}

# Sum CPU requests (handles mixed formats: 100m, 1, 0.5)
sum_cpu_requests() {
    local total=0
    for req in $1; do
        local mc=$(cpu_to_millicores "$req")
        total=$((total + mc))
    done
    echo "$total"
}

# Sum memory requests
sum_memory_requests() {
    local total=0
    for req in $1; do
        local mi=$(memory_to_mi "$req")
        total=$((total + mi))
    done
    echo "$total"
}

echo ""
echo "=============================================================================="
echo "DAEMONSET PLACEMENT ANALYSIS"
echo "=============================================================================="
echo "Kubeconfig:        $KUBECONFIG_PATH"
echo "DaemonSet CPU:     $DS_CPU_REQUEST"
echo "DaemonSet Memory:  $DS_MEMORY_REQUEST"
echo "=============================================================================="
echo ""

DS_CPU_MC=$(cpu_to_millicores "$DS_CPU_REQUEST")
DS_MEM_MI=$(memory_to_mi "$DS_MEMORY_REQUEST")

# Get PriorityClasses
echo "PRIORITY CLASSES"
echo "----------------"
PRIORITY_CLASSES=$($KUBECTL get priorityclasses -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.value}{"\n"}{end}' 2>/dev/null | sort -t$'\t' -k2 -rn)
if [[ -n "$PRIORITY_CLASSES" ]]; then
    printf "%-30s %s\n" "NAME" "VALUE"
    printf "%-30s %s\n" "----" "-----"
    echo "$PRIORITY_CLASSES" | while read -r line; do
        NAME=$(echo "$line" | cut -f1)
        VALUE=$(echo "$line" | cut -f2)
        printf "%-30s %s\n" "$NAME" "$VALUE"
    done
    # Check for recommended priority class
    if echo "$PRIORITY_CLASSES" | grep -q "system-node-critical"; then
        RECOMMENDED_PRIORITY="system-node-critical"
    elif echo "$PRIORITY_CLASSES" | grep -q "system-cluster-critical"; then
        RECOMMENDED_PRIORITY="system-cluster-critical"
    else
        RECOMMENDED_PRIORITY=""
    fi
else
    echo "  No PriorityClasses found (using default scheduling priority)"
    RECOMMENDED_PRIORITY=""
fi
echo ""

# Get all nodes
NODES=$($KUBECTL get nodes -o jsonpath='{.items[*].metadata.name}')

if [[ -z "$NODES" ]]; then
    echo "Error: No nodes found or unable to connect to cluster"
    exit 1
fi

# Collect all unique taints (using a simple list with dedup)
ALL_TAINTS_LIST=""

# Temporary file for summary
SUMMARY_FILE=$(mktemp)
trap "rm -f $SUMMARY_FILE" EXIT

echo "NODE DETAILS"
echo "------------"

for NODE in $NODES; do
    # Get node status
    STATUS=$($KUBECTL get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')

    # Get taints
    TAINTS_JSON=$($KUBECTL get node "$NODE" -o jsonpath='{.spec.taints}')
    if [[ -z "$TAINTS_JSON" || "$TAINTS_JSON" == "null" ]]; then
        TAINT_LIST=""
    else
        TAINT_LIST=$($KUBECTL get node "$NODE" -o jsonpath='{range .spec.taints[*]}{.key}={.value}:{.effect}{","}{end}' | sed 's/,$//')

        # Collect unique taints
        IFS=',' read -ra TAINT_ARR <<< "$TAINT_LIST"
        for t in "${TAINT_ARR[@]}"; do
            if [[ -n "$t" ]]; then
                KEY=$(echo "$t" | cut -d'=' -f1)
                EFFECT=$(echo "$t" | grep -oE ':(NoSchedule|NoExecute|PreferNoSchedule)$' | tr -d ':')
                TAINT_ENTRY="$KEY:$EFFECT"
                if [[ ! "$ALL_TAINTS_LIST" =~ "$TAINT_ENTRY" ]]; then
                    ALL_TAINTS_LIST="${ALL_TAINTS_LIST:+$ALL_TAINTS_LIST }$TAINT_ENTRY"
                fi
            fi
        done
    fi

    # Get allocatable resources
    ALLOC_CPU=$($KUBECTL get node "$NODE" -o jsonpath='{.status.allocatable.cpu}')
    ALLOC_MEM=$($KUBECTL get node "$NODE" -o jsonpath='{.status.allocatable.memory}')
    ALLOC_PODS=$($KUBECTL get node "$NODE" -o jsonpath='{.status.allocatable.pods}')

    ALLOC_CPU_MC=$(cpu_to_millicores "$ALLOC_CPU")
    ALLOC_MEM_MI=$(memory_to_mi "$ALLOC_MEM")

    # Get current resource requests on node
    CPU_REQS=$($KUBECTL get pods --all-namespaces --field-selector spec.nodeName="$NODE" \
        -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.resources.requests.cpu}{" "}{end}{end}' 2>/dev/null)
    MEM_REQS=$($KUBECTL get pods --all-namespaces --field-selector spec.nodeName="$NODE" \
        -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.resources.requests.memory}{" "}{end}{end}' 2>/dev/null)

    USED_CPU_MC=$(sum_cpu_requests "$CPU_REQS")
    USED_MEM_MI=$(sum_memory_requests "$MEM_REQS")

    # Calculate available
    AVAIL_CPU_MC=$((ALLOC_CPU_MC - USED_CPU_MC))
    AVAIL_MEM_MI=$((ALLOC_MEM_MI - USED_MEM_MI))

    # Get running pod count
    RUNNING_PODS=$($KUBECTL get pods --all-namespaces --field-selector spec.nodeName="$NODE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    AVAIL_PODS=$((ALLOC_PODS - RUNNING_PODS))

    # Check if daemonset can schedule
    CAN_SCHEDULE="YES"
    REASONS=""

    if [[ "$STATUS" != "True" ]]; then
        CAN_SCHEDULE="NO"
        REASONS="NotReady"
    fi

    if [[ $AVAIL_CPU_MC -lt $DS_CPU_MC ]]; then
        CAN_SCHEDULE="NO"
        REASONS="${REASONS:+$REASONS, }InsufficientCPU"
    fi

    if [[ $AVAIL_MEM_MI -lt $DS_MEM_MI ]]; then
        CAN_SCHEDULE="NO"
        REASONS="${REASONS:+$REASONS, }InsufficientMemory"
    fi

    if [[ $AVAIL_PODS -lt 1 ]]; then
        CAN_SCHEDULE="NO"
        REASONS="${REASONS:+$REASONS, }MaxPodsReached"
    fi

    if [[ -n "$TAINT_LIST" ]]; then
        CAN_SCHEDULE="${CAN_SCHEDULE}*"
        REASONS="${REASONS:+$REASONS, }HasTaints"
    fi

    SCHEDULE_STATUS="$CAN_SCHEDULE${REASONS:+ ($REASONS)}"

    # Print detailed info
    echo ""
    echo "Node: $NODE"
    echo "  Ready:           $STATUS"
    echo "  Taints:          ${TAINT_LIST:-<none>}"
    echo "  Allocatable:     CPU=${ALLOC_CPU_MC}m  Mem=${ALLOC_MEM_MI}Mi  Pods=${ALLOC_PODS}"
    echo "  Requested:       CPU=${USED_CPU_MC}m  Mem=${USED_MEM_MI}Mi  Pods=${RUNNING_PODS}"
    echo "  Available:       CPU=${AVAIL_CPU_MC}m  Mem=${AVAIL_MEM_MI}Mi  Pods=${AVAIL_PODS}"
    echo "  Can Schedule:    $SCHEDULE_STATUS"

    # Save to summary file
    SHORT_NAME=$(echo "$NODE" | cut -c1-44)
    printf "%-45s %8s %10s %8s %s\n" "$SHORT_NAME" "$AVAIL_CPU_MC" "$AVAIL_MEM_MI" "$AVAIL_PODS" "$SCHEDULE_STATUS" >> "$SUMMARY_FILE"
done

echo ""
echo "=============================================================================="
echo "SUMMARY TABLE"
echo "=============================================================================="
printf "%-45s %8s %10s %8s %s\n" "NODE" "CPU(m)" "MEM(Mi)" "PODS" "SCHEDULABLE"
printf "%-45s %8s %10s %8s %s\n" "----" "------" "-------" "----" "-----------"
cat "$SUMMARY_FILE"

echo ""
echo "* = Requires tolerations (see below)"
echo ""
echo "DaemonSet Requirements: CPU=${DS_CPU_REQUEST} (${DS_CPU_MC}m), Memory=${DS_MEMORY_REQUEST} (${DS_MEM_MI}Mi)"

# Build taint keys list if taints exist
TAINT_KEYS=""
if [[ -n "$ALL_TAINTS_LIST" ]]; then
    echo ""
    echo "=============================================================================="
    echo "TAINTS FOUND"
    echo "=============================================================================="
    echo ""
    echo "The following taints were found in the cluster:"
    echo ""

    for taint in $ALL_TAINTS_LIST; do
        KEY=$(echo "$taint" | cut -d: -f1)
        EFFECT=$(echo "$taint" | cut -d: -f2)
        echo "  - $KEY ($EFFECT)"
        TAINT_KEYS="${TAINT_KEYS:+$TAINT_KEYS,}$KEY"
    done
fi

echo ""
echo "=============================================================================="
echo "HELM INSTALL COMMANDS"
echo "=============================================================================="

# Build base helm command
HELM_BASE="helm install aigent-ds ct-helm/aigent-ds \\
  --namespace controltheory \\
  --set resources.cpu.request=$DS_CPU_REQUEST \\
  --set resources.memory.request=$DS_MEMORY_REQUEST"

# Add priority class recommendation
if [[ -n "$RECOMMENDED_PRIORITY" ]]; then
    echo ""
    echo "RECOMMENDED: Use priorityClassName=$RECOMMENDED_PRIORITY to ensure the agent"
    echo "             can preempt lower-priority pods when nodes are resource-constrained."
    PRIORITY_FLAG=" \\
  --set priorityClassName=$RECOMMENDED_PRIORITY"
else
    PRIORITY_FLAG=""
fi

echo ""
echo "Option 1: Schedule on ALL nodes (default - recommended for DaemonSets):"
echo ""
echo "$HELM_BASE$PRIORITY_FLAG"
echo ""
echo "  (tolerateAllTaints=true is the default)"

if [[ -n "$ALL_TAINTS_LIST" ]]; then
    echo ""
    echo "Option 2: Tolerate only the specific taints found in this cluster:"
    echo ""
    echo "$HELM_BASE$PRIORITY_FLAG \\
  --set tolerateAllTaints=false \\
  --set 'tolerateTaintKeys={$TAINT_KEYS}'"
    echo ""
    echo "Option 3: Only schedule on nodes WITHOUT taints:"
    echo ""
    echo "$HELM_BASE$PRIORITY_FLAG \\
  --set tolerateAllTaints=false"
else
    echo ""
    echo "No taints found - DaemonSet will schedule on all ready nodes with available resources."
fi

echo ""
