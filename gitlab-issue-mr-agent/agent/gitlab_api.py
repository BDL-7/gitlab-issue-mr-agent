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
