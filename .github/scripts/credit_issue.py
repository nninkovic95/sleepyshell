"""The one "API credit exhausted" issue: opened at the first skip, edited (never commented) on later skips so
it sends no notifications, closed by the first run that reaches the API again.

    credit_issue.py skip "<what was skipped>"
    credit_issue.py resumed
"""

from __future__ import annotations

import datetime as dt
import json
import re
import sys

from claude import gh, hidden_json, repo, run_url

LABEL = "credit-exhausted"
TITLE = "API credit exhausted — reviews paused"
KEEP = 30
DATA_RE = re.compile(r"<!-- credit-data: (.*?) -->", re.S)


def _open_issue():
    issues = gh("GET", f"repos/{repo()}/issues?labels={LABEL}&state=open&per_page=10") or []
    issues = [i for i in issues if "pull_request" not in i]
    return issues[0] if issues else None


def _body(data: dict) -> str:
    lines = [
        "The Anthropic API reported that the credit is exhausted, so Claude reviews, the weekly audit and "
        "release decisions are paused. Nothing is lost: when the credit is back, the next review covers "
        "everything since the last completed review, the next release covers everything since the last "
        "tag, and this issue closes by itself.",
        "",
        f"- First seen: {data['first']}",
        f"- Last seen: {data['last']}",
        f"- Runs skipped so far: {data['count']}",
        "",
        f"Skipped (newest first, last {KEEP}):",
        "",
    ]
    lines += [f"- {e['at']}: {e['what']} ([run]({e['run']}))" for e in data["entries"]]
    lines += ["", f"<!-- credit-data: {hidden_json(data)} -->"]
    return "\n".join(lines)


def record_skip(what: str) -> int | None:
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    entry = {"at": now, "what": what, "run": run_url()}
    issue = _open_issue()
    if issue is None:
        data = {"first": now, "last": now, "count": 1, "entries": [entry]}
        made = gh("POST", f"repos/{repo()}/issues", {"title": TITLE, "body": _body(data), "labels": [LABEL]})
        return made["number"]
    m = DATA_RE.search(issue.get("body") or "")
    data = json.loads(m.group(1)) if m else {"first": now, "count": 0, "entries": []}
    data["last"] = now
    data["count"] = int(data.get("count", 0)) + 1
    data["entries"] = ([entry] + data.get("entries", []))[:KEEP]
    gh("PATCH", f"repos/{repo()}/issues/{issue['number']}", {"body": _body(data)})
    return issue["number"]


def close_if_open() -> None:
    issue = _open_issue()
    if issue is None:
        return
    gh("POST", f"repos/{repo()}/issues/{issue['number']}/comments", {"body": f"Credit is back; resumed at {run_url()}."})
    gh("PATCH", f"repos/{repo()}/issues/{issue['number']}", {"state": "closed", "state_reason": "completed"})


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "skip":
        n = record_skip(sys.argv[2])
        print(f"credit issue #{n} updated")
    elif len(sys.argv) == 2 and sys.argv[1] == "resumed":
        close_if_open()
    else:
        sys.exit(__doc__)
