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
