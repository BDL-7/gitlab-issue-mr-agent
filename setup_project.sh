#!/usr/bin/env bash
# =============================================================================
# setup_project.sh
# Run this once in an empty folder to scaffold the entire ai-agent project.
# Usage: bash setup_project.sh
# =============================================================================

set -e
PROJECT="gitlab-issue-mr-agent"
mkdir -p "$PROJECT"
cd "$PROJECT"

mkdir -p agent tests .github/skills/issue-first-branch-mr-workflow

echo ">>> Creating all project files..."

# =============================================================================
# .gitignore
# =============================================================================
cat > .gitignore << 'EOF'
.env
__pycache__/
*.py[cod]
*.egg-info/
dist/
build/
.venv/
venv/
*.log
.DS_Store
.pytest_cache/
.mypy_cache/
htmlcov/
.coverage
EOF

# =============================================================================
# requirements.txt
# =============================================================================
cat > requirements.txt << 'EOF'
fastapi==0.111.0
uvicorn==0.29.0
anthropic==0.25.8
python-gitlab==4.4.0
python-dotenv==1.0.1
httpx==0.27.0
gitpython==3.1.43
pytest==8.2.0
pytest-asyncio==0.23.6
httpx==0.27.0
EOF

# =============================================================================
# .env.example
# =============================================================================
cat > .env.example << 'EOF'
# -----------------------------------------------
# GitLab configuration
# -----------------------------------------------
GITLAB_URL=https://gitlab.com
# Personal Access Token — needs: api, write_repository, read_user scopes
GITLAB_TOKEN=your-gitlab-personal-access-token
# Numeric project ID (found in GitLab project → Settings → General)
GITLAB_PROJECT_ID=your-project-id
# A random secret string you define and paste into the GitLab webhook settings
GITLAB_WEBHOOK_SECRET=your-random-webhook-secret

# -----------------------------------------------
# Anthropic configuration
# -----------------------------------------------
ANTHROPIC_API_KEY=your-anthropic-api-key

# -----------------------------------------------
# Repository defaults
# -----------------------------------------------
# The integration branch the agent always targets
DEFAULT_BASE_BRANCH=dev

# -----------------------------------------------
# Notifications (optional)
# -----------------------------------------------
# Slack incoming webhook URL — leave blank to disable Slack notifications
SLACK_WEBHOOK_URL=
EOF

