#!/usr/bin/env python3
"""Turn a Claude Code agent markdown file into the JSON `claude --agents` accepts.

Usage: bin/agent-json.py .claude/agents-candidates/<name>.md

Frontmatter keys name, description, tools (comma list), model, maxTurns are mapped; the markdown
body becomes the agent's prompt. This lets bin/admit.sh run a *candidate* headlessly without
installing it under .claude/agents/ first. Kept deliberately small: no YAML library, frontmatter is
`key: value` lines between two `---` lines.
"""

import json
import sys


def parse(path):
    text = open(path, encoding="utf-8").read()
    if not text.startswith("---\n"):
        raise SystemExit(f"{path}: no frontmatter")
    _, front, body = text.split("---\n", 2)
    meta = {}
    for line in front.splitlines():
        if ":" in line and not line.startswith(" "):
            key, value = line.split(":", 1)
            meta[key.strip()] = value.strip()
    if "name" not in meta or "description" not in meta:
        raise SystemExit(f"{path}: frontmatter needs name and description")
    agent = {"description": meta["description"], "prompt": body.strip()}
    if meta.get("tools"):
        agent["tools"] = [t.strip() for t in meta["tools"].split(",") if t.strip()]
    if meta.get("model"):
        agent["model"] = meta["model"]
    if meta.get("maxTurns"):
        agent["maxTurns"] = int(meta["maxTurns"])
    return meta["name"], agent


if __name__ == "__main__":
    name, agent = parse(sys.argv[1])
    print(json.dumps({name: agent}))
