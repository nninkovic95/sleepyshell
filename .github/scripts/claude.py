"""Shared helpers for the review, release and audit scripts.

Claude is reached through Workload Identity Federation: a fresh GitHub OIDC token is exchanged for a
short-lived Anthropic token, no API key exists anywhere. GitHub is reached through the `gh` CLI with the
job's GITHUB_TOKEN. Nothing here retries or falls back when the API credit is exhausted; callers check
is_credit_exhausted() and stop quietly.
"""

from __future__ import annotations

import fnmatch
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

MODELS = {
    "haiku": "claude-haiku-5-5",
    "sonnet": "claude-sonnet-5-5",
    "opus": "claude-opus-5-5",
    "fable": "claude-fable-5-1",
}
TIERS = ["haiku", "sonnet", "opus", "fable"]
# USD per million tokens (input, output), for the cost line in run summaries only
PRICES = {
    "claude-haiku-5-5": (0.10, 0.50),
    "claude-sonnet-5-5": (2.0, 10.0),
    "claude-opus-5-5": (4.0, 20.0),
    "claude-fable-5-1": (10.0, 50.0),
}
# a request whose input is above the threshold is priced at the second pair
LONG_PRICES = {"claude-haiku-5-5": (100_000, (0.50, 2.50))}
OIDC_AUDIENCE = "https://api.anthropic.com"
FALLBACK_BETA = "server-side-fallback-2026-07-01"
# the models that accept the server-side refusal fallback; Haiku has none
FALLBACK_MODELS = frozenset({"claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5"})
CHECK_NAME = "Claude review"
DEVONLY_FILE = ".github/dev-only"
REPO_ROOT = Path(__file__).resolve().parents[2]
# never sent to the model: a generated icon index, large and meaningless to review
BUNDLE_SKIP = {"data/icons.json"}
BUNDLE_MAX_FILE = 300_000
# left out of the codebase context of reviews and the audit: data, palettes, templates, the work list and the
# dependency hash list hold no logic to review (a push that changes them still shows them in its diff)
REVIEW_SKIP_DIRS = ("themes/", "templates/", "data/", "assets/", "gallery/", "docs/")
REVIEW_SKIP_FILES = frozenset({".github/scripts/requirements.txt", "TASKS.md", "LICENSE"})
# findings in these categories go only to a private draft security advisory, never to a check run, an
# issue, a run summary or a log, while they are unfixed
PRIVATE_CATEGORIES = frozenset({"security", "ask-first", "personal-path"})
WITHHELD_SUMMARY = "The reviewer's summary is not shown here: it covers findings that were filed privately."
CONTEXT_WINDOW = 1_000_000
# each model's context window as the API reports it (check_models fills it); CONTEXT_WINDOW where unknown
WINDOWS: dict[str, int] = {}
POLL_SECONDS = 60


class CreditExhausted(Exception):
    """The API said the credit is used up."""


class ReviewError(Exception):
    """A failure that must surface as an error (red), with a readable message."""


# ---------------------------------------------------------------- Claude ---


def is_credit_exhausted(exc: BaseException) -> bool:
    """True only for the two known out-of-credit answers; everything else is a real error."""
    import anthropic

    if not isinstance(exc, anthropic.APIStatusError):
        return False
    if exc.status_code == 402 and exc.type == "billing_error":
        return True
    if exc.status_code == 400 and "credit balance is too low" in str(exc).lower():
        return True
    return False


