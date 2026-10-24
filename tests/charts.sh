#!/usr/bin/env bash
#
# Template assertions for the aigent charts: renders each chart with helm
# template and checks what the rendered manifests must (and must not) hold.
# Needs only helm and bash. Run from anywhere:
#
#   tests/charts.sh
#
# The golden files in tests/golden hold each ClusterRole's rules as they were
# before metricsScrape existed (docs#694). With metricsScrape off, the rules
# must match them exactly: a customer who never turns scraping on keeps
# today's RBAC.

set -uo pipefail

cd "$(dirname "$0")/.."

failures=0

pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }

# render <chart> <template> [helm args...]: one template, rendered.
render() {
  local chart=$1 tmpl=$2
  shift 2
  helm template ci "charts/$chart" -s "templates/$tmpl" "$@"
}

# rules <chart> [helm args...]: the ClusterRole from "rules:" on, blank lines
# and comment lines dropped.
rules() {
  local chart=$1
  shift
  render "$chart" clusterrole.yaml "$@" | sed -n '/^rules:/,$p' | sed -e '/^$/d' -e '/^ *#/d'
}

# expect_contains <name> <text> <block>: block is a substring of text.
expect_contains() {
  if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1"; fi
}

# expect_absent <name> <text> <needle>: needle is not in text.
expect_absent() {
  if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1"; fi
}

# expect_equal <name> <got> <want>
expect_equal() {
  if [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    fail "$1"
    diff <(printf '%s\n' "$3") <(printf '%s\n' "$2") | sed 's/^/     /'
  fi
}

# --- aigent-ds -------------------------------------------------------------

golden=$(cat tests/golden/aigent-ds-clusterrole-rules.yaml)

expect_equal "aigent-ds: RBAC unchanged by default" \
  "$(rules aigent-ds)" "$golden"
expect_equal "aigent-ds: RBAC unchanged with metricsScrape.enabled=false" \
  "$(rules aigent-ds --set metricsScrape.enabled=false)" "$golden"

on=$(rules aigent-ds --set metricsScrape.enabled=true)
expect_equal "aigent-ds: metricsScrape.enabled adds exactly nodes/metrics (get)" \
  "$on" "$golden
  - apiGroups: [\"\"]
    resources: [\"nodes/metrics\"]
    verbs: [\"get\"]"
expect_absent "aigent-ds: never nodes/proxy" "$on" "nodes/proxy"

ds=$(render aigent-ds daemonset.yaml)
expect_contains "aigent-ds: K8S_NODE_IP from status.hostIP" "$ds" \
"          - name: K8S_NODE_IP
            valueFrom:
              fieldRef:
                fieldPath: status.hostIP"

svc=$(render aigent-ds service.yaml)
expect_absent "aigent-ds: no remote-write port on the agent by default" "$ds" "remote-write"
expect_absent "aigent-ds: no remote-write port on the Service by default" "$svc" "remote-write"

ds_rw=$(render aigent-ds daemonset.yaml --set remoteWrite.enabled=true)
svc_rw=$(render aigent-ds service.yaml --set remoteWrite.enabled=true)
expect_contains "aigent-ds: remoteWrite.enabled opens 9090 on the agent" "$ds_rw" \
"          - name: remote-write
            containerPort: 9090"
expect_contains "aigent-ds: remoteWrite.enabled opens 9090 on the Service" "$svc_rw" \
"    - name: remote-write
      protocol: TCP
      port: 9090
      targetPort: 9090"

# Load-bearing (docs#694 §3.4): one sender's series must land in one agent.
expect_contains "aigent-ds: Service internalTrafficPolicy is Local" "$svc" \
  "  internalTrafficPolicy: Local"
expect_contains "aigent-ds: Service internalTrafficPolicy is Local with remoteWrite" "$svc_rw" \
  "  internalTrafficPolicy: Local"

# --- aigent-cluster --------------------------------------------------------

golden=$(cat tests/golden/aigent-cluster-clusterrole-rules.yaml)

expect_equal "aigent-cluster: RBAC unchanged by default" \
  "$(rules aigent-cluster)" "$golden"
expect_equal "aigent-cluster: RBAC unchanged with metricsScrape.enabled=false" \
  "$(rules aigent-cluster --set metricsScrape.enabled=false)" "$golden"
expect_equal "aigent-cluster: metricsScrape.enabled adds exactly endpoints and endpointslices" \
  "$(rules aigent-cluster --set metricsScrape.enabled=true)" "$golden
  - apiGroups: [\"\"]
    resources: [\"endpoints\"]
    verbs: [\"get\", \"list\", \"watch\"]
  - apiGroups: [\"discovery.k8s.io\"]
    resources: [\"endpointslices\"]
    verbs: [\"get\", \"list\", \"watch\"]"

# D5: never two cluster agents during a rollout.
recreate="  strategy:
    type: Recreate"
expect_contains "aigent-cluster: Deployment strategy is Recreate" \
  "$(render aigent-cluster deployment.yaml)" "$recreate"
expect_contains "aigent-cluster: Deployment strategy is Recreate with metricsScrape" \
  "$(render aigent-cluster deployment.yaml --set metricsScrape.enabled=true)" "$recreate"

if ((failures > 0)); then
  printf '\n%d check(s) failed\n' "$failures"
  exit 1
fi
printf '\nall checks passed\n'
