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