# =============================================================================
# Dockerfile
# =============================================================================
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install dependencies first (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source
COPY . .

# Expose FastAPI port
EXPOSE 8000

# Run the agent server
CMD ["uvicorn", "agent.server:app", "--host", "0.0.0.0", "--port", "8000", "--log-level", "info"]
EOF

# =============================================================================
# docker-compose.yml
# =============================================================================
cat > docker-compose.yml << 'EOF'
version: "3.9"

services:
  agent:
    build: .
    container_name: gitlab-issue-mr-agent
    ports:
      - "8000:8000"
    env_file:
      - .env
    restart: unless-stopped
    volumes:
      # Mount SKILL.md read-only so changes to the skill file take effect on restart
      - ./SKILL.md:/app/SKILL.md:ro
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

# =============================================================================
# .gitlab-ci.yml
# =============================================================================
cat > .gitlab-ci.yml << 'EOF'
# GitLab CI configuration
# Runs tests on every push and deploys the agent when dev is updated.

stages:
  - test
  - deploy

# -----------------------------------------------
# Test stage — runs on every branch push
# -----------------------------------------------
test:
  stage: test
  image: python:3.11-slim
  before_script:
    - pip install --no-cache-dir -r requirements.txt
  script:
    - pytest tests/ -v --tb=short
  rules:
    - if: '$CI_PIPELINE_SOURCE == "push"'

# -----------------------------------------------
# Deploy stage — only on dev branch
# -----------------------------------------------
deploy-agent:
  stage: deploy
  image: docker:24.0
  services:
    - docker:24.0-dind
  variables:
    DOCKER_TLS_CERTDIR: "/certs"
  before_script:
    - docker info
  script:
    - docker compose down || true
    - docker compose up -d --build
  rules:
    - if: '$CI_COMMIT_BRANCH == "dev"'
  environment:
    name: agent-server
EOF

# =============================================================================
# SKILL.md (loaded as Claude system prompt at runtime)
# =============================================================================
cat > SKILL.md << 'EOF'
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
EOF

# =============================================================================
# Copy SKILL.md into Copilot-discoverable location
# =============================================================================
cp SKILL.md .github/skills/issue-first-branch-mr-workflow/SKILL.md

# =============================================================================
# agent/__init__.py
# =============================================================================
cat > agent/__init__.py << 'EOF'
EOF

# =============================================================================
# agent/skill.py
# =============================================================================
cat > agent/skill.py << 'EOF'
"""
skill.py
Loads SKILL.md from the project root and returns it as a string.
This is injected into Claude's system prompt on every agent run,
giving Claude its standing operating instructions.
"""

import os

SKILL_PATH = os.path.join(os.path.dirname(__file__), "..", "SKILL.md")


def load_skill() -> str:
    """Read and return the full contents of SKILL.md."""
    with open(SKILL_PATH, "r", encoding="utf-8") as f:
        return f.read()
EOF

# =============================================================================
# agent/gitlab_api.py
# =============================================================================
cat > agent/gitlab_api.py << 'EOF'
"""
gitlab_api.py
Thin wrapper around python-gitlab for all operations the agent needs:
  - reading repository files
  - creating branches
  - committing file changes
  - creating merge requests
  - posting issue comments
  - triggering and polling CI pipelines
"""

import os
import time
import gitlab
from dotenv import load_dotenv

load_dotenv()

# Initialise the GitLab client once at import time
gl = gitlab.Gitlab(
    url=os.getenv("GITLAB_URL", "https://gitlab.com"),
    private_token=os.getenv("GITLAB_TOKEN"),
)
gl.auth()

project = gl.projects.get(os.getenv("GITLAB_PROJECT_ID"))


# ---------------------------------------------------------------------------
# Repository read operations
# ---------------------------------------------------------------------------

def get_repository_tree(path: str = "", recursive: bool = True) -> list[str]:
    """Return a flat list of all file paths in the repository (or a subdirectory)."""
    items = project.repository_tree(path=path, recursive=recursive, all=True)
    return [item["path"] for item in items if item["type"] == "blob"]


def get_file_content(file_path: str, ref: str = "dev") -> str:
    """
    Read and return the decoded UTF-8 content of a file at the given ref.
    Returns an error string if the file does not exist.
    """
    try:
        f = project.files.get(file_path=file_path, ref=ref)
        return f.decode().decode("utf-8")
    except Exception as e:
        return f"ERROR: could not read {file_path} — {e}"


def file_exists(file_path: str, ref: str) -> bool:
    """Return True if the file exists on the given branch."""
    try:
        project.files.get(file_path=file_path, ref=ref)
        return True
    except Exception:
        return False


# ---------------------------------------------------------------------------
# Branch operations
# ---------------------------------------------------------------------------

def create_branch(branch_name: str, base_branch: str = "dev") -> None:
    """Create a new branch from base_branch. Raises on failure."""
    project.branches.create({"branch": branch_name, "ref": base_branch})


# ---------------------------------------------------------------------------
# Commit operations
# ---------------------------------------------------------------------------

def commit_files(branch_name: str, commit_message: str, file_changes: list[dict]) -> None:
    """
    Commit one or more file changes to a branch in a single commit.

    Each item in file_changes must be a dict with:
      - action:    "create" | "update" | "delete"
      - file_path: path relative to repo root
      - content:   full file content (not required for delete)
    """
    project.commits.create({
        "branch": branch_name,
        "commit_message": commit_message,
        "actions": file_changes,
    })


# ---------------------------------------------------------------------------
# Merge request operations
# ---------------------------------------------------------------------------

def create_merge_request(branch_name: str, title: str, description: str) -> str:
    """
    Open a merge request from branch_name targeting the DEFAULT_BASE_BRANCH.
    Returns the web URL of the created MR.
    """
    target = os.getenv("DEFAULT_BASE_BRANCH", "dev")
    mr = project.mergerequests.create({
        "source_branch": branch_name,
        "target_branch": target,
        "title": title,
        "description": description,
        "remove_source_branch": True,
    })
    return mr.web_url


# ---------------------------------------------------------------------------
# Issue comment operations
# ---------------------------------------------------------------------------

def post_issue_comment(issue_number: int, comment: str) -> None:
    """Post a markdown comment on a GitLab issue."""
    issue = project.issues.get(issue_number)
    issue.notes.create({"body": comment})


# ---------------------------------------------------------------------------
# CI pipeline operations
# ---------------------------------------------------------------------------

def trigger_pipeline(branch_name: str) -> int:
    """Trigger a CI pipeline on the given branch and return the pipeline ID."""
    pipeline = project.pipelines.create({"ref": branch_name})
    return pipeline.id


def poll_pipeline(pipeline_id: int, timeout: int = 300) -> str:
    """
    Poll a pipeline until it completes or times out.
    Returns "TESTS PASSED", "TESTS FAILED: <jobs>", or "TESTS TIMEOUT".
    """
    start = time.time()
    while time.time() - start < timeout:
        time.sleep(15)
        p = project.pipelines.get(pipeline_id)
        status = p.status

        if status == "success":
            return "TESTS PASSED"

        if status in ("failed", "canceled", "skipped"):
            jobs = project.pipelines.get(pipeline_id).jobs.list()
            failed_names = [j.name for j in jobs if j.status == "failed"]
            return f"TESTS FAILED: {', '.join(failed_names)}"

    return "TESTS TIMEOUT: pipeline did not complete within the allowed window"
EOF

# =============================================================================
# agent/tools.py
# =============================================================================
cat > agent/tools.py << 'EOF'
"""
tools.py
Defines the tool schemas passed to Claude via the Anthropic API.
Each tool corresponds to an action Claude can take against the repository.
"""

TOOLS = [
    {
        "name": "list_files",
        "description": (
            "List all files in the repository or a subdirectory. "
            "Always call this first to understand the project structure "
            "before attempting to read or write any files."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": (
                        "Subdirectory path to list. "
                        "Pass an empty string to list the entire repository."
                    ),
                }
            },
            "required": [],
        },
    },
    {
        "name": "read_file",
        "description": (
            "Read the full content of a specific file in the repository. "
            "Read every file that could be relevant before writing any changes."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "file_path": {
                    "type": "string",
                    "description": "Path to the file relative to the repository root.",
                }
            },
            "required": ["file_path"],
        },
    },
    {
        "name": "write_file",
        "description": (
            "Write or update a file on the working branch. "
            "Always provide the complete file content — not a diff or partial update. "
            "Each call to write_file creates one commit. "
            "Use a clear, descriptive commit message for every change."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "file_path": {
                    "type": "string",
                    "description": "Path to the file relative to the repository root.",
                },
                "content": {
                    "type": "string",
                    "description": "Full file content after the fix is applied.",
                },
                "commit_message": {
                    "type": "string",
                    "description": (
                        "A concise, descriptive commit message explaining "
                        "what this specific change does and why."
                    ),
                },
            },
            "required": ["file_path", "content", "commit_message"],
        },
    },
    {
        "name": "run_tests",
        "description": (
            "Trigger the GitLab CI pipeline on the current branch and wait for results. "
            "Always run tests after completing all code changes and before opening the MR. "
            "If tests fail, diagnose the failure and fix before proceeding."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "branch_name": {
                    "type": "string",
                    "description": "The branch to run tests on.",
                }
            },
            "required": ["branch_name"],
        },
    },
    {
        "name": "open_merge_request",
        "description": (
            "Open a Merge Request once all fixes are committed and all tests pass. "
            "The MR title MUST exactly match the branch name. "
            "The description MUST summarize what was done to resolve the issue — "
            "not just what was asked, but what was actually changed and why."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "branch_name": {
                    "type": "string",
                    "description": "Source branch for the MR.",
                },
                "title": {
                    "type": "string",
                    "description": "MR title — must exactly match the branch name.",
                },
                "description": {
                    "type": "string",
                    "description": (
                        "Detailed summary of what was resolved, "
                        "what files were changed, and how the fix works."
                    ),
                },
            },
            "required": ["branch_name", "title", "description"],
        },
    },
]
EOF

