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
        json={"ref": "refs/heads/feature-x", "after": "abc123", "commits": []},
    )
    assert r.status_code == 200
    assert r.json()["status"] == "ignored"


def test_push_to_dev_starts_readme_review():
    payload = {
        "ref": "refs/heads/dev",
        "after": "d34db33f",
        "commits": [{"added": [], "modified": ["agent/server.py"], "removed": []}],
    }
    with patch("agent.server.run_readme_review_for_push"):
        r = client.post(
            "/webhook",
            headers={"X-Gitlab-Token": "test-secret", "X-Gitlab-Event": "Push Hook"},
            json=payload,
        )
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "readme_review_started"
    assert body["branch"] == "dev"
    assert body["after"] == "d34db33f"


def test_duplicate_push_delivery_is_ignored():
    payload = {
        "ref": "refs/heads/dev",
        "after": "feedbeef",
        "commits": [{"added": [], "modified": ["agent/server.py"], "removed": []}],
    }

    with patch("agent.server.run_readme_review_for_push"):
        first = client.post(
            "/webhook",
            headers={"X-Gitlab-Token": "test-secret", "X-Gitlab-Event": "Push Hook"},
            json=payload,
        )
        second = client.post(
            "/webhook",
            headers={"X-Gitlab-Token": "test-secret", "X-Gitlab-Event": "Push Hook"},
            json=payload,
        )

    assert first.status_code == 200
    assert first.json()["status"] == "readme_review_started"
    assert second.status_code == 200
    assert second.json()["status"] == "ignored"
    assert "duplicate push delivery" in second.json()["reason"]


def test_issue_without_ai_fix_label_ignored():
    payload = {
        "object_attributes": {
            "iid": 1,
            "state": "opened",
            "title": "Some issue",
            "description": "",
        },
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
