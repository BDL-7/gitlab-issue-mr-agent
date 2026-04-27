# Issue-First Branch and MR Workflow (VS Code + GitLab + Copilot)

> Taken from [corvd-ai-skills — Issue-First Branch and PR Workflow](https://github.com/cdcent/corvd-ai-skills/blob/dev/README.md)
> and re-written for the GitLab, GitHub Copilot, and VS Code platform.

---

## Skill Summary

This skill standardizes the first-time contribution workflow for a local branch
in a GitLab repository. The flow is:

1. Create an issue with a title and description
2. Create a branch that includes the issue number and full issue title in its name
3. Fix the code as described in the issue, committing as many times as needed
4. Once everything is resolved, open a Merge Request whose title matches the
   branch name and whose description summarizes what was achieved

---

## When to Use This Skill

- A contributor has local changes that need to be published for the first time
- A new feature or bugfix does not yet have a tracking issue
- The repository uses `dev` as the integration branch

---

## Required Policy

First publication of a new line of work must follow this exact order:

1. Create issue (with title and description)
2. Create branch (named with issue number + issue title)
3. Make all necessary commits on that branch
4. When the issue is fully resolved, open an MR targeting `dev`

After the MR is open, subsequent fixes on the same branch only require
commit and push — no new issue or MR needed.

---

## Inputs You Need

- Repository namespace/name (for example, `org/repo`)
- Issue title and description
- Local base branch (usually `dev`)

---

## Branch Naming Convention

Branch names must include both the issue number and the full issue title (slugified):

- `<issue-number>-<issue-title-as-slug>`
- Example: if issue #42 is titled "Fix FASTQ header validation",
  the branch is `42-fix-fastq-header-validation`

---

## Step 1 — Create the Issue

```bash
glab issue create \
  --title "<issue title>" \
  --description "<issue description>"
```

---

## Step 2 — Create and Publish the Branch

```bash
git fetch origin
git checkout dev
git pull --ff-only origin dev

ISSUE_NUMBER=<issue-number>
ISSUE_TITLE="<issue-title-as-slug>"
BRANCH_NAME="${ISSUE_NUMBER}-${ISSUE_TITLE}"

git checkout -b "$BRANCH_NAME"
git push -u origin "$BRANCH_NAME"
```

---

## Step 3 — Fix the Code (Commit as Many Times as Needed)

```bash
git add -A
git commit -m "<clear description of what this commit does>"
git push
```

---

## Step 4 — Open the Merge Request (Once Everything is Fixed)

```bash
glab mr create \
  --target-branch dev \
  --source-branch "$BRANCH_NAME" \
  --title "${BRANCH_NAME}" \
  --description "<summary of what was fixed and how>"
```

---

## Dev-Target Verification (Mandatory)

```bash
git branch -vv
glab mr view
```

Expected:
- `target_branch` must be `dev`
- `source_branch` must match your issue branch

Fix if wrong:
```bash
glab mr update --target-branch dev
```

---

## Decision Logic for Copilot Automation

1. Check whether the current branch already has an open MR
2. If no MR exists, enforce the full flow: issue → branch → commits → MR
3. If an MR already exists, only commit and push
4. Always verify MR target branch is `dev` before the final push

---

## Common Pitfalls

- Opening the MR before the issue is fully resolved
- Creating the branch before the issue exists
- Using only a short slug instead of the full issue title
- Forgetting `git push -u origin <branch>` on the first push
- MR targeting `main` instead of `dev`

---

## Minimal Checklist

- [ ] Issue exists with a clear title and description
- [ ] Branch name contains the issue number and full issue title
- [ ] All commits are pushed to the issue branch
- [ ] Issue is fully resolved before MR is opened
- [ ] MR title matches the branch name
- [ ] MR description summarizes what was achieved
- [ ] MR target branch is `dev`
