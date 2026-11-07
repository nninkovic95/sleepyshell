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
import context  # noqa: E402
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

    def decide_with(self, rows, tier, effort="medium", status=None):
        from unittest import mock

        answer = claude.Result({"tier": tier, "effort": effort, "reason": "test"}, route.ROUTER_MODEL, 0, 0)
        with mock.patch.object(route, "numstat", return_value=rows), \
                mock.patch.object(route, "statuses", return_value=status or {}), \
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


class RouterEffort(unittest.TestCase):
    """The router picks the effort too; sensitive pushes get at least high, whatever it says."""

    decide_with = RouterNoBias.decide_with

    def test_trivial_push_may_get_low_effort(self):
        rt = self.decide_with([("2", "1", "README.md")], "haiku", "low")
        self.assertEqual((rt.tier, rt.effort, rt.lifted), ("haiku", "low", []))

    def test_floor_lifts_effort_to_high(self):
        rt = self.decide_with([("3", "0", "services/SettingsServer.qml")], "opus", "low")
        self.assertEqual((rt.tier, rt.effort), ("opus", "high"))
        self.assertEqual(rt.lifted, ["effort"])

    def test_floor_never_lowers_a_higher_effort(self):
        rt = self.decide_with([("3", "0", "scripts/idle.py")], "fable", "max")
        self.assertEqual((rt.tier, rt.effort, rt.lifted), ("fable", "max", []))

    def test_every_model_takes_every_effort(self):
        self.assertEqual(route.SCHEMA["properties"]["effort"]["enum"], ["low", "medium", "high", "xhigh", "max"])

    def test_summary_logs_model_effort_and_reason(self):
        rt = self.decide_with([("3", "0", "services/SettingsServer.qml")], "haiku", "low")
        md = route.summary_md(rt)
        for part in ("claude-opus-5-5", "effort `high`", "test", "raised the model and the effort"):
            self.assertIn(part, md)

    def test_prompt_maps_the_sensitive_paths(self):
        self.assertIn("services/SettingsServer.qml", route.SYSTEM)
        self.assertIn("sleepylock/*", route.SYSTEM)
        self.assertNotIn("$", route.SYSTEM)  # no prices


class RouterSurvey(unittest.TestCase):
    """What is counted as size, and which pushes skip the AI review."""

    def survey(self, rows, status=None):
        return route.survey("BASE", "HEAD", rows=rows, status=status or {})

    def test_clips_and_icon_index_are_not_large(self):
        rows = [("-", "-", "assets/clips/a.webp"), ("-", "-", "assets/clips/b.webp"), ("40000", "39000", "data/icons.json")]
        sv = self.survey(rows)
        self.assertEqual(sv.kept, [])
        self.assertTrue(sv.skip_ai)
        self.assertIn("0 files counted, 0 insertions, 0 deletions", route.stats_text(sv))
        self.assertEqual(sv.media, ["assets/clips/a.webp", "assets/clips/b.webp"])
        self.assertEqual(sv.generated, ["data/icons.json"])

    def test_pure_renames_and_deletions_are_not_counted(self):
        rows = [("0", "0", "scripts/{a.py => b.py}"), ("0", "900", "old/big.qml"), ("5", "1", "shell.qml")]
        sv = self.survey(rows, {"scripts/b.py": "R100", "old/big.qml": "D", "shell.qml": "M"})
        self.assertEqual(sv.kept, [("5", "1", "shell.qml")])
        self.assertEqual(sv.excluded["renamed"], ["scripts/b.py"])
        self.assertEqual(sv.excluded["deleted"], ["old/big.qml"])
        self.assertFalse(sv.skip_ai)

    def test_a_rename_with_edits_still_counts(self):
        sv = self.survey([("4", "2", "scripts/{a.py => b.py}")], {"scripts/b.py": "R090"})
        self.assertEqual(len(sv.kept), 1)

    def test_kinds(self):
        self.assertEqual(self.survey([("300", "0", "README.md"), ("-", "-", "assets/clips/x.webp")]).kind, "docs-only")
        self.assertEqual(self.survey([("900", "10", "tests/bar/x.sh")]).kind, "tests-only")
        self.assertEqual(self.survey([("1", "1", "shell.qml"), ("1", "0", "README.md")]).kind, "code")

    def test_docs_only_push_is_still_reviewed(self):
        sv = self.survey([("300", "0", "README.md")])
        self.assertFalse(sv.skip_ai)
        self.assertIn("only documentation", route.stats_text(sv))

    def test_media_only_push_makes_no_api_call(self):
        from types import SimpleNamespace
        from unittest import mock

        posted = []
        boom = AssertionError("a media-only push reached the API")
        args = SimpleNamespace(branch="dev", head="a" * 40, before="", mode="review", p2="", private_out="")
        rows = [("-", "-", "assets/clips/a.webp"), ("12", "12", "data/icons.json")]
        with mock.patch.object(review.review_range, "review_base", return_value=("BASE", "since BASE", False)), \
                mock.patch.object(route, "numstat", return_value=rows), \
                mock.patch.object(route, "statuses", return_value={}), \
                mock.patch.object(review.media, "check", return_value=[]), \
                mock.patch.object(review, "post_check", side_effect=lambda *a, **k: posted.append(a) or "u"), \
                mock.patch.object(review, "summary"), mock.patch.object(review, "output"), \
                mock.patch.object(review, "run_url", return_value="u"), \
                mock.patch.object(claude, "client", side_effect=boom), \
                mock.patch.object(claude, "call_json", side_effect=boom), \
                mock.patch.object(route, "call_json", side_effect=boom):
            self.assertEqual(review.run(args), 0)
        self.assertEqual(posted[0][1], "success")
        self.assertIn("no AI review", posted[0][2])

    def test_failed_file_check_fails_the_media_only_push(self):
        from types import SimpleNamespace
        from unittest import mock

        posted = []
        args = SimpleNamespace(branch="dev", head="a" * 40, before="", mode="review", p2="", private_out="")
        with mock.patch.object(review.review_range, "review_base", return_value=("BASE", "since BASE", False)), \
                mock.patch.object(route, "numstat", return_value=[("-", "-", "assets/clips/a.webp")]), \
                mock.patch.object(route, "statuses", return_value={}), \
                mock.patch.object(review.media, "check", return_value=[("assets/clips/a.webp", "is not a WebP file")]), \
                mock.patch.object(review, "post_check", side_effect=lambda *a, **k: posted.append(a) or "u"), \
                mock.patch.object(review, "summary"), mock.patch.object(review, "output"), \
                mock.patch.object(review, "run_url", return_value="u"), \
                mock.patch.object(claude, "client", side_effect=AssertionError("API")):
            self.assertEqual(review.run(args), 1)
        self.assertEqual(posted[0][1], "failure")


