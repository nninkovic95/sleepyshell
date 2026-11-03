"""Unit tests for the CI scripts' decisions that can be checked without the API or GitHub:
the credit detector, the dev-only matching, the router (no bias, the Opus floor), the release version arithmetic,
and the private filing (no private finding in public output, simulations make no API call and run only by hand).

    python3 .github/scripts/test_claude.py   (from the repository root, with the SDK installed)
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import httpx2  # noqa: E402  (the SDK's HTTP library, used to build real error objects)
import anthropic  # noqa: E402

import claude  # noqa: E402
import release  # noqa: E402
import review  # noqa: E402
import route  # noqa: E402


def api_error(status: int, etype: str, message: str):
    req = httpx2.Request("POST", "https://api.anthropic.com/v1/messages")
    body = {"type": "error", "error": {"type": etype, "message": message}}
    resp = httpx2.Response(status, json=body, request=req)
    cls = {
        400: anthropic.BadRequestError,
        401: anthropic.AuthenticationError,
        403: anthropic.PermissionDeniedError,
        429: anthropic.RateLimitError,
    }.get(status, anthropic.APIStatusError)
    return cls(message, response=resp, body=body)


class CreditDetector(unittest.TestCase):
    def test_billing_error_402(self):
        self.assertTrue(claude.is_credit_exhausted(api_error(402, "billing_error", "There's an issue with your billing")))

    def test_credit_balance_400(self):
        msg = "Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing."
        self.assertTrue(claude.is_credit_exhausted(api_error(400, "invalid_request_error", msg)))

    def test_rejects_other_errors(self):
        for err in (
            api_error(401, "authentication_error", "invalid x-api-key"),
            api_error(403, "permission_error", "not allowed"),
            api_error(429, "rate_limit_error", "spend limit reached"),
            api_error(400, "invalid_request_error", "You have reached your specified API usage limits"),
            api_error(400, "invalid_request_error", "max_tokens is too large"),
            api_error(402, "invalid_request_error", "payment required"),
            api_error(500, "api_error", "internal"),
            ValueError("credit balance is too low"),
        ):
            with self.subTest(err=repr(err)):
                self.assertFalse(claude.is_credit_exhausted(err))


class DevOnlyMatching(unittest.TestCase):
    pats = ["tools/showoff/", "secret-*.txt", "lab"]

    def test_folder_prefix(self):
        self.assertTrue(claude.devonly_match("tools/showoff/shell.qml", self.pats))
        self.assertFalse(claude.devonly_match("tools/showoffx/shell.qml", self.pats))
        self.assertFalse(claude.devonly_match("tools/merge-dev.sh", self.pats))

    def test_glob_and_folder_without_slash(self):
        self.assertTrue(claude.devonly_match("secret-1.txt", self.pats))
        self.assertTrue(claude.devonly_match("lab/x.py", self.pats))
        self.assertFalse(claude.devonly_match("laboratory/x.py", self.pats))


class RouterFloor(unittest.TestCase):
    def test_sensitive_path_forces_opus(self):
        rows = [("3", "1", "services/SettingsServer.qml")]
        reasons = route.floor_reasons(rows, "HEAD")
        self.assertTrue(reasons and "sensitive path" in reasons[0])

    def test_prose_does_not_trigger_the_floor(self):
        self.assertFalse(route.is_code("TASKS.md", "- [ ] never run sudo or rm -rf here"))
        self.assertTrue(route.is_code("scripts/theme.py", ""))
        self.assertTrue(route.is_code("tools/helper", "#!/bin/sh\nrm -f x\n"))

    def test_rename_notation(self):
        self.assertEqual(route._path_of("scripts/{a.py => b.py}"), "scripts/b.py")
        self.assertEqual(route._path_of("old.md => new.md"), "new.md")

    def test_markers(self):
        for text in ("IpcHandler {", "Process {", "subprocess.run(", "eval(x)", "pkexec foo"):
            with self.subTest(text=text):
                self.assertIsNotNone(route.RISKY.search(text))


class RouterNoBias(unittest.TestCase):
    """The router's own pick stands unless the code floor applies; nothing nudges it a tier up."""

    def decide_with(self, rows, tier):
        from unittest import mock

        answer = claude.Result({"tier": tier, "reason": "test"}, route.ROUTER_MODEL, 0, 0)
        with mock.patch.object(route, "numstat", return_value=rows), \
                mock.patch.object(route, "call_json", return_value=answer):
            return route.decide(None, "BASE", "HEAD")

    def test_small_plain_push_routes_cheaper(self):
        # three lines of README prose: the router's haiku pick stays haiku (before, the prompt pushed it up a tier)
        rt = self.decide_with([("3", "0", "README.md")], "haiku")
        self.assertEqual(rt.tier, "haiku")
        self.assertEqual(rt.floor, [])
        self.assertLess(route.TIERS.index(rt.tier), route.TIERS.index("sonnet"))

    def test_floor_still_lifts_sensitive_paths(self):
        rt = self.decide_with([("3", "0", "services/SettingsServer.qml")], "haiku")
        self.assertEqual(rt.tier, "opus")
        self.assertTrue(rt.floor)

    def test_prompt_has_no_upward_bias(self):
        self.assertNotIn("borderline", route.SCHEMA["properties"])
        self.assertNotIn("pick the higher one", route.SYSTEM)