# =============================================================================
# agent/tool_executor.py
# =============================================================================
cat > agent/tool_executor.py << 'EOF'
"""
tool_executor.py
Maps Claude tool calls to actual GitLab API operations.
Called from agent_loop.py whenever Claude returns a tool_use block.
"""

from agent.gitlab_api import (
    get_repository_tree,
    get_file_content,
    file_exists,
    commit_files,
    create_merge_request,
    trigger_pipeline,
    poll_pipeline,
)

# Track files written so far so we know whether to use "create" or "update"
_written_files: set = set()


def reset_state() -> None:
    """Reset file tracking between agent runs."""
    _written_files.clear()


def execute_tool(tool_name: str, tool_input: dict, branch_name: str) -> str:
    """
    Dispatch a tool call from Claude and return the result as a string.
    All results are returned as plain text so Claude can reason about them.
    """

    # ------------------------------------------------------------------
    if tool_name == "list_files":
        path = tool_input.get("path", "")
        files = get_repository_tree(path=path)
        if not files:
            return "No files found at that path."
        return "\n".join(files)

    # ------------------------------------------------------------------
    elif tool_name == "read_file":
        file_path = tool_input["file_path"]
        return get_file_content(file_path, ref=branch_name)

    # ------------------------------------------------------------------
    elif tool_name == "write_file":
        file_path = tool_input["file_path"]
        content = tool_input["content"]
        commit_message = tool_input["commit_message"]

        # Determine action: create for new files, update for existing ones
        if file_path in _written_files or file_exists(file_path, ref=branch_name):
            action = "update"
        else:
            action = "create"

        _written_files.add(file_path)

        try:
            commit_files(
                branch_name=branch_name,
                commit_message=commit_message,
                file_changes=[{
                    "action": action,
                    "file_path": file_path,
                    "content": content,
                }],
            )
            return (
                f"SUCCESS: {action}d {file_path}\n"
                f"Commit message: {commit_message}"
            )
        except Exception as e:
            return f"ERROR: failed to commit {file_path} — {e}"

    # ------------------------------------------------------------------
    elif tool_name == "run_tests":
        branch = tool_input.get("branch_name", branch_name)
        try:
            pipeline_id = trigger_pipeline(branch)
            result = poll_pipeline(pipeline_id)
            return result
        except Exception as e:
            return f"ERROR: could not trigger or poll pipeline — {e}"

    # ------------------------------------------------------------------
    elif tool_name == "open_merge_request":
        try:
            url = create_merge_request(
                branch_name=tool_input["branch_name"],
                title=tool_input["title"],
                description=tool_input["description"],
            )
            return f"MR created: {url}"
        except Exception as e:
            return f"ERROR: could not create MR — {e}"

    # ------------------------------------------------------------------
    return f"ERROR: unknown tool '{tool_name}'"
