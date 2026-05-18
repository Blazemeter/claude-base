# Linked repositories — strict two-way sync

This codebase is published from **two GitHub repositories that MUST stay byte-for-byte identical on every branch**:

| Repo | URL | Default branch |
|------|-----|----------------|
| PerfectoMobileDev/claude-base | https://github.com/PerfectoMobileDev/claude-base | `main` |
| Blazemeter/claude-base        | https://github.com/Blazemeter/claude-base        | `main` |

Both repos belong to teams inside Perforce that consume the same Claude Code plugin marketplace. Drift between them is treated as a defect.

## The rule

> **Every commit on every branch must appear on both repos.** You push to one — the auto-sync workflow propagates to the other.

There is no source-of-truth designation. Both repos are first-class. The rule is symmetric: a push to either side propagates to the other.

## How the sync works

Two GitHub Actions workflows enforce the rule. Both ship in `.github/workflows/` and are present in BOTH repos (kept in sync along with everything else).

### `sync-to-sibling.yml` — automated mirror (the propagation)

Triggers on every `push` and `delete` event on any branch. It:

1. Detects which repo it is running in (`Perfecto` vs `Blazemeter`).
2. Computes the sibling URL.
3. Force-pushes the affected ref to the sibling using the `SIBLING_SYNC_TOKEN` secret.

`git push` with an unchanged SHA is a no-op on the sibling, so the workflow does **not** trigger an infinite ping-pong: the sibling's push-event handler sees that the ref didn't change and exits silently.

### `verify-sibling-sync.yml` — strict check on every PR (the gate)

Triggers on every `pull_request` targeting `main`. It compares the current `main` of this repo against the current `main` of the sibling and **fails the check if the sibling has commits not present here** (out-of-band drift).

The check is required by branch protection on `main`. **PRs cannot be merged while it is failing.** If it fails, the recovery procedure is below.

### What can still go wrong

The mirror is best-effort. Race conditions and outages do happen:

| Scenario | What happens | What to do |
|----------|--------------|------------|
| Two devs push to the two repos at the same time | Last writer wins; the earlier push is force-overwritten on the sibling | The losing commit is still in the local clone — re-push it |
| `SIBLING_SYNC_TOKEN` is expired / revoked | `sync-to-sibling.yml` fails on push | Rotate the PAT (see "Required secrets" below); re-run the failed workflow |
| Sibling repo has had a direct admin push that the source missed | `verify-sibling-sync.yml` fails the next PR opened against `main` | Pull the missing commits into this repo first, then re-open the PR |
| Workflow files themselves diverge (someone disables a workflow on one side) | Slow drift; next push from the other side will restore them | Treat workflow files as immutable except via PR to **both repos simultaneously** |

## Required secrets (one-time setup per repo)

Both repos need a PAT stored as **repository secret** `SIBLING_SYNC_TOKEN`:

- Type: classic personal access token (or a fine-grained equivalent).
- Scopes: `repo`, `workflow`.
- SSO authorization: **authorized for both `Blazemeter` AND `PerfectoMobileDev` organizations** (each org has its own SAML grant — both must be approved on the same token).
- Stored at:
  - https://github.com/PerfectoMobileDev/claude-base/settings/secrets/actions → `SIBLING_SYNC_TOKEN`
  - https://github.com/Blazemeter/claude-base/settings/secrets/actions → `SIBLING_SYNC_TOKEN`

Rotate annually (or whenever the owning user leaves). The workflow exits 1 with a clear error when the token is missing or unauthorized.

## Required branch protection (one-time setup per repo)

On `main` in **both** repos:

1. Settings → Branches → Add rule for `main`.
2. Enable **"Require status checks to pass before merging"**.
3. Mark these checks as required:
   - `Plugin marketplace validate / *` (the existing 5-layer CI)
   - `Verify sibling sync / verify` (from `verify-sibling-sync.yml`)
4. Enable **"Require branches to be up to date before merging"**.
5. (Recommended) Enable **"Restrict pushes that create matching branches"** so the only path to `main` is via PR.

Without these settings the sync is advisory. With them, drift becomes physically impossible to merge.

## Recovery procedure: "verify-sibling-sync failed on my PR"

The check fails when the sibling has at least one commit on `main` that this repo does not. Two paths:

### Path A — the sibling commit is legitimate, just unsynced

```bash
git remote add sibling https://github.com/<sibling-org>/claude-base.git
git fetch sibling main
git checkout main
git merge --ff-only sibling/main          # fast-forward if possible
git push origin main                       # this triggers sync-to-sibling to mirror back
```

Rebase your PR branch on top and re-open.

### Path B — the sibling commit shouldn't have existed (admin push, accident)

```bash
# Identify the unwanted commit
git fetch sibling main
git log this-repo/main..sibling/main

# After confirming, force-overwrite the sibling main from this repo's authoritative state:
git push --force sibling main             # uses SSO-authorized credentials
```

Document the recovery in the PR description so reviewers know which side won.

## Why two-way and not one-way?

Two-way mirror means anyone with merge rights on either repo can ship a change; no single "upstream" team blocks the other. The trade-off is the race-condition risk above, mitigated by branch protection + the strict verify check.

If at any point one side becomes the agreed source-of-truth, switch by:

1. Disabling `sync-to-sibling.yml` on the non-truth side (set `if: false` on the job).
2. Updating this document.
3. The other side's workflow continues to propagate.

## Changes to this document

`LINKED_REPOS.md` is the contract. Any change to the linking model itself requires PRs to **both** repositories (the verify check will block otherwise). Treat it like a versioned spec.