class ReviewContext(unittest.TestCase):
    """A later review reads the diff and what it needs; the first one the whole codebase."""

    FILES = {
        "README.md": "# shell\n",
        "SECURITY.md": "# security\n",
        "services/Notifs.qml": "Singleton {\n    function toggleDnd() {}\n    readonly property bool dnd: Settings.dnd\n}\n",
        "services/Settings.qml": "Singleton {\n    dnd: { tab: \"notifications\", def: false },\n}\n",
        "sleepybar/widgets/notifications/Bell.qml": "Item {\n    onClicked: Notifs.toggleDnd()\n}\n",
        "scripts/idle.py": "# reads idleLockMin\nprint('--create')\n",
        "sleepysettings/IdleTab.qml": "Item { property string k: \"idleLockMin\" }\n",
        "sleepybar/widgets/clock/Clock.qml": "Item { property string label: \"clock\" }\n",
        "services/SettingsServer.qml": "Singleton { }\n",
        "sleepysettings/BarLink.qml": "Item { }\n",
    }
    GROUPS = [("The settings socket", ["services/SettingsServer.qml", "sleepysettings/BarLink.qml"])]

    def select(self, diff, changed, whole=10**9):
        return context.select(diff, changed, self.FILES, self.GROUPS, whole)

    def paths(self, sel):
        return {p for p, _ in sel.files}

    def test_changed_file_brings_its_users_and_what_it_uses(self):
        diff = "diff --git a/services/Notifs.qml b/services/Notifs.qml\n+++ b/services/Notifs.qml\n+    function toggleDnd() {}\n"
        got = self.paths(self.select(diff, ["services/Notifs.qml"]))
        self.assertIn("sleepybar/widgets/notifications/Bell.qml", got)   # calls toggleDnd, names Notifs
        self.assertIn("services/Settings.qml", got)                      # Notifs uses Settings
        self.assertIn("README.md", got)
        self.assertNotIn("sleepybar/widgets/clock/Clock.qml", got)

    def test_docs_only_push_brings_what_its_lines_quote(self):
        diff = "diff --git a/README.md b/README.md\n+++ b/README.md\n+`scripts/idle.py` reads `idleLockMin`; see the `label` row.\n"
        got = self.paths(self.select(diff, ["README.md"]))
        self.assertIn("scripts/idle.py", got)
        self.assertIn("sleepysettings/IdleTab.qml", got)                 # the distinctive key
        self.assertNotIn("sleepybar/widgets/clock/Clock.qml", got)       # "label" is a plain word

    def test_sensitive_group_comes_whole(self):
        got = self.paths(self.select("", ["services/SettingsServer.qml"]))
        self.assertIn("sleepysettings/BarLink.qml", got)

    def test_wide_change_gets_the_whole_codebase(self):
        sel = self.select("", list(self.FILES), whole=10)
        self.assertTrue(sel.whole)

    def test_cap_leaves_out_the_lowest_ranks_first(self):
        from unittest import mock

        diff = "diff --git a/services/Notifs.qml b/services/Notifs.qml\n+++ b/services/Notifs.qml\n+    function toggleDnd() {}\n"
        size = len(self.FILES["services/Notifs.qml"]) + len(self.FILES["README.md"]) + len(self.FILES["SECURITY.md"])
        with mock.patch.object(context, "CAP_TOKENS", size / context.CHARS_PER_TOKEN):
            sel = self.select(diff, ["services/Notifs.qml"])
        self.assertIn("services/Notifs.qml", self.paths(sel))
        self.assertTrue(sel.left_out)

    def build(self, first):
        from types import SimpleNamespace
        from unittest import mock

        sv = SimpleNamespace(rows=[("1", "0", "services/Notifs.qml")], excluded={})
        diff = "diff --git a/services/Notifs.qml b/services/Notifs.qml\n+++ b/services/Notifs.qml\n+ x\n"
        # the fixture is ten small files, so any selection is a large share of it: turn the switch off
        with mock.patch.object(context, "FULL_SHARE", 1.0), \
                mock.patch.object(context, "texts", return_value=self.FILES), \
                mock.patch.object(route, "sensitive_lines", return_value=self.GROUPS), \
                mock.patch.object(review, "bundle", return_value=("WHOLE-CODEBASE-MARK", 99)), \
                mock.patch.object(review, "devonly_patterns", return_value=[]), \
                mock.patch.object(review, "git", return_value="README.md\nsleepybar/widgets/clock/Clock.qml"), \
                mock.patch.object(review, "summary"), \
                mock.patch.object(claude, "git_ok", return_value=False), \
                mock.patch.object(claude, "fits", return_value=(True, 1000)):
            return review.build_user(None, "m", 1000, "dev", "range", "BASE", "HEAD", diff, first=first, sv=sv)

    def test_first_review_reads_the_whole_codebase(self):
        user, note, _ = self.build(first=True)
        self.assertIn("WHOLE-CODEBASE-MARK", user)
        self.assertTrue(note.startswith("the codebase"))

    def test_later_review_reads_the_diff_and_its_files(self):
        user, note, _ = self.build(first=False)
        self.assertNotIn("WHOLE-CODEBASE-MARK", user)
        self.assertIn('<file path="services/Notifs.qml">', user)
        self.assertNotIn('<file path="sleepybar/widgets/clock/Clock.qml">', user)
        self.assertIn("<paths>", user)                                   # every path is still listed
        self.assertTrue(note.startswith("the diff and the files it needs"))