EOF

# =============================================================================
# agent/notifier.py
# =============================================================================
cat > agent/notifier.py << 'EOF'
"""
notifier.py
Sends notifications when the agent completes a run:
  - Always posts a comment on the GitLab issue
  - Optionally sends a Slack message if SLACK_WEBHOOK_URL is set
"""

import os
import httpx
from agent.gitlab_api import post_issue_comment


def notify_success(issue_number: int, branch_name: str, mr_url: str, issue_title: str) -> None:
    """Notify that the agent successfully opened an MR."""

    gitlab_comment = (
        f"✅ **AI Agent completed work on issue #{issue_number}.**\n\n"
        f"**Branch:** `{branch_name}`\n"
        f"**Merge Request:** {mr_url}\n\n"
        f"All changes have been committed and tests have passed. "
        f"Please review the MR, run any manual checks, and merge when satisfied.\n\n"
        f"> ⚠️ The agent has not merged anything automatically. "
        f"Final merge requires human approval."
    )
    post_issue_comment(issue_number, gitlab_comment)
    _slack_notify(
        f":white_check_mark: AI Agent opened MR for issue #{issue_number}: "
        f"_{issue_title}_\nBranch: `{branch_name}`\nMR: {mr_url}"
    )


def notify_failure(issue_number: int, branch_name: str, reason: str) -> None:
    """Notify that the agent could not complete the work."""

    gitlab_comment = (
        f"⚠️ **AI Agent could not complete issue #{issue_number}.**\n\n"
        f"**Branch:** `{branch_name}`\n"
        f"**Reason:** {reason}\n\n"
        f"Please review the branch and complete the fix manually."
    )
    post_issue_comment(issue_number, gitlab_comment)
    _slack_notify(
        f":warning: AI Agent failed on issue #{issue_number}. "
        f"Branch: `{branch_name}`. Reason: {reason}"
    )


