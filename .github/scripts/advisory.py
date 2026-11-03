"""Files security findings privately, as draft repository security advisories, so they never reach a public
check run, issue, run summary or log while they are unfixed. Runs in its own workflow step with the
ADVISORY_TOKEN secret as GH_TOKEN (a fine-grained token limited to this repository's security advisories);
that step never gets the Anthropic federation inputs, and this script never prints the token or a finding.

    advisory.py file FILE              file the report review.py or audit.py left in FILE (none: nothing to do)
    advisory.py previous-audit OUT     write the previous audit's findings data to OUT for audit.py --previous

System python3 and the gh CLI only; the Anthropic SDK is not needed here.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

import claude
from claude import ReviewError, gh, repo, summary

AUDIT_PREFIX = "Weekly audit "
DATA_RE = re.compile(r"<!-- audit-data: (.*?) -->", re.S)
MAX_DESCRIPTION = 60000
# a repository advisory must name a package; the shell is not published in any package ecosystem
PACKAGE = [{"package": {"ecosystem": "other", "name": "sleepyshell"}}]


def require_token() -> None:
    if not os.environ.get("GH_TOKEN", "").strip():
        raise ReviewError("the ADVISORY_TOKEN secret is not set, so security findings cannot be filed privately")


def drafts() -> list[dict]:
    out = gh("GET", f"repos/{repo()}/security-advisories?state=draft&sort=created&direction=desc&per_page=100") or []
    return [a for a in out if isinstance(a, dict)]


def is_audit(adv: dict) -> bool:
    return (adv.get("summary") or "").startswith(AUDIT_PREFIX) and "(simulated)" not in (adv.get("summary") or "")


def audit_data(description: str) -> list | None:
    """The findings data of an audit advisory: the last marker in it, or None when it has none or it is broken."""
    found = DATA_RE.findall(description or "")
    if not found:
        return None
    try:
        data = json.loads(found[-1])
    except ValueError:
        return None
    return data if isinstance(data, list) else None


def previous_audit(out: str) -> int:
    require_token()
    data: list = []
    # the newest advisory that carries audit data (review advisories carry none; the private copy of the
    # first audit does); a simulated audit's test data never counts
    for adv in drafts():
        if "(simulated)" in (adv.get("summary") or ""):
            continue
        found = audit_data(adv.get("description") or "")
        if found is not None:
            data = found
            break
    Path(out).write_text(json.dumps(data), encoding="utf-8")
    print(f"previous audit findings: {len(data)}")
    return 0


def file_report(path: str) -> int:
    p = Path(path)
    if not p.exists():
        print("nothing to file privately")
        return 0
    require_token()
    report = json.loads(p.read_text(encoding="utf-8"))
    description = report["description"]
    if len(description) > MAX_DESCRIPTION:
        description = description[: MAX_DESCRIPTION - 200] + "\n\n… cut to fit an advisory."
    made = gh(
        "POST",
        f"repos/{repo()}/security-advisories",
        {"summary": report["summary"][:1024], "description": description, "vulnerabilities": PACKAGE},
    )
    p.unlink()
    closed = 0
    if is_audit(made):
        # last week's audit is superseded by this one; the first private copy and review advisories stay open
        for adv in drafts():
            if adv.get("ghsa_id") != made.get("ghsa_id") and is_audit(adv):
                gh("PATCH", f"repos/{repo()}/security-advisories/{adv['ghsa_id']}", {"state": "closed"})
                closed += 1
    print("filed privately as a draft security advisory" + (f"; closed {closed} older audit advisory" if closed else ""))
    summary("Security findings were filed privately as a draft security advisory.")
    return 0


def main(argv: list[str]) -> None:
    try:
        if len(argv) == 2 and argv[0] == "file":
            sys.exit(file_report(argv[1]))
        if len(argv) == 2 and argv[0] == "previous-audit":
            sys.exit(previous_audit(argv[1]))
        print(__doc__.strip())
        sys.exit(2)
    except ReviewError as exc:
        claude.fail(f"{exc}. Fix the ADVISORY_TOKEN secret, then re-run this job.")
    except Exception as exc:  # no traceback: it could hold a report's text
        claude.fail(f"filing privately failed ({type(exc).__name__}). Fix the cause, then re-run this job.")


if __name__ == "__main__":
    main(sys.argv[1:])
