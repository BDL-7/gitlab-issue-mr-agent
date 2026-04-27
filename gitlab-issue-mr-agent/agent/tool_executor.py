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