class PrivateFindings(unittest.TestCase):
    """A private finding's text never reaches a check run, an issue or a run summary; it goes only to the
    file the filing step reads. The marker stands for any detail of such a finding."""

    MARK = "PRIVATE-MARK-7f3a"

    def finding(self, severity, category, word):
        return {"severity": severity, "category": category, "file": "shell.qml", "line": 3,
                "title": f"{word} title", "detail": f"{word} detail", "fix": f"{word} fix"}

    def setUp(self):
        import os
        import tempfile

        os.environ.setdefault("GITHUB_REPOSITORY", "owner/repo")
        self.tmp = tempfile.TemporaryDirectory()
        self.out = os.path.join(self.tmp.name, "private.json")
        self.public = []  # every text that would be published

    def tearDown(self):
        self.tmp.cleanup()

    def capture(self, *args, **_):
        self.public.append(repr(args))
        return {"number": 7, "html_url": "u", "id": 1}

    def run_review(self, findings, summary_text):
        from types import SimpleNamespace
        from unittest import mock

        res = claude.Result({"summary": summary_text, "findings": findings}, "m", 0, 0)
        args = SimpleNamespace(branch="dev", private_out=self.out)
        with mock.patch.object(review, "gh", side_effect=self.capture), \
                mock.patch.object(review, "post_check", side_effect=lambda *a, **k: (self.capture(*a), "url")[1]), \
                mock.patch.object(review, "summary", side_effect=self.capture), \
                mock.patch.object(review, "output"), \
                mock.patch.object(claude, "git_ok", return_value=True):
            return review.publish(args, "a" * 40, res, "route", "range", "usage")

    def test_review_keeps_private_findings_out_of_public_output(self):
        import json

        findings = [self.finding("serious", "security", self.MARK), self.finding("minor", "docs", "Plain")]
        code = self.run_review(findings, f"The summary mentions {self.MARK}.")
        published = "\n".join(self.public)
        self.assertEqual(code, 1)  # the red X stays for a serious private finding
        self.assertNotIn(self.MARK, published)
        self.assertIn("Plain detail", published)
        self.assertIn("1 security finding (1 serious) filed privately", published)
        self.assertNotIn("review-serious", published)  # no public issue for a serious private finding
        private = json.loads(Path(self.out).read_text())
        self.assertIn(self.MARK, private["description"])

    def test_review_without_private_findings_files_nothing(self):
        import os

        self.run_review([self.finding("minor", "docs", "Plain")], "All fine.")
        self.assertFalse(os.path.exists(self.out))
        self.assertIn("All fine.", "\n".join(self.public))

    def test_every_private_category(self):
        for cat in ("security", "ask-first", "personal-path"):
            with self.subTest(category=cat):
                self.public = []
                self.run_review([self.finding("minor", cat, self.MARK)], f"About {self.MARK}.")
                self.assertNotIn(self.MARK, "\n".join(self.public))

    def test_audit_simulation_keeps_the_marker_private(self):
        import json
        from unittest import mock

        import audit

        res = claude.Result(audit.simulated("run1"), audit.MODEL, 0, 0, batch=True)
        prev = [{"title": "Old secret thing", "file": "x", "severity": "minor"}]  # no category: never published
        res.data["fixed"] = ["Old secret thing"]
        with mock.patch.object(audit, "gh", side_effect=lambda m, *a: [] if m == "GET" else self.capture(m, *a)), \
                mock.patch.object(audit, "summary", side_effect=self.capture):
            audit.publish(res, "note", prev, "2026-11-02 (simulated)", self.out, close_issue=False)
        published = "\n".join(self.public)
        self.assertNotIn("PRIVATE-CANARY-run1", published)
        self.assertNotIn("Old secret thing", published)
        self.assertNotIn("audit-data", published)
        self.assertIn("Simulated public finding", published)
        private = json.loads(Path(self.out).read_text())
        self.assertIn("PRIVATE-CANARY-run1", private["description"])
        self.assertIn("audit-data", private["description"])

    def simulate_env(self, event):
        import os
        from unittest import mock

        return mock.patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": event})

    def test_simulation_makes_no_api_call(self):
        from unittest import mock

        import audit

        boom = AssertionError("the simulation reached the API client (federation login)")
        with self.simulate_env("workflow_dispatch"), \
                mock.patch.object(claude, "client", side_effect=boom), \
                mock.patch.object(claude, "batch_json", side_effect=boom), \
                mock.patch.object(claude, "call_json", side_effect=boom), \
                mock.patch.object(claude, "check_models", side_effect=boom), \
                mock.patch.object(audit, "gh", side_effect=lambda m, *a: [] if m == "GET" else self.capture(m, *a)), \
                mock.patch.object(audit, "summary", side_effect=self.capture):
            self.assertEqual(audit.run("findings", "", self.out), 0)

    def test_simulation_refused_outside_a_manual_run(self):
        import audit

        for event in ("schedule", "push", ""):
            with self.subTest(event=event), self.simulate_env(event):
                with self.assertRaises(claude.ReviewError):
                    audit.run("findings", "", self.out)
                with self.assertRaises(claude.ReviewError):
                    audit.run("credit_exhausted", "", self.out)

    def test_non_json_error_shows_no_text(self):
        from types import SimpleNamespace

        msg = SimpleNamespace(stop_reason="end_turn", content=[SimpleNamespace(type="text", text=f"not json {self.MARK}")])
        with self.assertRaises(claude.ReviewError) as cm:
            claude._finish(msg, "m", 10)
        self.assertNotIn(self.MARK, str(cm.exception))


