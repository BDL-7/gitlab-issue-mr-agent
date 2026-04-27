"""
test_agent_loop.py
Tests for the slugify helper and branch name construction.
No live API calls.
"""

import pytest
from agent.agent_loop import _slugify


def test_slugify_basic():
    assert _slugify("Fix login bug") == "fix-login-bug"


def test_slugify_special_chars():
    assert _slugify("Fix: user's email (validation)!") == "fix-users-email-validation"


def test_slugify_long_title():
    long = "a" * 200
    result = _slugify(long)
    assert len(result) <= 60


def test_branch_name_format():
    issue_number = 42
    issue_title = "Fix FASTQ header validation"
    slug = _slugify(issue_title)
    branch = f"{issue_number}-{slug}"
    assert branch == "42-fix-fastq-header-validation"