def _slack_notify(message: str) -> None:
    """Post a message to Slack if a webhook URL is configured."""
    slack_url = os.getenv("SLACK_WEBHOOK_URL", "")
    if not slack_url:
        return
    try:
        httpx.post(slack_url, json={"text": message}, timeout=10)
    except Exception as e:
        print(f"[notifier] Slack notification failed: {e}")
EOF

# =============================================================================
# agent/agent_loop.py
# =============================================================================
cat > agent/agent_loop.py << 'EOF'
"""
agent_loop.py
Core agentic loop. Orchestrates the full issue-to-MR cycle:
  1. Creates a branch named <issue-number>-<issue-title-slug>
  2. Feeds Claude the issue context + SKILL.md as system prompt
  3. Runs Claude's tool-use loop until the MR is opened or max iterations hit
  4. Notifies via GitLab comment and Slack
"""

import os
import re
from anthropic import Anthropic
from dotenv import load_dotenv

from agent.gitlab_api import create_branch, post_issue_comment
from agent.tool_executor import execute_tool, reset_state
from agent.tools import TOOLS
from agent.skill import load_skill
from agent.notifier import notify_success, notify_failure

load_dotenv()

client = Anthropic()
MAX_ITERATIONS = 20


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _slugify(text: str) -> str:
    """Convert an issue title to a URL-safe branch slug."""
    text = text.lower().strip()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    text = re.sub(r"-+", "-", text)
    return text[:60].strip("-")


