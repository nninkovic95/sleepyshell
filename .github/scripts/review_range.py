"""What a push still needs reviewed, so nothing is skipped and nothing is paid for twice.

The record of what was reviewed is the "Claude review" check run on a commit: success or failure means a
review completed there. Cancelled runs and runs stopped by an exhausted credit leave no completed check,
so their changes roll into the next run.

    review_range.py classify --head SHA    (main pushes: prints mode= and p2= for $GITHUB_OUTPUT)
"""

from __future__ import annotations

import argparse
import time
import urllib.parse

from claude import (
    CHECK_NAME,
    devonly_patterns,
    gh,
    git,
    git_ok,
    is_ancestor,
    keep_devonly,
    output,
    repo,
    strip_tree,
    summary,
    tree_of,
)

WAIT_SECONDS = 45 * 60
POLL_SECONDS = 60
WALK_LIMIT = 300


def check_state(sha: str):
    """(status, conclusion, html_url) of the newest "Claude review" check run on sha, or None."""
    name = urllib.parse.quote(CHECK_NAME)
    res = gh("GET", f"repos/{repo()}/commits/{sha}/check-runs?check_name={name}&per_page=20", check=False)
    runs = (res or {}).get("check_runs") or []
    if not runs:
        return None
    newest = max(runs, key=lambda r: r["id"])
    return newest["status"], newest.get("conclusion"), newest.get("html_url")


def is_reviewed(sha: str) -> bool:
    st = check_state(sha)
    return bool(st and st[0] == "completed" and st[1] in ("success", "failure"))


def last_reviewed(head: str) -> str | None:
    """The newest commit on head's first-parent line with a completed review."""
    for sha in git("rev-list", "--first-parent", f"--max-count={WALK_LIMIT}", head).split():
        if is_reviewed(sha):
            return sha
    return None


def review_base(head: str, branch: str, before: str | None) -> tuple[str | None, str, bool]:
    """(base tree-ish to diff against, how it was chosen, whether no review has completed yet). A None base
    means there is nothing to diff from. The first review reads the whole codebase; later ones the diff and
    what it needs (context.py)."""
    base = last_reviewed(head)
    if base is None:
        if branch == "dev" and git_ok("rev-parse", "--verify", "--quiet", "origin/main"):
            # main is covered by the weekly audit; review what dev has on top of it
            tip = git("rev-parse", "origin/main").strip()
            return tip, f"no earlier review on dev; reviewing what dev adds to main ({tip[:12]})", True
        if before and git_ok("cat-file", "-e", f"{before}^{{commit}}") and is_ancestor(before, head):
            return before, f"no earlier review; starting from the push's previous tip ({before[:12]})", True
        parent = git("rev-parse", f"{head}^", check=False).strip()
        if parent:
            return parent, "no earlier review; starting from the parent commit", True
        return None, "no earlier review and no parent", True
    if branch == "dev" and git_ok("rev-parse", "--verify", "--quiet", "origin/main"):
        # main commits brought in by a back-sync were reviewed on main already: subtract them
        main_rev = last_reviewed("origin/main")
        if main_rev and not is_ancestor(main_rev, base) and is_ancestor(main_rev, head):
            out = git("merge-tree", "--write-tree", "--no-messages", base, main_rev, check=False)
            merged = out.split("\n", 1)[0].strip()
            if merged and git_ok("merge-tree", "--write-tree", "--no-messages", base, main_rev):
                pats = devonly_patterns(head, "origin/main")
                tree = keep_devonly(merged, base, pats)
                return tree, (
                    f"since the last dev review ({base[:12]}), minus main's reviewed commits up to {main_rev[:12]}"
                ), False
    return base, f"since the last completed review ({base[:12]})", False


def dev_run_active(sha: str) -> bool:
    res = gh("GET", f"repos/{repo()}/actions/runs?head_sha={sha}&per_page=20", check=False) or {}
    return any(r.get("status") in ("queued", "in_progress", "waiting", "pending", "requested")
               for r in res.get("workflow_runs") or [])


def classify(head: str) -> tuple[str, str]:
    """mode for a main push: covered | carry-fail | review, and the dev commit it leans on."""
    parents = git("rev-list", "--parents", "-n1", head).split()[1:]
    if len(parents) != 2:
        return "review", ""
    p2 = parents[1]
    if not git_ok("rev-parse", "--verify", "--quiet", "origin/dev") or not is_ancestor(p2, "origin/dev"):
        return "review", ""
    pats = devonly_patterns(head, "origin/dev")
    if tree_of(head) != strip_tree(p2, pats):
        summary(f"The merge's tree differs from dev {p2[:12]} minus dev-only paths: full review.")
        return "review", ""
    waited = 0
    while True:
        st = check_state(p2)
        if st and st[0] == "completed" and st[1] == "success":
            return "covered", p2
        if st and st[0] == "completed" and st[1] == "failure":
            return "carry-fail", p2
        if (st and st[0] != "completed") or dev_run_active(p2):
            if waited >= WAIT_SECONDS:
                summary(f"The dev review of {p2[:12]} did not finish within 45 minutes: full review.")
                return "review", ""
            time.sleep(POLL_SECONDS)
            waited += POLL_SECONDS
            continue
        return "review", ""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["classify"])
    ap.add_argument("--head", required=True)
    args = ap.parse_args()
    mode, p2 = classify(args.head)
    output("mode", mode)
    output("p2", p2)
    labels = {
        "covered": f"merge of dev {p2[:12]}, which already passed its review: guard only, no API call",
        "carry-fail": f"merge of dev {p2[:12]}, whose review found serious issues: carried over, no release",
        "review": "direct push (or a merge whose dev side has no passing review): full review",
    }
    summary(f"**Main push:** {labels[mode]}.")
    print(f"mode={mode} p2={p2}")


if __name__ == "__main__":
    main()
