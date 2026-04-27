# GitLab Issue-to-MR AI Agent

An autonomous AI agent that reads a GitLab issue, creates a branch, writes the
code fix, runs tests, opens a Merge Request, and notifies you — eliminating
the repetitive manual commands of the issue-to-MR developer cycle.

Built with [Claude](https://anthropic.com) (Anthropic API), the
[GitLab REST API](https://docs.gitlab.com/ee/api/), and
[FastAPI](https://fastapi.tiangolo.com/).

---

## How It Works

```
GitLab Issue (labelled "ai-fix")
         ↓
GitLab Webhook → Agent Server (FastAPI)
         ↓
Claude (tool-use loop)
    ├── list_files      → understand project structure
    ├── read_file       → read relevant source files
    ├── write_file      → commit the fix
    ├── run_tests       → trigger GitLab CI and wait for result
    └── open_merge_request → open MR targeting dev
         ↓
GitLab issue comment + Slack notification
         ↓
Human reviews MR → approves → merges
```

The agent **never merges its own MR**. The final merge always requires human approval.

---

## Project Structure

```
gitlab-issue-mr-agent/
├── agent/
│   ├── server.py          # FastAPI webhook receiver
│   ├── agent_loop.py      # Claude tool-use orchestration loop
│   ├── gitlab_api.py      # GitLab REST API wrapper
│   ├── tools.py           # Tool schemas passed to Claude
│   ├── tool_executor.py   # Dispatches tool calls to GitLab API
│   ├── notifier.py        # GitLab comments + Slack notifications
│   └── skill.py           # Loads SKILL.md as Claude system prompt
├── tests/
│   ├── test_server.py
│   ├── test_agent_loop.py
│   └── test_tool_executor.py
├── .github/
│   └── skills/
│       └── issue-first-branch-mr-workflow/
│           └── SKILL.md   # Copilot-discoverable skill (VS Code)
├── SKILL.md               # Agent workflow policy (Claude system prompt)
├── .env.example           # Environment variable template
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
└── .gitlab-ci.yml
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Python 3.11+ | For local development |
| Docker + Docker Compose | For containerised deployment |
| GitLab Personal Access Token | Scopes: `api`, `write_repository`, `read_user` |
| Anthropic API Key | [console.anthropic.com](https://console.anthropic.com) |
| Public HTTPS endpoint | For GitLab to reach your webhook (ngrok works for local dev) |

---

## Setup

### 1. Clone and configure

```bash
git clone <this-repo-url>
cd gitlab-issue-mr-agent
cp .env.example .env
```

Edit `.env` and fill in all values:

```env
GITLAB_URL=https://gitlab.com
GITLAB_TOKEN=<your-personal-access-token>
GITLAB_PROJECT_ID=<numeric-project-id>
GITLAB_WEBHOOK_SECRET=<any-random-string-you-choose>
ANTHROPIC_API_KEY=<your-anthropic-api-key>
DEFAULT_BASE_BRANCH=dev
SLACK_WEBHOOK_URL=          # optional
```

**Where to find your GitLab Project ID:**
Go to your GitLab project → Settings → General → Project ID (top of the page).

### 2. Run locally

```bash
# Install dependencies
pip install -r requirements.txt

# Start the server
uvicorn agent.server:app --reload --port 8000
```

### 3. Expose your local server for webhook testing

```bash
# Install ngrok if you don't have it
brew install ngrok          # macOS
# or download from https://ngrok.com

ngrok http 8000
# Copy the https://<id>.ngrok.io URL — you'll use it in the next step
```

### 4. Configure the GitLab webhook

1. Go to your GitLab project → **Settings → Webhooks**
2. **URL:** `https://<your-ngrok-or-server-url>/webhook`
3. **Secret token:** same value as `GITLAB_WEBHOOK_SECRET` in your `.env`
4. **Trigger:** check **Issues events** only
5. Click **Add webhook**
6. Use **Test → Issue events** to verify — you should see `{"status":"ignored",...}`

### 5. Run with Docker (recommended for production)

```bash
docker compose up --build -d
docker compose logs -f    # watch logs
```

---

## Using the Agent

1. Open your GitLab project and create an issue with a clear **title** and **description**
2. Add the label **`ai-fix`** to the issue
3. The agent activates automatically and posts a comment on the issue confirming it started
4. Wait for the agent to finish — it will post the MR link directly on the issue thread
5. Review the MR, run any manual checks, and merge when satisfied

### Writing good issues for the agent

The agent's output quality depends directly on issue quality. Good issues:

- Have a **specific, descriptive title** (becomes the branch name)
- **Describe the problem** clearly in the description — what is broken, where, what the expected behaviour is
- **Optionally include** relevant file paths, error messages, or reproduction steps

**Example of a good issue:**

> **Title:** Fix divide-by-zero error in calculate_average function
>
> **Description:** `calculate_average` in `utils/math.py` raises a `ZeroDivisionError`
> when passed an empty list. It should return `0` or `None` instead.
> Relevant file: `utils/math.py`, function `calculate_average`.

---

## Configuration Reference

| Variable | Required | Description |
|---|---|---|
| `GITLAB_URL` | Yes | Your GitLab instance URL |
| `GITLAB_TOKEN` | Yes | Personal access token with api + write_repository |
| `GITLAB_PROJECT_ID` | Yes | Numeric ID of the target project |
| `GITLAB_WEBHOOK_SECRET` | Yes | Random string shared with GitLab webhook |
| `ANTHROPIC_API_KEY` | Yes | Anthropic API key |
| `DEFAULT_BASE_BRANCH` | Yes | Integration branch (default: `dev`) |
| `SLACK_WEBHOOK_URL` | No | Slack incoming webhook for notifications |

---

## Running Tests

```bash
pytest tests/ -v
```

All tests are unit tests with mocked external dependencies.
No live GitLab or Anthropic API calls are made during testing.

---

## Deployment

The agent is a stateless HTTP server. Any platform that runs Docker works:

- **VPS (DigitalOcean, Hetzner, Linode):** `docker compose up -d`
- **Railway / Render:** point to the Dockerfile, add env vars in the dashboard
- **GitLab CI self-hosted runner:** use the included `.gitlab-ci.yml`
- **AWS / GCP / Azure:** any container service (ECS, Cloud Run, ACI)

For production, put the agent behind a reverse proxy (nginx or Caddy) with a
valid TLS certificate so GitLab can reach it over HTTPS.

---

## Security Notes

- The webhook token is verified on every request using constant-time comparison
- The agent never pushes to `dev` or `main` directly — only to its issue branch
- The agent never merges MRs — human approval is always required
- A maximum iteration guard (20 loops) prevents runaway Claude usage
- The `ai-fix` label gate prevents the agent from acting on every issue
- All secrets are in `.env` — never commit that file

---

## Extending the Agent

| Extension | How |
|---|---|
| Support multiple projects | Pass project ID dynamically from the webhook payload |
| Add code review step | Add a `review_diff` tool that reads the staged diff before committing |
| Limit to specific file types | Add file extension filtering in `tool_executor.py` |
| Add linting | Add a `run_linter` tool alongside `run_tests` |
| Support issue templates | Parse GitLab issue templates in the system prompt |
| Custom branch naming | Edit `_slugify` and the branch name format in `agent_loop.py` |

---

## Skill File (SKILL.md)

`SKILL.md` serves two purposes:

1. **Claude system prompt** — loaded at runtime and injected into every agent
   run as the standing policy document. Edit it to change agent behaviour.
2. **Copilot skill** — copied to `.github/skills/issue-first-branch-mr-workflow/SKILL.md`
   so GitHub Copilot in VS Code auto-discovers it and follows the same workflow
   when you work manually.

> Skill taken from [corvd-ai-skills](https://github.com/cdcent/corvd-ai-skills/blob/dev/README.md)
> and re-written for the GitLab, GitHub Copilot, and VS Code platform.

---

## License

MIT
