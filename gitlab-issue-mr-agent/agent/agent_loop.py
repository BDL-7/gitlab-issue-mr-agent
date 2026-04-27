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