def _build_system_prompt(skill: str) -> str:
    return f"""
You are an autonomous software engineer AI agent operating inside a GitLab repository.
You follow the workflow described in the skill document below exactly.

---
{skill}
---

Your responsibilities for this run:
1. Start by listing the repository files to understand the project structure.
2. Read every file that is relevant to the issue before writing any changes.
3. Write the minimal correct fix that resolves the issue as described.
4. Commit each logical change with a clear, descriptive commit message.
5. Run tests after all changes are committed.
6. If tests fail, diagnose the failure, fix it, and run tests again.
7. Once tests pass, open a Merge Request:
   - Title: must exactly match the branch name
   - Description: must summarize what was done, what files changed, and how the fix works
8. Never merge the MR yourself. Always leave that to the human reviewer.
9. Do not change files unrelated to the issue.
10. Do not add speculative improvements — fix only what the issue describes.
""".strip()


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def run_agent(issue_number: int, issue_title: str, issue_description: str) -> None:
    """
    Full agent run for a single GitLab issue.
    Called as a background task from the webhook server.
    """

    reset_state()
    skill = load_skill()
    base_branch = os.getenv("DEFAULT_BASE_BRANCH", "dev")
    slug = _slugify(issue_title)
    branch_name = f"{issue_number}-{slug}"

    print(f"[agent] Starting run for issue #{issue_number}: {issue_title}")
    print(f"[agent] Branch: {branch_name}")

    # Notify the issue thread that the agent is starting
    post_issue_comment(
        issue_number,
        (
            f"🤖 **AI Agent starting work on this issue.**\n\n"
            f"**Branch:** `{branch_name}`\n"
            f"The agent will commit fixes, run tests, and open an MR. "
            f"You will be notified here when it is done."
        ),
    )

    # Create the branch
    try:
        create_branch(branch_name=branch_name, base_branch=base_branch)
        print(f"[agent] Branch '{branch_name}' created from '{base_branch}'")
    except Exception as e:
        msg = f"Failed to create branch `{branch_name}`: {e}"
        print(f"[agent] ERROR: {msg}")
        notify_failure(issue_number, branch_name, msg)
        return

    # Build the initial user message
    user_message = (
        f"Issue #{issue_number}: {issue_title}\n\n"
        f"Description:\n{issue_description}\n\n"
        f"Working branch: {branch_name}\n"
        f"Base branch: {base_branch}\n\n"
        f"Begin by listing the repository files, then read relevant files, "
        f"write the fix, run tests, and open the MR."
    )

    messages = [{"role": "user", "content": user_message}]
    system_prompt = _build_system_prompt(skill)
    mr_url = None
    iteration = 0

    # ------------------------------------------------------------------
    # Agentic tool-use loop
    # ------------------------------------------------------------------
    while True:
        iteration += 1
        if iteration > MAX_ITERATIONS:
            reason = f"Exceeded maximum iterations ({MAX_ITERATIONS}). Human review required."
            print(f"[agent] {reason}")
            notify_failure(issue_number, branch_name, reason)
            return

        print(f"[agent] Iteration {iteration} — calling Claude")

        response = client.messages.create(
            model="claude-opus-4-5",
            max_tokens=8096,
            system=system_prompt,
            tools=TOOLS,
            messages=messages,
        )

        # Add assistant turn to history
        messages.append({"role": "assistant", "content": response.content})

        # Agent decided it is done
        if response.stop_reason == "end_turn":
            print("[agent] Claude returned end_turn — loop complete")
            break

        # Claude wants to call tools
        if response.stop_reason == "tool_use":
            tool_results = []

            for block in response.content:
                if block.type != "tool_use":
                    continue

                tool_name = block.name
                tool_input = block.input
                tool_use_id = block.id

                print(f"[agent] Tool call: {tool_name}")
                print(f"[agent] Input: {tool_input}")

                result = execute_tool(
                    tool_name=tool_name,
                    tool_input=tool_input,
                    branch_name=branch_name,
                )

                print(f"[agent] Result: {result[:300]}")

                # Capture MR URL if the MR was just created
                if tool_name == "open_merge_request" and result.startswith("MR created:"):
                    mr_url = result.replace("MR created:", "").strip()

                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_use_id,
                    "content": result,
                })

            messages.append({"role": "user", "content": tool_results})

        else:
            print(f"[agent] Unexpected stop_reason: {response.stop_reason}")
            break

    # ------------------------------------------------------------------
    # Notify outcome
    # ------------------------------------------------------------------
    if mr_url:
        print(f"[agent] MR opened: {mr_url}")
        notify_success(
            issue_number=issue_number,
            branch_name=branch_name,
            mr_url=mr_url,
            issue_title=issue_title,
        )
    else:
        reason = "Agent completed its loop but did not open an MR. Please review the branch."
        print(f"[agent] WARNING: {reason}")
        notify_failure(issue_number, branch_name, reason)
EOF

# =============================================================================
# agent/server.py
# =============================================================================
cat > agent/server.py << 'EOF'
"""
server.py
FastAPI webhook receiver. GitLab posts here when an issue event fires.
The agent only activates on issues that are:
  - Newly opened (state == "opened")
  - Labelled with "ai-fix"
All agent work runs in a background task so the webhook returns immediately.
"""

