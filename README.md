# ?? GitLab Issue-to-MR Agent

> You write the issue. The agent writes the code. You click merge.

---

## Feed It a Good Issue

The agent is only as good as what you give it.

| | Title | Description |
|---|---|---|
| ? | `Fix divide-by-zero in calculate_average` | "`calculate_average` in `utils/math.py` crashes on empty list — return `None` instead." |
| ? | `Fix bug` | `something is broken` |

A good issue has a **specific title** (becomes the branch name) and tells the agent **what file**, **what's wrong**, and **what done looks like**.

---

## Trigger It

Add the label **`ai-fix`** to the issue. That's it. Walk away.

The agent will comment on the issue when it starts (branch name) and when it's done (MR link).

---

## Review and Merge

Open the MR, read the diff, merge when satisfied. **The agent never merges its own work.**

---

## First-Time Setup

**1. Configure**
```bash
git clone https://github.com/BDL-7/gitlab-issue-mr-agent.git
cd gitlab-issue-mr-agent
cp .env.example .env   # fill in the values below
```

```env
GITLAB_URL=https://gitlab.com
GITLAB_TOKEN=           # scopes: api, write_repository, read_user
GITLAB_PROJECT_ID=      # Settings ? General ? top of page
GITLAB_WEBHOOK_SECRET=  # any random string
ANTHROPIC_API_KEY=
DEFAULT_BASE_BRANCH=dev
SLACK_WEBHOOK_URL=      # optional
```

**2. Start the server**
```bash
docker compose up --build -d
# or locally: uvicorn agent.server:app --reload --port 8000
```

**3. Connect GitLab**

GitLab project ? **Settings ? Webhooks**
- URL: `https://<your-server>/webhook`
- Secret: matches `GITLAB_WEBHOOK_SECRET`
- Trigger: **Issues events** only

> Local dev? `ngrok http 8000` and use the `https://` URL.

**4. Test**
```bash
pytest tests/ -v   # fully mocked, no live API calls
```

---

## Guardrails

- Never pushes to `dev` or `main`
- Never merges its own MR
- Ignores every issue without the `ai-fix` label
- Capped at 20 reasoning iterations
- Webhook verified with constant-time token comparison

---

## Stack

Claude (Anthropic) · GitLab REST API v4 · FastAPI · Docker

---

*Workflow policy adapted from [corvd-ai-skills](https://github.com/cdcent/corvd-ai-skills/blob/dev/README.md) by [@cdcent](https://github.com/cdcent), re-implemented for GitLab + Anthropic API.*

MIT License
