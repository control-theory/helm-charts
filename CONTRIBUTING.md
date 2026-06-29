# Contributing

## Branching & release workflow

This repo publishes **publicly**. The `main` branch is the public release branch — do **not** commit to it directly.

```
feature branch ──► stage ──► (PR) ──► main
   (your work)    (test)            (public release)
```

| Branch | Role | What publishing does |
|--------|------|----------------------|
| `stage` | Integration & testing | `release.yml` publishes charts as `<version>-stage.N` |
| `main`  | Public release | `release.yml` publishes the real chart versions |

### How to land a change

1. Branch off `stage`, do your work, open a PR **into `stage`**.
2. Merge to `stage`. The release workflow publishes a `-stage.N` chart you can test against.
3. When it's good, open a PR **from `stage` into `main`** and merge it. That is the *only* way to release publicly.

### Enforcement (so we can't forget)

`main` is protected:

- **Direct pushes are blocked** — everything goes through a PR.
- **Only `stage` may be merged into `main`.** A required status check (`source-branch-guard`, see `.github/workflows/enforce-stage-only.yml`) fails any PR into `main` whose source branch isn't `stage`.
- Force-pushes and branch deletion are blocked, and the rules apply to admins too.

If you find yourself wanting to push to `main` directly: don't. Land it on `stage`, then merge `stage` → `main`.
