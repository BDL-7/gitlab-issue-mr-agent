"""
test_readme_review.py
Tests deterministic README drift review logic.
"""

from unittest.mock import patch

from agent.readme_review import evaluate_readme_drift, run_readme_review_for_push


def test_outdated_when_docs_relevant_changes_without_readme():
    payload = {
        "ref": "refs/heads/dev",
        "after": "abc12345",
        "commits": [{"added": [], "modified": ["agent/server.py"], "removed": []}],
    }
    result = evaluate_readme_drift(payload)
    assert result["status"] == "outdated"
    assert result["readme_updated"] is False
    assert "agent/server.py" in result["docs_relevant_files"]
    assert len(result["suggestions"]) > 0


def test_up_to_date_when_readme_changed_in_same_push():
    payload = {
        "ref": "refs/heads/dev",
        "after": "abc12345",
        "commits": [
            {
                "added": [],
                "modified": ["agent/server.py", "README.md"],
                "removed": [],
            }
        ],
    }
    result = evaluate_readme_drift(payload)
    assert result["status"] == "up_to_date"
    assert result["readme_updated"] is True


def test_up_to_date_for_test_only_changes():
    payload = {
        "ref": "refs/heads/dev",
        "after": "abc12345",
        "commits": [{"added": [], "modified": ["tests/test_server.py"], "removed": []}],
    }
    result = evaluate_readme_drift(payload)
    assert result["status"] == "up_to_date"
    assert result["reason"] == "no docs-relevant files changed"


def test_push_review_posts_comment_only_when_outdated():
    payload = {
        "ref": "refs/heads/dev",
        "after": "abc12345",
        "commits": [{"added": [], "modified": ["agent/server.py"], "removed": []}],
    }
    with patch("agent.readme_review.post_commit_comment") as mock_post:
        result = run_readme_review_for_push(payload)
    assert result["status"] == "outdated"
    assert mock_post.call_count == 1


def test_push_review_skips_comment_when_up_to_date():
    payload = {
        "ref": "refs/heads/dev",
        "after": "abc12345",
        "commits": [{"added": [], "modified": ["README.md"], "removed": []}],
    }
    with patch("agent.readme_review.post_commit_comment") as mock_post:
        result = run_readme_review_for_push(payload)
    assert result["status"] == "up_to_date"
    assert mock_post.call_count == 0


def test_docs_skip_token_suppresses_review_comment():
    payload = {
        "ref": "refs/heads/dev",
        "after": "abc12345",
        "commits": [
            {
                "added": [],
                "modified": ["agent/server.py"],
                "removed": [],
                "message": "refactor webhook flow [docs-skip]",
            }
        ],
    }
    with patch("agent.readme_review.post_commit_comment") as mock_post:
        result = run_readme_review_for_push(payload)
    assert result["status"] == "skipped"
    assert "docs-skip" in result["reason"]
    assert mock_post.call_count == 0
