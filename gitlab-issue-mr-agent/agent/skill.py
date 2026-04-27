"""
skill.py
Loads SKILL.md from the project root and returns it as a string.
This is injected into Claude's system prompt on every agent run,
giving Claude its standing operating instructions.
"""

import os

SKILL_PATH = os.path.join(os.path.dirname(__file__), "..", "SKILL.md")


def load_skill() -> str:
    """Read and return the full contents of SKILL.md."""
    with open(SKILL_PATH, "r", encoding="utf-8") as f:
        return f.read()