import hmac
import os
from fastapi import FastAPI, Request, HTTPException, BackgroundTasks
from dotenv import load_dotenv
from agent.agent_loop import run_agent

load_dotenv()

app = FastAPI(title="GitLab Issue-to-MR AI Agent")
WEBHOOK_SECRET = os.getenv("GITLAB_WEBHOOK_SECRET", "")


def _verify_token(token: str) -> bool:
    """Constant-time comparison to prevent timing attacks."""
    return hmac.compare_digest(token, WEBHOOK_SECRET)


@app.get("/health")
def health():
    """Health check endpoint — used by Docker and load balancers."""
    return {"status": "ok"}


@app.post("/webhook")
async def gitlab_webhook(request: Request, background_tasks: BackgroundTasks):
    """
    Receive GitLab webhook payloads.
    Filters for issue events labelled 'ai-fix' and dispatches the agent.
    """

    # Authenticate the request
    token = request.headers.get("X-Gitlab-Token", "")
    if not _verify_token(token):
        raise HTTPException(status_code=401, detail="Invalid webhook token")

    # Only handle Issue Hook events
    event = request.headers.get("X-Gitlab-Event", "")
    if event != "Issue Hook":
        return {"status": "ignored", "reason": f"event type '{event}' not handled"}

    payload = await request.json()
    issue = payload.get("object_attributes", {})
    labels = [label["title"] for label in payload.get("labels", [])]

    # Only act on newly opened issues tagged ai-fix
    if issue.get("state") == "opened" and "ai-fix" in labels:
        issue_number = issue["iid"]
        issue_title = issue.get("title", "untitled-issue")
        issue_description = issue.get("description", "No description provided.")

        background_tasks.add_task(
            run_agent,
            issue_number=issue_number,
            issue_title=issue_title,
            issue_description=issue_description,
        )

        return {
            "status": "agent_started",
            "issue": issue_number,
            "title": issue_title,
        }

    return {"status": "ignored", "reason": "issue not labelled ai-fix or not newly opened"}
EOF

# =============================================================================
# tests/__init__.py
# =============================================================================
cat > tests/__init__.py << 'EOF'
EOF

# =============================================================================
# tests/test_server.py
# =============================================================================
cat > tests/test_server.py << 'EOF'
"""
test_server.py
Tests for the FastAPI webhook server.
Uses httpx TestClient — no live GitLab or Anthropic calls made.
"""

import os
import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch

os.environ.setdefault("GITLAB_URL", "https://gitlab.com")
os.environ.setdefault("GITLAB_TOKEN", "test-token")
os.environ.setdefault("GITLAB_PROJECT_ID", "1")
os.environ.setdefault("GITLAB_WEBHOOK_SECRET", "test-secret")
os.environ.setdefault("ANTHROPIC_API_KEY", "test-key")
os.environ.setdefault("DEFAULT_BASE_BRANCH", "dev")

from agent.server import app

client = TestClient(app)


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_wrong_token_rejected():
    r = client.post(
        "/webhook",
        headers={"X-Gitlab-Token": "wrong", "X-Gitlab-Event": "Issue Hook"},
        json={},
    )
    assert r.status_code == 401


def test_non_issue_event_ignored():
    r = client.post(
        "/webhook",
        headers={"X-Gitlab-Token": "test-secret", "X-Gitlab-Event": "Push Hook"},
        json={},
    )
    assert r.status_code == 200
    assert r.json()["status"] == "ignored"


def test_issue_without_ai_fix_label_ignored():
    payload = {
        "object_attributes": {"iid": 1, "state": "opened", "title": "Some issue", "description": ""},
        "labels": [],
    }
    r = client.post(
        "/webhook",
        headers={"X-Gitlab-Token": "test-secret", "X-Gitlab-Event": "Issue Hook"},
        json=payload,
    )
    assert r.status_code == 200
    assert r.json()["status"] == "ignored"