def _github_oidc_token() -> str:
    """A fresh GitHub OIDC token for the Anthropic audience. GitHub's tokens are single-use, so this is
    called again for every exchange."""
    url = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_URL")
    bearer = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_TOKEN")
    if not url or not bearer:
        raise ReviewError("no GitHub OIDC token available: the job needs `permissions: id-token: write`")
    sep = "&" if "?" in url else "?"
    req = urllib.request.Request(
        f"{url}{sep}audience={urllib.parse.quote(OIDC_AUDIENCE, safe='')}",
        headers={"Authorization": f"bearer {bearer}"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)["value"]


def client():
    """An Anthropic client authenticated by WIF from the four repository variables."""
    import anthropic
    from anthropic.lib.credentials import WorkloadIdentityCredentials

    for var in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE"):
        os.environ.pop(var, None)
    need = {
        "federation_rule_id": "ANTHROPIC_FEDERATION_RULE_ID",
        "organization_id": "ANTHROPIC_ORGANIZATION_ID",
        "service_account_id": "ANTHROPIC_SERVICE_ACCOUNT_ID",
    }
    kwargs = {}
    for key, var in need.items():
        val = os.environ.get(var, "").strip()
        if not val:
            raise ReviewError(f"repository variable {var} is not set")
        kwargs[key] = val
    workspace = os.environ.get("ANTHROPIC_WORKSPACE_ID", "").strip()
    if workspace:
        kwargs["workspace_id"] = workspace
    creds = WorkloadIdentityCredentials(identity_token_provider=_github_oidc_token, **kwargs)
    return anthropic.Anthropic(credentials=creds, timeout=3600.0)


def auth_hint(exc: BaseException) -> str | None:
    """A readable message for an authentication failure, else None."""
    import anthropic
    from anthropic.lib.credentials import WorkloadIdentityError

    if isinstance(exc, (WorkloadIdentityError, anthropic.AuthenticationError, anthropic.PermissionDeniedError)):
        return (
            "WIF auth failed: re-check the four IDs (federation rule, organization, service account, "
            f"workspace; transcribed from a screenshot) in the repository variables. Detail: {exc}"
        )
    return None


def check_models(cl, wanted) -> list[str]:
    """Fail early when a model this run needs is not offered to this organization."""
    listed = list(cl.models.list())
    have = {m.id for m in listed}
    for m in listed:
        window = getattr(m, "max_input_tokens", None)
        if isinstance(window, int) and window > 0:
            WINDOWS[m.id] = window
    missing = [m for m in wanted if m not in have]
    if missing:
        raise ReviewError(f"model(s) not available to this organization: {', '.join(missing)}")
    return sorted(m for m in have if m in PRICES)


@dataclass
class Result:
    data: dict
    model: str
    input_tokens: int
    output_tokens: int
    batch: bool = False

    def cost(self) -> float:
        pin, pout = PRICES.get(self.model, (0.0, 0.0))
        long = LONG_PRICES.get(self.model)
        if long and self.input_tokens > long[0]:
            pin, pout = long[1]
        full = (self.input_tokens * pin + self.output_tokens * pout) / 1e6
        return full / 2 if self.batch else full

    def usage_line(self) -> str:
        how = ", batch price" if self.batch else ""
        return (
            f"`{self.model}`: {self.input_tokens:,} input + {self.output_tokens:,} output tokens "
            f"(about ${self.cost():.2f}{how})"
        )


def hidden_json(value) -> str:
    """JSON that is safe inside an HTML comment: "--" cannot appear, so "-->" cannot end it early."""
    return json.dumps(value).replace("--", "-\\u002d")


def split_private(findings) -> tuple[list, list]:
    """(public, private) findings, by category."""
    public = [f for f in findings if f["category"] not in PRIVATE_CATEGORIES]
    private = [f for f in findings if f["category"] in PRIVATE_CATEGORIES]
    return public, private


def private_line(private) -> str:
    """The one public line about private findings: a count, nothing else."""
    if not private:
        return ""
    serious = sum(1 for f in private if f["severity"] == "serious")
    n = len(private)
    return (
        f"**{n} security finding{'s' if n != 1 else ''}"
        + (f" ({serious} serious)" if serious else "")
        + " filed privately** in a draft security advisory."
    )


def write_private(path: str, title: str, description: str) -> None:
    """Hand a private report to the filing step (advisory.py) through a file in the runner's temp folder,
    which is never uploaded."""
    if not path:
        raise ReviewError("findings to file privately, but no --private-out file was given")
    Path(path).write_text(json.dumps({"summary": title, "description": description}), encoding="utf-8")


def _api(fn):
    """Run one API call, turning an out-of-credit answer into CreditExhausted and an auth failure into a
    readable ReviewError; everything else propagates."""
    try:
        return fn()
    except Exception as exc:
        if is_credit_exhausted(exc):
            raise CreditExhausted(str(exc)) from exc
        hint = auth_hint(exc)
        if hint:
            raise ReviewError(hint) from exc
        raise


def _params(model: str, effort: str, system: str, user: str, schema: dict, max_tokens: int) -> dict:
    return {
        "model": model,
        "max_tokens": max_tokens,
        "system": system,
        "messages": [{"role": "user", "content": user}],
        "thinking": {"type": "adaptive"},
        "output_config": {"effort": effort, "format": {"type": "json_schema", "schema": schema}},
    }


def count_input(cl, model: str, system: str, user: str, schema: dict) -> int:
    """Exact input tokens for this model (the count endpoint is free)."""
    res = _api(
        lambda: cl.beta.messages.count_tokens(
            model=model,
            system=system,
            messages=[{"role": "user", "content": user}],
            thinking={"type": "adaptive"},
            output_config={"format": {"type": "json_schema", "schema": schema}},
        )
    )
    return res.input_tokens


def window_of(model: str) -> int:
    return WINDOWS.get(model, CONTEXT_WINDOW)


def fits(cl, model: str, system: str, user: str, schema: dict, max_tokens: int) -> tuple[bool, int]:
    """Whether input plus the output allowance fits this model's context window, with the exact count."""
    n = count_input(cl, model, system, user, schema)
    return n + max_tokens + 4000 <= window_of(model), n


def fallback_kwargs(model: str) -> dict:
    """The refusal fallback for models that accept it; nothing for the others."""
    return {"fallbacks": "default", "betas": [FALLBACK_BETA]} if model in FALLBACK_MODELS else {}


def call_json(cl, model: str, effort: str, system: str, user: str, schema: dict, max_tokens: int) -> Result:
    """One streamed call with adaptive thinking and a JSON-schema answer. Raises CreditExhausted on an
    out-of-credit answer, ReviewError on a refusal or a cut-off answer; other API errors propagate."""

    def go():
        with cl.beta.messages.stream(
            **_params(model, effort, system, user, schema, max_tokens),
            **fallback_kwargs(model),
        ) as stream:
            return stream.get_final_message()

    return _finish(_api(go), model, max_tokens)


def batch_json(cl, model: str, effort: str, system: str, user: str, schema: dict, max_tokens: int,
               wait_seconds: int) -> Result:
    """The same call through the Message Batches API (half price, answered within hours). Polls until the
    batch ends or wait_seconds pass."""
    import time

    batch = _api(
        lambda: cl.beta.messages.batches.create(
            requests=[{"custom_id": "audit", "params": _params(model, effort, system, user, schema, max_tokens)}]
        )
    )
    print(f"batch {batch.id} submitted")
    waited = 0
    while batch.processing_status != "ended":
        if waited >= wait_seconds:
            try:  # nobody will collect the answer: stop it so it is not billed
                cl.beta.messages.batches.cancel(batch.id)
                what = "cancelled"
            except Exception as exc:
                what = f"cancelling it failed too ({exc}); cancel it in the Console"
            raise ReviewError(f"batch {batch.id} did not finish within {wait_seconds // 60} minutes; {what}")
        time.sleep(POLL_SECONDS)
        waited += POLL_SECONDS
        batch = _api(lambda: cl.beta.messages.batches.retrieve(batch.id))
    print(f"batch {batch.id} ended after about {waited // 60} minutes")
    for item in _api(lambda: cl.beta.messages.batches.results(batch.id)):
        res = item.result
        if res.type == "succeeded":
            result = _finish(res.message, model, max_tokens)
            result.batch = True
            return result
        if res.type == "errored":
            err = getattr(res.error, "error", None)
            etype = getattr(err, "type", "")
            text = getattr(err, "message", "") or str(res.error)
            if etype == "billing_error" or "credit balance is too low" in text.lower():
                raise CreditExhausted(text)
            raise ReviewError(f"batch request failed: {etype}: {text}")
        raise ReviewError(f"batch request ended as {res.type}")
    raise ReviewError(f"batch {batch.id} returned no result")


def _finish(msg, model: str, max_tokens: int) -> Result:
    if msg.stop_reason == "refusal":
        details = getattr(msg, "stop_details", None)
        raise ReviewError(f"{model} declined the request (refusal: {details})")
    if msg.stop_reason == "max_tokens":
        raise ReviewError(f"{model} ran out of output tokens ({max_tokens}) before finishing")
    text = "".join(b.text for b in msg.content if getattr(b, "type", "") == "text")
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        # the length only: the text may describe findings that must not reach the public log
        raise ReviewError(f"{model} returned text that is not JSON ({len(text):,} characters)") from None
    usage = msg.usage
    total_in = (
        (usage.input_tokens or 0)
        + (getattr(usage, "cache_read_input_tokens", 0) or 0)
        + (getattr(usage, "cache_creation_input_tokens", 0) or 0)
    )
    return Result(data, getattr(msg, "model", model) or model, total_in, usage.output_tokens or 0)


# ------------------------------------------------------------------- git ---


def git(*args: str, check: bool = True) -> str:
    out = subprocess.run(["git", *args], cwd=REPO_ROOT, capture_output=True, text=True)
    if check and out.returncode != 0:
        raise ReviewError(f"git {' '.join(args)} failed: {out.stderr.strip()}")
    return out.stdout


def git_ok(*args: str) -> bool:
    return subprocess.run(["git", *args], cwd=REPO_ROOT, capture_output=True).returncode == 0


def is_ancestor(a: str, b: str) -> bool:
    return git_ok("merge-base", "--is-ancestor", a, b)


def tree_of(rev: str) -> str:
    return git("rev-parse", f"{rev}^{{tree}}").strip()


def devonly_patterns(*refs: str) -> list[str]:
    pats: set[str] = set()
    for ref in refs:
        if not git_ok("cat-file", "-e", f"{ref}:{DEVONLY_FILE}"):
            continue
        for line in git("show", f"{ref}:{DEVONLY_FILE}").splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                pats.add(line)
    return sorted(pats)


def devonly_match(path: str, pats) -> bool:
    for pat in pats:
        if pat.endswith("/"):
            if path.startswith(pat):
                return True
        elif fnmatch.fnmatchcase(path, pat) or path.startswith(pat + "/"):
            return True
    return False


def strip_tree(rev: str, pats) -> str:
    """The tree of rev without the dev-only paths (the same thing tools/merge-dev.sh builds)."""
    return _rewrite_tree(rev, pats, keep_from=None)


def keep_devonly(tree: str, from_rev: str, pats) -> str:
    """tree with its dev-only paths replaced by those of from_rev."""
    return _rewrite_tree(tree, pats, keep_from=from_rev)


def _rewrite_tree(tree: str, pats, keep_from: str | None) -> str:
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(tmp) / "idx"))

        def run(args, data=None):
            out = subprocess.run(["git", *args], cwd=REPO_ROOT, env=env, input=data, capture_output=True)
            if out.returncode != 0:
                raise ReviewError(f"git {' '.join(args)} failed: {out.stderr.decode().strip()}")
            return out.stdout

        run(["read-tree", tree])
        names = run(["ls-tree", "-r", "-z", "--name-only", "--full-tree", tree]).split(b"\0")
        drop = [n for n in names if n and devonly_match(n.decode(), pats)]
        if drop:
            run(["update-index", "-z", "--force-remove", "--stdin"], b"\0".join(drop) + b"\0")
        if keep_from:
            entries = run(["ls-tree", "-r", "-z", "--full-tree", keep_from]).split(b"\0")
            keep = [e for e in entries if e and devonly_match(e.split(b"\t", 1)[1].decode(), pats)]
            if keep:
                run(["update-index", "-z", "--index-info"], b"\0".join(keep) + b"\0")
        return run(["write-tree"]).decode().strip()