class MediaCheck(unittest.TestCase):
    WEBP = b"RIFF\x24\x00\x00\x00WEBPVP8 " + b"\x00" * 20
    PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 20

    def test_real_files_pass(self):
        import media

        self.assertIsNone(media.check_media("a.webp", self.WEBP))
        self.assertIsNone(media.check_media("a.PNG", self.PNG))
        self.assertIsNone(media.check_media("a.gif", b"GIF89a" + b"\x00" * 10))
        self.assertIsNone(media.check_media("a.mp4", b"\x00\x00\x00\x18ftypmp42"))

    def test_spoofed_and_oversized_files_fail(self):
        import media

        self.assertIn("not a WebP", media.check_media("a.webp", self.PNG))
        self.assertIn("not a PNG", media.check_media("a.png", b"#!/bin/sh\nrm -rf ~\n"))
        self.assertIn("limit", media.check_media("a.webp", self.WEBP + b"\x00" * media.MAX_MEDIA))

    def test_generated_index_must_parse(self):
        import media

        self.assertIsNone(media.check_generated("data/icons.json", b'{"a": 1}'))
        self.assertEqual(media.check_generated("data/icons.json", b'{"a": '), "is not valid JSON")

    def test_existing_clips_are_within_the_limit(self):
        import media

        clips = list((claude.REPO_ROOT / "assets/clips").glob("*.webp"))
        for clip in clips:
            with self.subTest(clip=clip.name):
                self.assertIsNone(media.check_media(clip.name, clip.read_bytes()))