def test_ai_fix_issue_starts_agent():
    payload = {
        "object_attributes": {
            "iid": 42,
            "state": "opened",
            "title": "Fix the login bug",
            "description": "Users cannot log in when 2FA is enabled.",
        },
        "labels": [{"title": "ai-fix"}],
    }
    with patch("agent.server.run_agent") as mock_run:
        r = client.post(
            "/webhook",
            headers={"X-Gitlab-Token": "test-secret", "X-Gitlab-Event": "Issue Hook"},
            json=payload,
        )
    assert r.status_code == 200
    assert r.json()["status"] == "agent_started"
    assert r.json()["issue"] == 42
EOF

# =============================================================================
# tests/test_agent_loop.py
# =============================================================================
cat > tests/test_agent_loop.py << 'EOF'
"""
test_agent_loop.py
Tests for the slugify helper and branch name construction.
No live API calls.
"""

import pytest
from agent.agent_loop import _slugify


def test_slugify_basic():
    assert _slugify("Fix login bug") == "fix-login-bug"


def test_slugify_special_chars():
    assert _slugify("Fix: user's email (validation)!") == "fix-users-email-validation"


def test_slugify_long_title():
    long = "a" * 200
    result = _slugify(long)
    assert len(result) <= 60


def test_branch_name_format():
    issue_number = 42
    issue_title = "Fix FASTQ header validation"
    slug = _slugify(issue_title)
    branch = f"{issue_number}-{slug}"
    assert branch == "42-fix-fastq-header-validation"
EOF

# =============================================================================
# tests/test_tool_executor.py
# =============================================================================
cat > tests/test_tool_executor.py << 'EOF'
"""
test_tool_executor.py
Tests for tool dispatch logic.
All GitLab API calls are mocked.
"""

import pytest
from unittest.mock import patch
from agent.tool_executor import execute_tool, reset_state


def setup_function():
    reset_state()


def test_list_files_returns_joined_paths():
    with patch("agent.tool_executor.get_repository_tree", return_value=["a.py", "b.py"]):
        result = execute_tool("list_files", {}, "test-branch")
    assert "a.py" in result
    assert "b.py" in result


def test_read_file_delegates_correctly():
    with patch("agent.tool_executor.get_file_content", return_value="print('hello')") as mock:
        result = execute_tool("read_file", {"file_path": "main.py"}, "test-branch")
    mock.assert_called_once_with("main.py", ref="test-branch")
    assert result == "print('hello')"


def test_unknown_tool_returns_error():
    result = execute_tool("nonexistent_tool", {}, "test-branch")
    assert "ERROR" in result


def test_write_file_uses_create_for_new_file():
    with patch("agent.tool_executor.file_exists", return_value=False), \
         patch("agent.tool_executor.commit_files") as mock_commit:
        result = execute_tool(
            "write_file",
            {"file_path": "new.py", "content": "x=1", "commit_message": "add new.py"},
            "test-branch",
        )
    action = mock_commit.call_args[1]["file_changes"][0]["action"]
    assert action == "create"
    assert "SUCCESS" in result


def test_write_file_uses_update_for_existing_file():
    with patch("agent.tool_executor.file_exists", return_value=True), \
         patch("agent.tool_executor.commit_files") as mock_commit:
        result = execute_tool(
            "write_file",
            {"file_path": "existing.py", "content": "x=2", "commit_message": "update existing.py"},
            "test-branch",
        )
    action = mock_commit.call_args[1]["file_changes"][0]["action"]
    assert action == "update"
EOF

# =============================================================================
# README.md
# =============================================================================
cat > README.md << 'EOF'
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
EOF

echo ""
echo "=================================================="
echo " Project scaffolded successfully!"
echo "=================================================="
echo ""
echo " Folder: ./$PROJECT"
echo ""
echo " Next steps:"
echo "   1. cd $PROJECT"
echo "   2. cp .env.example .env  then fill in your secrets"
echo "   3. pip install -r requirements.txt"
echo "   4. uvicorn agent.server:app --reload --port 8000"
echo "   5. ngrok http 8000  and paste the URL into GitLab webhook settings"
echo "   6. Create a GitLab issue, add label 'ai-fix', and watch it go"
echo ""