def bundle(rev: str, skip_dirs: tuple[str, ...] = (), skip_files=frozenset()) -> tuple[str, int]:
    """Every tracked text file of rev, with line numbers, as <file path="..."> blocks. Returns the text
    and the number of files."""
    parts, count = [], 0
    for path in git("ls-tree", "-r", "--name-only", "--full-tree", rev).splitlines():
        if path in BUNDLE_SKIP or path in skip_files or path.startswith(skip_dirs):
            continue
        raw = subprocess.run(["git", "cat-file", "blob", f"{rev}:{path}"], cwd=REPO_ROOT, capture_output=True).stdout
        if len(raw) > BUNDLE_MAX_FILE or b"\0" in raw[:8192]:
            continue
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            continue
        numbered = "\n".join(f"{i}\t{line}" for i, line in enumerate(text.splitlines(), 1))
        parts.append(f'<file path="{path}">\n{numbered}\n</file>')
        count += 1
    return "\n".join(parts), count



# ---------------------------------------------------------------- GitHub ---


def repo() -> str:
    return os.environ["GITHUB_REPOSITORY"]


def gh(method: str, path: str, body: dict | None = None, check: bool = True):
    args = ["gh", "api", "-X", method, path, "-H", "Accept: application/vnd.github+json"]
    data = None
    if body is not None:
        args += ["--input", "-"]
        data = json.dumps(body)
    out = subprocess.run(args, input=data, capture_output=True, text=True)
    if out.returncode != 0:
        if check:
            raise ReviewError(f"GitHub API {method} {path} failed: {out.stderr.strip() or out.stdout.strip()}")
        return None
    return json.loads(out.stdout) if out.stdout.strip() else None


def run_url() -> str:
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    return f"{server}/{repo()}/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}"


def summary(text: str) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(text.rstrip() + "\n\n")
    else:
        print(text)


def output(key: str, value: str) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(f"{key}={value}\n")


def fail(msg: str) -> None:
    print(f"::error::{msg}", file=sys.stderr)
    summary(f"**Error:** {msg}")
    sys.exit(1)


def credit_notice(what: str) -> None:
    """Record a skip in the single credit-exhausted issue (needs issues: write) and say so, briefly."""
    from credit_issue import record_skip

    number = record_skip(what)
    ref = f" See #{number}." if number else ""
    summary(f"API credit exhausted: {what} did not run.{ref}")
    output("credit", "true")


def credit_resumed() -> None:
    """Close the credit-exhausted issue if one is open (needs issues: write)."""
    from credit_issue import close_if_open

    close_if_open()
