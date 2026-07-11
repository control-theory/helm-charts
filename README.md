# ControlTheory Helm Charts

Public Helm charts for deploying the **ControlTheory agent** into your
Kubernetes cluster, so runtime telemetry flows into [Dstl8](https://dstl8.ai).

> Published as a Helm repository at **[control-theory.github.io/helm-charts](https://control-theory.github.io/helm-charts)**.

## What is Dstl8?

**Dstl8** is continuous runtime feedback for developers. It distills, detects,
correlates, and explains problems across your full deployment chain —
Kubernetes, Docker, AWS, Vercel, Supabase, Railway, OpenTelemetry, and more —
so you stay out of debug rabbit holes. Powered by Möbius agents, an MCP server,
and the Dstl8 CLI, that context streams back into Claude Code, Cursor, and the
rest of your dev flow.

- Website — **[dstl8.ai](https://dstl8.ai)** · [controltheory.com](https://www.controltheory.com)
- Documentation — **[docs.controltheory.com](https://docs.controltheory.com/controltheory-documentation/dstl8-docs)**
- Dstl8 CLI — **[github.com/control-theory/dstl8](https://github.com/control-theory/dstl8)**

## Getting started

New to Dstl8? Start here — you don't need this repo to begin.

1. **Sign up** and grab the Dstl8 CLI:
   ```bash
   brew install control-theory/dstl8/dstl8
   dstl8 signup
   ```
2. **Add a source** so logs start flowing. The CLI wizard covers Kubernetes,
   CloudWatch, Vercel, Supabase, OTLP, GitHub, and more:
   ```bash
   dstl8 sources add kubernetes
   ```
3. **Connect your AI agent** over MCP:
   ```bash
   dstl8 install claude-code
   ```

Full walkthrough in the [Dstl8 CLI repo](https://github.com/control-theory/dstl8)
and the [docs](https://docs.controltheory.com/controltheory-documentation/dstl8-docs).

## The charts

This repository publishes the charts that deploy the ControlTheory agent on
Kubernetes:

| Chart | What it deploys |
|-------|-----------------|
| **aigent-ds** | The aigent DaemonSet — per-node log collection |
| **aigent-cluster** | The cluster agent — captures Kubernetes events |

The charts are driven by tokens and endpoints that Dstl8 generates for you.

## Installing

The easiest path is to **add a Kubernetes source in the
[Dstl8 app](https://dstl8.ai)** — it hands you a ready-to-run install command
(via [install.controltheory.com](https://install.controltheory.com)) that wires
up both charts for you. See the
[installation docs](https://docs.controltheory.com/controltheory-documentation/dstl8-docs)
for details.

To use the charts directly with Helm, add the repo:

```bash
helm repo add ct-helm https://control-theory.github.io/helm-charts
helm repo update ct-helm
```

Then install the chart(s) with the values Dstl8 provides:

```bash
helm upgrade --install aigent-ds ct-helm/aigent-ds \
  --namespace controltheory --create-namespace \
  --set daemonset.org_dns_id=<org-id> \
  --set daemonset.controlplane.admission_token=<token> \
  --set daemonset.org_api_endpoint=<url> \
  --set daemonset.cluster_name=<name> \
  --set daemonset.deployment_env=<env>

helm upgrade --install aigent-cluster ct-helm/aigent-cluster \
  --namespace controltheory --create-namespace \
  --set deployment.org_dns_id=<org-id> \
  --set deployment.controlplane.admission_token=<token> \
  --set deployment.org_api_endpoint=<url> \
  --set deployment.cluster_name=<name> \
  --set deployment.deployment_env=<env>
```

See each chart's `values.yaml` for the full set of configurable values.

## Contributing

Charts are published from this repo via GitHub Pages. Changes are tested on
`stage` (published as `-stage.N` versions) and released through `main` — see
[CONTRIBUTING.md](CONTRIBUTING.md) for the branching and release workflow.

## Community & support

- [Discord](https://discord.gg/nRBUFYByta)
- [Issues](https://github.com/control-theory/dstl8/issues)

## License

These Helm charts are MIT licensed. The ControlTheory agent and Dstl8 binaries
themselves are proprietary, owned by ControlTheory, Inc., and governed by the
[ControlTheory Terms of Service](https://www.controltheory.com/terms-of-service/).
