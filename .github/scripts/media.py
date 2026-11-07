"""The free check for files no AI review reads: every media file must be what its extension says (its first
bytes) and of a sane size, and the generated icon index must parse. Runs on every push that has such files;
for a push of nothing else it is the whole check, with no API call.

    media.py HEAD PATH...    check the files as they are in commit HEAD, print the problems, exit 1 if any
"""

from __future__ import annotations

import json
import subprocess
import sys

from claude import REPO_ROOT

MAX_MEDIA = 20 * 1024 * 1024
MAX_GENERATED = 5 * 1024 * 1024


def _webp(b: bytes) -> bool:
    return len(b) >= 12 and b[:4] == b"RIFF" and b[8:12] == b"WEBP"


def _png(b: bytes) -> bool:
    return b[:8] == b"\x89PNG\r\n\x1a\n"


def _jpeg(b: bytes) -> bool:
    return b[:3] == b"\xff\xd8\xff"


def _gif(b: bytes) -> bool:
    return b[:6] in (b"GIF87a", b"GIF89a")


def _mp4(b: bytes) -> bool:
    return len(b) >= 12 and b[4:8] == b"ftyp"


def _webm(b: bytes) -> bool:
    return b[:4] == b"\x1a\x45\xdf\xa3"


SIGNATURES = {
    ".webp": ("WebP", _webp),
    ".png": ("PNG", _png),
    ".jpg": ("JPEG", _jpeg),
    ".jpeg": ("JPEG", _jpeg),
    ".gif": ("GIF", _gif),
    ".mp4": ("MP4", _mp4),
    ".webm": ("WebM", _webm),
}


def check_media(path: str, data: bytes) -> str | None:
    """The problem with one media file, or None when it is fine."""
    ext = "." + path.rsplit(".", 1)[-1].lower() if "." in path else ""
    sig = SIGNATURES.get(ext)
    if sig is None:
        return f"no check is known for `{ext or path}` files"
    if len(data) > MAX_MEDIA:
        return f"{len(data) / 1048576:.1f} MB, over the {MAX_MEDIA // 1048576} MB limit"
    if not sig[1](data):
        return f"is not a {sig[0]} file (its first bytes say otherwise)"
    return None


def check_generated(path: str, data: bytes) -> str | None:
    if len(data) > MAX_GENERATED:
        return f"{len(data) / 1048576:.1f} MB, over the {MAX_GENERATED // 1048576} MB limit"
    if path.endswith(".json"):
        try:
            json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            return "is not valid JSON"
    return None


def blob(head: str, path: str) -> bytes | None:
    out = subprocess.run(["git", "cat-file", "blob", f"{head}:{path}"], cwd=REPO_ROOT, capture_output=True)
    return out.stdout if out.returncode == 0 else None


def check(head: str, media, generated) -> list[tuple[str, str]]:
    """[(path, problem)] for the files as they are in head."""
    problems = []
    for paths, fn in ((media, check_media), (generated, check_generated)):
        for path in paths:
            data = blob(head, path)
            if data is None:
                problems.append((path, "cannot be read from the commit"))
                continue
            p = fn(path, data)
            if p:
                problems.append((path, p))
    return problems


def report(media, generated, problems) -> str:
    n = len(media) + len(generated)
    if not n:
        return ""
    if not problems:
        return f"**File check:** {n} media or generated file{'s' if n != 1 else ''} checked: each is what its name says and within the size limit."
    lines = [f"**File check failed:** {len(problems)} of {n} file{'s' if n != 1 else ''}:"]
    lines += [f"- `{p}` {why}" for p, why in problems]
    return "\n".join(lines)


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    from route import GENERATED

    head, paths = sys.argv[1], sys.argv[2:]
    gen = [p for p in paths if p in GENERATED]
    med = [p for p in paths if p not in GENERATED]
    problems = check(head, med, gen)
    print(report(med, gen, problems))
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
