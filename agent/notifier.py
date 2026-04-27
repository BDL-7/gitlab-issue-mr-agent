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