class ModelOptions(unittest.TestCase):
    def test_fallback_only_where_the_model_takes_it(self):
        self.assertEqual(claude.fallback_kwargs("claude-haiku-5-5"), {})
        for m in ("claude-sonnet-5-5", "claude-opus-5-5", "claude-fable-5-1"):
            with self.subTest(model=m):
                self.assertEqual(claude.fallback_kwargs(m)["fallbacks"], "default")

    def test_window_from_the_model_list(self):
        from types import SimpleNamespace
        from unittest import mock

        listed = [SimpleNamespace(id="claude-opus-5-5", max_input_tokens=200_000), SimpleNamespace(id="claude-haiku-5-5")]
        cl = SimpleNamespace(models=SimpleNamespace(list=lambda: listed))
        with mock.patch.dict(claude.WINDOWS, clear=True):
            claude.check_models(cl, ["claude-opus-5-5"])
            self.assertEqual(claude.window_of("claude-opus-5-5"), 200_000)
            self.assertEqual(claude.window_of("claude-haiku-5-5"), claude.CONTEXT_WINDOW)
            with mock.patch.object(claude, "count_input", return_value=150_000):
                self.assertFalse(claude.fits(None, "claude-opus-5-5", "", "", {}, 64_000)[0])
                self.assertTrue(claude.fits(None, "claude-haiku-5-5", "", "", {}, 64_000)[0])

    def test_haiku_long_prompt_price(self):
        short = claude.Result({}, "claude-haiku-5-5", 100_000, 0)
        long = claude.Result({}, "claude-haiku-5-5", 200_000, 0)
        self.assertAlmostEqual(short.cost(), 0.01)
        self.assertAlmostEqual(long.cost(), 0.10)


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


class ReleaseInput(unittest.TestCase):
    TREE = {
        "README.md": "# sleepyshell\nInstall by hand.\n",
        "SECURITY.md": "# Security\n## Known limitations\n- The update check has no timeout.\n## Other\nx\n",
        "TASKS.md": "- [ ] public item\n- [x] showoff thing in tools/showoff/\n",
        "tests/bar/a.sh": "", "tests/common/b.sh": "", ".github/workflows/dev.yml": "run: review.py",
        "tools/showoff/shell.qml": "",
    }

    def docs(self, tree):
        from unittest import mock

        with mock.patch.object(release, "tree_files", return_value=list(tree)), \
                mock.patch.object(release, "blob_text", side_effect=lambda _h, p: tree.get(p, "")):
            return release.first_release_docs("HEAD", ["tools/showoff/"])

    def test_first_release_reads_readme_facts_and_limits(self):
        text = self.docs(self.TREE)
        self.assertIn("<readme>", text)
        self.assertIn("The update check has no timeout.", text)
        self.assertNotIn("## Other", text)
        self.assertIn("Installer: none yet", text)
        self.assertIn("2 shell scripts", text)
        self.assertIn("does not run in CI", text)

    def test_work_list_only_when_present_and_without_devonly_lines(self):
        text = self.docs(self.TREE)
        self.assertIn("public item", text)
        self.assertNotIn("showoff", text)
        self.assertNotIn("<work-list>", self.docs({k: v for k, v in self.TREE.items() if k != "TASKS.md"}))

    def test_devonly_files_are_not_counted(self):
        self.assertIn("Files in the shell: 6", self.docs(self.TREE))

    def test_notes_keep_unfixed_security_out(self):
        self.assertIn("Never describe a security problem that is not fixed yet", release.SYSTEM)

    def test_dry_run_makes_no_api_call(self):
        import io
        from contextlib import redirect_stdout
        from unittest import mock

        boom = AssertionError("the dry run reached the API")
        with mock.patch.object(claude, "client", side_effect=boom), \
                mock.patch.object(claude, "count_input", side_effect=boom), \
                mock.patch.object(claude, "call_json", side_effect=boom), \
                mock.patch.object(release, "latest_tag", return_value=None), \
                mock.patch.object(release, "devonly_patterns", return_value=["tools/showoff/"]), \
                mock.patch.object(claude, "strip_tree", return_value="TREE"), \
                mock.patch.object(release, "build_user", return_value="<facts>\nF\n</facts>\n<codebase>x</codebase>"), \
                redirect_stdout(io.StringIO()) as out:
            self.assertEqual(release.dry_run("HEAD", ""), 0)
        self.assertIn("no API call made", out.getvalue())


if __name__ == "__main__":
    unittest.main()
