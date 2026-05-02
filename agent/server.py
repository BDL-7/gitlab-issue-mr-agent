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
from collections import deque
from fastapi import FastAPI, Request, HTTPException, BackgroundTasks
from dotenv import load_dotenv
from agent.agent_loop import run_agent
from agent.readme_review import run_readme_review_for_push

load_dotenv()

app = FastAPI(title="GitLab Issue-to-MR AI Agent")
WEBHOOK_SECRET = os.getenv("GITLAB_WEBHOOK_SECRET", "")
README_REVIEW_ENABLED = os.getenv("README_REVIEW_ENABLED", "true").lower() in {
    "1",
    "true",
    "yes",
    "on",
}
README_REVIEW_BRANCH = os.getenv("README_REVIEW_BRANCH", "dev")
README_REVIEW_PATH = os.getenv("README_REVIEW_PATH", "README.md")
_RECENT_PUSH_SHA_LIMIT = 500
_recent_push_shas = deque(maxlen=_RECENT_PUSH_SHA_LIMIT)
_recent_push_set = set()


def _verify_token(token: str) -> bool:
    """Constant-time comparison to prevent timing attacks."""
    return hmac.compare_digest(token, WEBHOOK_SECRET)


def _is_duplicate_push(sha: str) -> bool:
    """Return True if SHA was already processed in this process lifetime window."""
    if not sha:
        return False

    if sha in _recent_push_set:
        return True

    if len(_recent_push_shas) == _recent_push_shas.maxlen:
        evicted = _recent_push_shas[0]
        _recent_push_set.discard(evicted)

    _recent_push_shas.append(sha)
    _recent_push_set.add(sha)
    return False


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

    # Route by event type
    event = request.headers.get("X-Gitlab-Event", "")
    payload = await request.json()

    if event == "Push Hook":
        if not README_REVIEW_ENABLED:
            return {"status": "ignored", "reason": "README review disabled"}

        ref = payload.get("ref", "")
        branch = (
            ref.replace("refs/heads/", "") if ref.startswith("refs/heads/") else ref
        )
        if branch != README_REVIEW_BRANCH:
            return {
                "status": "ignored",
                "reason": f"push to '{branch}' does not match review branch '{README_REVIEW_BRANCH}'",
            }

        after_sha = payload.get("after", "")
        if _is_duplicate_push(after_sha):
            return {
                "status": "ignored",
                "reason": f"duplicate push delivery for commit '{after_sha}'",
            }

        background_tasks.add_task(
            run_readme_review_for_push, payload, README_REVIEW_PATH
        )
        return {
            "status": "readme_review_started",
            "branch": branch,
            "after": after_sha,
        }

    if event != "Issue Hook":
        return {"status": "ignored", "reason": f"event type '{event}' not handled"}

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

    return {
        "status": "ignored",
        "reason": "issue not labelled ai-fix or not newly opened",
    }
