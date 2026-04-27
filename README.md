# 🤖 GitLab Issue-to-MR AI Agent

> Write an issue. Label it. Walk away. Come back to a Merge Request.

This agent watches your GitLab project for issues labelled `ai-fix`, reads the description, writes the fix, runs your tests, and opens a Merge Request — all without you touching a terminal.

**It never merges its own MR.** That part is always yours.

---

## How It Works

```
You write a GitLab issue  →  label it "ai-fix"
         ↓
Agent reads the issue
         ↓
Creates a branch  →  writes the fix  →  commits
         ↓
Runs CI tests
         ↓
Opens a Merge Request
         ↓
Posts the MR link on the issue thread
         ↓
You review  →  approve  →  merge
```

---

## Built With

| | |
|---|---|
| 🧠 AI | [Claude](https://anthropic.com) via Anthropic API |
| 🦊 VCS | GitLab REST API v4 |
| ⚡ Server | FastAPI + Uvicorn |
| 🐳 Deploy | Docker + Docker Compose |

---

## Project Structure

```
gitlab-issue-mr-agent/
│
├── agent/
│   ├── server.py          # Receives GitLab webhook events
│   ├── agent_loop.py      # Claude reasoning + tool-use loop
│   ├── gitlab_api.py      # All GitLab API calls
│   ├── tools.py           # Tool definitions for Claude
│   ├── tool_executor.py   # Runs the tools Claude calls
│   ├── notifier.py        # Posts comments + Slack alerts
│   └── skill.py           # Loads SKILL.md as system prompt
│
├── tests/                 # Unit tests (mocked, no live API calls)
│
├── .github/skills/
│   └── issue-first-branch-mr-workflow/
│       └── SKILL.md       # Auto-discovered by GitHub Copilot in VS Code
│
├── SKILL.md               # Agent workflow policy (Claude system prompt)
├── .env.example           # Environment variable template
├── Dockerfile
├── docker-compose.yml
└── .gitlab-ci.yml
```

---

## Setup

### 1 — Clone and configure

```bash
git clone https://github.com/BDL-7/gitlab-issue-mr-agent.git
cd gitlab-issue-mr-agent
cp .env.example .env
```

Open `.env` and fill in your values:

```env
GITLAB_URL=https://gitlab.com
GITLAB_TOKEN=your-personal-access-token
GITLAB_PROJECT_ID=your-numeric-project-id
GITLAB_WEBHOOK_SECRET=any-random-string-you-choose
ANTHROPIC_API_KEY=your-anthropic-api-key
DEFAULT_BASE_BRANCH=dev
SLACK_WEBHOOK_URL=        # optional
```

> **GitLab token scopes needed:** `api` · `write_repository` · `read_user`
>
> **Where is my Project ID?** GitLab project → Settings → General → top of the page

---

### 2 — Start the server

```bash
# Local development
pip install -r requirements.txt
uvicorn agent.server:app --reload --port 8000

# Or with Docker
docker compose up --build -d
```

---

### 3 — Connect GitLab

1. Go to your GitLab project → **Settings → Webhooks**
2. Set the URL to `https://<your-server>/webhook`
3. Set the secret token to match `GITLAB_WEBHOOK_SECRET` in your `.env`
4. Enable **Issues events** only
5. Save

> Testing locally? Use [ngrok](https://ngrok.com) to expose port 8000:
> ```bash
> ngrok http 8000
> ```
> Paste the `https://` ngrok URL as your webhook URL.

---

### 4 — Run tests

```bash
pytest tests/ -v
```

No live API calls are made — everything is mocked.

---

## Using the Agent

### Step 1 — Write a good issue

The agent is only as good as what you give it. A good issue has:

- A **specific title** — this becomes the branch name
- A **clear description** — what is broken, where it is, what correct looks like

**Example of a great issue:**

> **Title:** Fix divide-by-zero error in calculate_average
>
> **Description:** `calculate_average` in `utils/math.py` crashes with
> `ZeroDivisionError` when passed an empty list. It should return `None` instead.

**Example of a bad issue:**

> **Title:** Fix bug
>
> **Description:** something is broken

---

### Step 2 — Add the label

Add the `ai-fix` label to the issue. That's your trigger.

---

### Step 3 — Wait for the comment

The agent posts on the issue thread twice:
- When it **starts** — confirms the branch name
- When it **finishes** — posts the MR link

---

### Step 4 — Review and merge

Open the MR, read the diff, run any manual checks, and merge when you're satisfied.

---

## What the Agent Will and Won't Do

| ✅ Will do | ❌ Won't do |
|---|---|
| Fix a specific bug in a named file | Merge its own MR |
| Add a missing validation | Refactor unrelated code |
| Write a missing unit test | Make architectural decisions |
| Update a config value | Act on issues without `ai-fix` label |
| Follow branch and MR naming policy exactly | Push directly to `dev` or `main` |
| Run CI and fix test failures | Touch more than the issue describes |

---

## Configuration Reference

| Variable | Required | What it does |
|---|---|---|
| `GITLAB_URL` | ✅ | Your GitLab instance URL |
| `GITLAB_TOKEN` | ✅ | Personal access token |
| `GITLAB_PROJECT_ID` | ✅ | Numeric ID of your project |
| `GITLAB_WEBHOOK_SECRET` | ✅ | Shared secret with GitLab webhook |
| `ANTHROPIC_API_KEY` | ✅ | Claude API access |
| `DEFAULT_BASE_BRANCH` | ✅ | MR target branch (default: `dev`) |
| `SLACK_WEBHOOK_URL` | ❌ | Slack notifications (leave blank to disable) |

---

## Deployment

The agent is a stateless container. It runs anywhere Docker runs:

```bash
# Any VPS (DigitalOcean, Hetzner, etc.)
docker compose up -d

# Railway / Render
# Point to the Dockerfile, add env vars in the dashboard

# GitLab CI
# Use the included .gitlab-ci.yml
```

For production, put it behind a reverse proxy (nginx or Caddy) with a valid TLS certificate so GitLab can reach it over HTTPS.

---

## Security

- Webhook token is verified on every request using constant-time comparison
- Agent only writes to its own issue branch — never to `dev` or `main`
- Agent never merges MRs — human approval is always required
- A 20-iteration cap prevents runaway Claude API usage
- The `ai-fix` label is a manual opt-in — the agent ignores everything else
- `.env` is in `.gitignore` — secrets never leave your machine

---

## Credits

The workflow in `SKILL.md` — issue-first branching, branch naming, MR targeting — is taken from the **corvd-ai-skills** repository by [@cdcent](https://github.com/cdcent):

🔗 [corvd-ai-skills — Issue-First Branch and PR Workflow](https://github.com/cdcent/corvd-ai-skills/blob/dev/README.md)

The original was written for GitHub CLI and GitHub workflows. This project re-implements it for GitLab, GitHub Copilot, and VS Code — and extends it into a fully autonomous agent powered by the Anthropic API.

---

## License

MIT
