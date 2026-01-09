# node-resources

Analyze Kubernetes cluster nodes for DaemonSet placement. Shows taints, available resources, and generates helm install guidance.

## Usage

```bash
./node-resources.sh [options]
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `-k, --kubeconfig` | Path to kubeconfig | `~/.kube/config` |
| `-c, --cpu` | DaemonSet CPU request | `100m` |
| `-m, --memory` | DaemonSet memory request | `500Mi` |
| `-h, --help` | Show help message | - |

## Examples

```bash
# Local/dev cluster (default kubeconfig)
./node-resources.sh

# Stage cluster
./node-resources.sh -k ~/.kube/ctstage

# Custom resource requirements
./node-resources.sh -k ~/.kube/ctstage -c 250m -m 1Gi
```

## Output

The script provides:

1. **Priority Classes** - Available priority classes in the cluster
2. **Node Details** - Per-node breakdown of:
   - Ready status
   - Taints
   - Allocatable vs requested resources (CPU, Memory, Pods)
   - Whether a DaemonSet can schedule on this node
3. **Summary Table** - Quick overview of all nodes
4. **Helm Install Commands** - Ready-to-use helm commands with appropriate tolerations

## Requirements

- `kubectl` with access to the target cluster
- `bash` (uses bash-specific features like regex matching)
