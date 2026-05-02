# Contributing

## Branch Strategy

This repository uses a three-tier branch model:

```
main  ← stable, production-ready snapshots only
  └── dev  ← long-lived integration branch; all features merge here first
        └── <issue-number>-<issue-title-slug>  ← short-lived feature branch
```

| Branch | Purpose | Who pushes |
|---|---|---|
| `main` | Stable releases only | Merge from `dev` via MR; no direct commits |
| `dev` | Integration branch; CI deploys from here | Merge from feature branches via MR |
| feature | One branch per issue | Author pushes; opens MR targeting `dev` |

---

## One-Time Repository Setup (run once, by a maintainer)

If `dev` does not yet exist, create it from the initial clean commit and push it:

```bash
git fetch origin
git checkout -b dev b86eedc
git push -u origin dev
```

Then protect both `main` and `dev` in **Settings → Branches** so that direct pushes are blocked and MR approval is required.

---

## Starting New Work

1. **Create an issue** in GitLab (or GitHub) with a clear title and description.
2. **Branch from `dev`**, naming the branch `<issue-number>-<issue-title-slug>`:

   ```bash
   git fetch origin
   git checkout dev
   git pull --ff-only origin dev
   git checkout -b 42-fix-divide-by-zero-in-calculate-average
   git push -u origin 42-fix-divide-by-zero-in-calculate-average
   ```

3. **Commit your changes** on that branch as many times as needed.
4. **Open an MR targeting `dev`** once the issue is fully resolved.

---

## Merge Request Checklist

- [ ] Branch name contains the issue number and the **full** issue title as a slug (no abbreviations)
- [ ] All commits are on the feature branch (none directly on `dev` or `main`)
- [ ] Tests pass (`pytest tests/ -v`)
- [ ] MR title matches the branch name
- [ ] MR description summarises what was changed and why
- [ ] **MR target branch is `dev`** — never `main`

---

## Releasing to `main`

Only maintainers merge `dev` → `main`. This is done via a dedicated MR after the integration tests on `dev` pass and the changes are confirmed stable.

---

## Automated Agent Behaviour

When the `ai-fix` label is added to an issue, the agent follows the same workflow:

1. Creates a branch from `dev` named `<issue-number>-<issue-title-slug>`
2. Commits the fix on that branch
3. Runs CI
4. Opens an MR targeting `dev`
5. Posts the MR link as a comment on the issue

The agent **never** merges its own MR and **never** pushes directly to `dev` or `main`.

---

## Running Tests Locally

```bash
pip install -r requirements.txt
pytest tests/ -v
```

No live API calls are made — everything is mocked.
