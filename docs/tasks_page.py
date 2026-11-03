#!/usr/bin/env python3
"""tasks_page.py TASKS.md OUT.html: render the goal-based task list as a page.

Parses the markdown the repository keeps (headings, "reached when" paragraphs, checklists with [x] [~] [ ]
and one level of subtasks, plain bullets, a numbered list, inline code, bold and links) and writes a
self-contained page with progress per goal."""
import html
import re
import sys
from pathlib import Path

src = Path(sys.argv[1]).read_text().splitlines()
out = Path(sys.argv[2])


def inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(https?://[^\s)]+)", r'<a href="\1">\1</a>', s)
    return s


# ---- parse ----
title = ""
intro = []
sections = []   # {title, kind, lead: [paragraphs], items: [{state, text, subs: [{state, text}]}], plain: [], numbered: []}
cur = None
last = None   # the last item or subitem, for continuation lines
mode = None   # "lead" | "items"
for raw in src:
    line = raw.rstrip("\n")
    if line.startswith("# "):
        title = line[2:].strip()
        continue
    if line.startswith("## "):
        name = line[3:].strip()
        kind = "goal" if name.startswith("Goal") else "other"
        cur = {"title": name, "kind": kind, "lead": [], "items": [], "plain": [], "numbered": []}
        sections.append(cur)
        last = None
        mode = "lead"
        continue
    m = re.match(r"^(\s*)- \[( |x|~)\] (.*)$", line)
    if m and cur is not None:
        indent, st, text = len(m.group(1)), m.group(2), m.group(3)
        state = {"x": "done", "~": "started", " ": "open"}[st]
        if indent == 0:
            item = {"state": state, "text": text, "subs": []}
            cur["items"].append(item)
            last = item
        else:
            sub = {"state": state, "text": text}
            if cur["items"]:
                cur["items"][-1]["subs"].append(sub)
            last = sub
        mode = "items"
        continue
    m = re.match(r"^- (.*)$", line)
    if m and cur is not None:
        cur["plain"].append(m.group(1))
        last = {"plain": len(cur["plain"]) - 1}
        mode = "plain"
        continue
    m = re.match(r"^(\d+)\. (.*)$", line)
    if m and cur is not None:
        cur["numbered"].append(m.group(2))
        last = {"numbered": len(cur["numbered"]) - 1}
        mode = "numbered"
        continue
    if line.strip() == "":
        if mode == "lead" and cur is not None and cur["lead"] and cur["lead"][-1] != "":
            cur["lead"].append("")
        last = None if mode != "items" else last
        continue
    # continuation of the previous item, bullet or paragraph
    text = line.strip()
    if last is not None and isinstance(last, dict):
        if "text" in last:
            last["text"] += " " + text
            continue
        if "plain" in last:
            cur["plain"][last["plain"]] += " " + text
            continue
        if "numbered" in last:
            cur["numbered"][last["numbered"]] += " " + text
            continue
    if cur is None:
        intro.append(text)
    else:
        if cur["lead"] and cur["lead"][-1] != "":
            cur["lead"][-1] += " " + text
        else:
            if cur["lead"] and cur["lead"][-1] == "":
                cur["lead"].pop()
            cur["lead"].append(text)
        mode = "lead"

intro_text = " ".join(intro)


def counts(sec):
    c = {"done": 0, "started": 0, "open": 0}
    for it in sec["items"]:
        if it["subs"]:
            for s in it["subs"]:
                c[s["state"]] += 1
        else:
            c[it["state"]] += 1
    return c


total = {"done": 0, "started": 0, "open": 0}
for sec in sections:
    if sec["kind"] == "goal":
        for k, v in counts(sec).items():
            total[k] += v
n_all = sum(total.values()) or 1

# ---- render ----
def mark(state):
    label = {"done": "done", "started": "started", "open": "open"}[state]
    return f'<span class="mark {state}" aria-label="{label}" title="{label}"></span>'


def goal_id(sec):
    return "g" + re.sub(r"[^a-z0-9]+", "-", sec["title"].lower()).strip("-")


parts = []
parts.append(f'''<header class="top">
  <p class="eyebrow">sleepyshell</p>
  <h1>Tasks</h1>
  <p class="intro">{inline(intro_text)}</p>
  <div class="overall" role="img" aria-label="{total['done']} done, {total['started']} started, {total['open']} open">
    <div class="bar"><span class="done" style="width:{total['done']/n_all*100:.1f}%"></span><span class="started" style="width:{total['started']/n_all*100:.1f}%"></span></div>
    <p class="legend"><span>{mark('done')} {total['done']} done</span><span>{mark('started')} {total['started']} started</span><span>{mark('open')} {total['open']} open</span></p>
  </div>
</header>''')

goals = [s for s in sections if s["kind"] == "goal"]
parts.append('<nav class="goals" aria-label="Goals">')
for sec in goals:
    c = counts(sec)
    n = sum(c.values()) or 1
    short = sec["title"].split(":", 1)
    num = short[0].replace("Goal ", "")
    name = short[1].strip() if len(short) > 1 else sec["title"]
    parts.append(f'''  <a class="goal-card" href="#{goal_id(sec)}">
    <span class="num">{num}</span>
    <span class="name">{html.escape(name)}</span>
    <span class="mini"><span class="done" style="width:{c['done']/n*100:.1f}%"></span><span class="started" style="width:{c['started']/n*100:.1f}%"></span></span>
    <span class="count">{c['done']}<span class="of">/{n}</span></span>
  </a>''')
parts.append('</nav>')

for sec in sections:
    sid = goal_id(sec)
    parts.append(f'<section class="goal" id="{sid}">')
    parts.append(f'  <h2>{inline(sec["title"])}</h2>')
    for p in sec["lead"]:
        if p:
            cls = ' class="reached"' if p.startswith("Reached when") else ""
            parts.append(f'  <p{cls}>{inline(p)}</p>')
    if sec["items"]:
        parts.append('  <ul class="tasks">')
        for it in sec["items"]:
            parts.append(f'    <li class="{it["state"]}">{mark(it["state"])}<div class="body"><p>{inline(it["text"])}</p>')
            if it["subs"]:
                parts.append('      <ul class="subs">')
                for s in it["subs"]:
                    parts.append(f'        <li class="{s["state"]}">{mark(s["state"])}<p>{inline(s["text"])}</p></li>')
                parts.append('      </ul>')
            parts.append('    </div></li>')
        parts.append('  </ul>')
    if sec["plain"]:
        parts.append('  <ul class="plain">')
        for p in sec["plain"]:
            parts.append(f'    <li>{inline(p)}</li>')
        parts.append('  </ul>')
    if sec["numbered"]:
        parts.append('  <ol class="next">')
        for p in sec["numbered"]:
            parts.append(f'    <li>{inline(p)}</li>')
        parts.append('  </ol>')
    parts.append('</section>')

body = "\n".join(parts)

page = f'''<title>sleepyshell Tasks</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap">
<style>
/* Layout: one reading column; a goal strip under the title with a progress bar per goal, then each goal
   as a section with its "reached when" line and its checklist. Dark-first, in the shell's own palette. */
:root {{
  color-scheme: dark;
  --surface: #0f141b;
  --container: #171e27;
  --container-high: #202a35;
  --line: #2b3745;
  --text: #dce3ec;
  --muted: #8d9aa8;
  --accent: #22c7d6;
  --accent-ink: #062a2f;
  --started: #e0b35a;
  --font-body: "IBM Plex Sans", "Segoe UI", system-ui, sans-serif;
  --font-mono: "JetBrains Mono", "SFMono-Regular", Menlo, monospace;
}}
@media (prefers-color-scheme: light) {{
  :root:not([data-theme="dark"]) {{
    color-scheme: light;
    --surface: #f3f6f8;
    --container: #ffffff;
    --container-high: #e6edf2;
    --line: #cfd9e2;
    --text: #15202b;
    --muted: #5b6b7a;
    --accent: #0a8d9b;
    --accent-ink: #ffffff;
    --started: #a3700f;
  }}
}}
:root[data-theme="light"] {{
  color-scheme: light;
  --surface: #f3f6f8;
  --container: #ffffff;
  --container-high: #e6edf2;
  --line: #cfd9e2;
  --text: #15202b;
  --muted: #5b6b7a;
  --accent: #0a8d9b;
  --accent-ink: #ffffff;
  --started: #a3700f;
}}
* {{ box-sizing: border-box; }}
body {{
  margin: 0; background: var(--surface); color: var(--text);
  font-family: var(--font-body); font-size: 15px; line-height: 1.55;
  padding-block: 32px 64px;
  padding-left: max(16px, env(safe-area-inset-left, 0px));
  padding-right: max(16px, env(safe-area-inset-right, 0px));
}}
.top, .goals, .goal {{ max-width: 860px; margin-inline: auto; }}
.eyebrow {{ font-family: var(--font-mono); font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--accent); margin: 0 0 6px; }}
h1 {{ font-size: 34px; line-height: 1.1; margin: 0 0 12px; font-weight: 600; text-wrap: balance; }}
h2 {{ font-size: 21px; line-height: 1.25; margin: 0 0 8px; font-weight: 600; text-wrap: balance; }}
.intro {{ color: var(--muted); max-width: 66ch; margin: 0 0 18px; }}
.overall .bar, .mini {{ display: flex; height: 8px; background: var(--container-high); border-radius: 999px; overflow: hidden; }}
.overall .bar {{ height: 10px; }}
.bar .done, .mini .done {{ background: var(--accent); display: block; }}
.bar .started, .mini .started {{ background: var(--started); display: block; }}
.legend {{ display: flex; gap: 18px; flex-wrap: wrap; margin: 10px 0 0; font-family: var(--font-mono); font-size: 12.5px; color: var(--muted); }}
.legend span {{ display: inline-flex; align-items: center; gap: 6px; }}
.goals {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 10px; margin-block: 28px 40px; }}
.goal-card {{ display: grid; gap: 6px; padding: 12px 12px 10px; background: var(--container); border: 1px solid var(--line); border-radius: 10px; color: inherit; text-decoration: none; }}
.goal-card:hover, .goal-card:focus-visible {{ border-color: var(--accent); outline: none; }}
.goal-card .num {{ font-family: var(--font-mono); font-size: 12px; color: var(--muted); }}
.goal-card .name {{ font-size: 13.5px; line-height: 1.3; min-height: 2.6em; font-weight: 500; }}
.goal-card .count {{ font-family: var(--font-mono); font-size: 13px; font-variant-numeric: tabular-nums; }}
.goal-card .of {{ color: var(--muted); }}
.goal {{ padding: 26px 0 8px; border-top: 1px solid var(--line); scroll-margin-top: 16px; }}
.goal > p {{ margin: 0 0 10px; max-width: 70ch; color: var(--muted); }}
.goal > p.reached {{ color: var(--text); padding: 10px 14px; background: var(--container); border-left: 3px solid var(--accent); border-radius: 0 8px 8px 0; max-width: none; }}
ul.tasks, ul.subs, ul.plain, ol.next {{ margin: 12px 0 0; padding: 0; list-style: none; }}
ul.tasks > li {{ display: grid; grid-template-columns: 18px 1fr; gap: 10px; padding: 10px 0; border-top: 1px solid var(--line); }}
ul.tasks > li:first-child {{ border-top: 0; }}
ul.tasks p, ul.subs p {{ margin: 0; }}
ul.subs {{ margin: 8px 0 2px; display: grid; gap: 6px; }}
ul.subs > li {{ display: grid; grid-template-columns: 16px 1fr; gap: 10px; font-size: 14px; color: var(--muted); }}
ul.subs > li.open p, ul.tasks > li.open > .body > p {{ color: var(--text); }}
ul.subs > li.started p {{ color: var(--text); }}
ul.subs > li.done p, ul.tasks > li.done > .body > p {{ color: var(--muted); }}
.mark {{ width: 16px; height: 16px; border-radius: 50%; border: 2px solid var(--muted); margin-top: 3px; display: inline-block; flex: none; position: relative; }}
.mark.done {{ background: var(--accent); border-color: var(--accent); }}
.mark.done::after {{ content: ""; position: absolute; left: 4px; top: 1px; width: 4px; height: 8px; border: solid var(--accent-ink); border-width: 0 2px 2px 0; transform: rotate(45deg); }}
.mark.started {{ border-color: var(--started); background: linear-gradient(90deg, var(--started) 50%, transparent 50%); }}
ul.subs .mark {{ width: 12px; height: 12px; border-width: 2px; margin-top: 4px; }}
ul.subs .mark.done::after {{ left: 2px; top: 0; width: 3px; height: 6px; }}
ul.plain li {{ padding: 6px 0 6px 18px; position: relative; color: var(--muted); }}
ul.plain li::before {{ content: ""; position: absolute; left: 2px; top: 14px; width: 8px; height: 2px; background: var(--muted); }}
ol.next {{ counter-reset: n; display: grid; gap: 8px; }}
ol.next li {{ counter-increment: n; display: grid; grid-template-columns: 28px 1fr; gap: 10px; }}
ol.next li::before {{ content: counter(n); font-family: var(--font-mono); color: var(--accent); font-size: 14px; padding-top: 1px; }}
code {{ font-family: var(--font-mono); font-size: 0.86em; background: var(--container-high); padding: 1px 5px; border-radius: 4px; }}
a {{ color: var(--accent); text-decoration-thickness: 1px; text-underline-offset: 2px; word-break: break-word; }}
strong {{ font-weight: 600; }}
@media (max-width: 480px) {{
  h1 {{ font-size: 28px; }}
  .goals {{ grid-template-columns: repeat(2, 1fr); }}
}}
@media (prefers-reduced-motion: no-preference) {{
  .goal-card {{ transition: border-color 120ms ease; }}
}}
</style>
{body}
'''
out.write_text(page)
print(f"{out}: {len(sections)} sections, {total}")
