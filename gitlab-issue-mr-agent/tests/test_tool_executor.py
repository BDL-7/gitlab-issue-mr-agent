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
