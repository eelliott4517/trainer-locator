"""Print one version's notes from CHANGELOG.md (for the GitHub release and CurseForge).

    python3 tools/changelog.py 1.0.0
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def notes(version):
    text = open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read()
    m = re.search(rf"^## {re.escape(version)}\b.*?\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        raise SystemExit(f"CHANGELOG.md has no section for {version}")
    return m.group(1).strip() + "\n"


if __name__ == "__main__":
    sys.stdout.write(notes(sys.argv[1].lstrip("v")))