class AdvisoryData(unittest.TestCase):
    def test_last_marker_and_broken_data(self):
        import advisory

        self.assertEqual(advisory.audit_data('<!-- audit-data: [1] --> x <!-- audit-data: [{"title": "b"}] -->'), [{"title": "b"}])
        self.assertIsNone(advisory.audit_data("<!-- audit-data: {broken -->"))
        self.assertIsNone(advisory.audit_data("no marker"))

    def test_simulated_audits_are_not_audits(self):
        import advisory

        self.assertTrue(advisory.is_audit({"summary": "Weekly audit 2026-11-09: 2 security finding(s)"}))
        self.assertFalse(advisory.is_audit({"summary": "Weekly audit 2026-11-02 (simulated): 1 security finding(s)"}))
        self.assertFalse(advisory.is_audit({"summary": "Security findings of the first weekly audit"}))


class HiddenJson(unittest.TestCase):
    def test_comment_safe_round_trip(self):
        import json
        import re

        value = [{"title": "a --> b -- c", "n": 1}]
        text = f"<!-- data: {claude.hidden_json(value)} -->"
        self.assertNotIn("--", text[5:-4])
        self.assertEqual(json.loads(re.search(r"<!-- data: (.*?) -->", text, re.S).group(1)), value)

    def test_batch_cost_is_half(self):
        full = claude.Result({}, "claude-fable-5-1", 1_000_000, 0)
        half = claude.Result({}, "claude-fable-5-1", 1_000_000, 0, batch=True)
        self.assertAlmostEqual(half.cost() * 2, full.cost())


class FindingPaths(unittest.TestCase):
    def test_dotfiles_kept(self):
        self.assertEqual(review.clean_path(" ./.github/scripts/claude.py "), ".github/scripts/claude.py")
        self.assertEqual(review.clean_path(".gitignore"), ".gitignore")
        self.assertEqual(review.clean_path("././services/Settings.qml"), "services/Settings.qml")


class ReleaseVersions(unittest.TestCase):
    def test_parse_and_bump(self):
        p = release.parse("0.4.2")
        self.assertEqual(release.bumped(p, "patch"), "0.4.3")
        self.assertEqual(release.bumped(p, "minor"), "0.5.0")
        self.assertEqual(release.bumped(p, "major"), "1.0.0")
        self.assertEqual(release.bumped(release.parse("1.0.0-rc.1"), "patch"), "1.0.0")

    def test_precedence(self):
        self.assertTrue(release.newer(release.parse("1.0.0"), release.parse("1.0.0-rc.1")))
        self.assertTrue(release.newer(release.parse("0.10.0"), release.parse("0.9.9")))
        self.assertFalse(release.newer(release.parse("0.9.9"), release.parse("0.10.0")))

    def test_invalid(self):
        for v in ("1.0", "v1.0.0", "01.0.0", "1.0.0.0", ""):
            with self.subTest(v=v):
                self.assertIsNone(release.parse(v))


if __name__ == "__main__":
    unittest.main()
