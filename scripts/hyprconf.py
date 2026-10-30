#!/usr/bin/env python3
"""Finds out what a Hyprland config loads and what it binds, without running Hyprland.

  hyprconf.py discover [--root PATH]
  hyprconf.py add-require FILE [--root PATH]
  hyprconf.py programs [--root PATH]    {"file", "values", "workspaceRules"}: the strings the required
                                        modules.programs returns (terminal, browser, editor, ...) and the
                                        workspace rules (as in discover); read-only, for the Apps tab

  hyprconf.py set-programs [--root PATH] [--dry-run] KEY=VALUE...
                                        {"ok", "changed", "file", "changes", "skipped", "shown", "backup", "message"}: set the string
                                        entries terminal, browser, editor or fileManager of modules/programs.lua that already exist (the
                                        Apps tab asks first, see below)

  hyprconf.py parse-binds FILE [--resolve ROOT]
                                        {"format", "file", "binds", "errors", "ignored"}: the keybinds of an export or a .conf file
                                        that Sleepysettings may import (read-only, see below)

PATH is the config folder (default $XDG_CONFIG_HOME/hypr, else ~/.config/hypr) or the main file
itself. hyprland.lua is the main file when it exists, else hyprland.conf. Prints one JSON object:

  format           "lua" or "conf"
  main             the main file
  files            [{path, missing, from, line}] in the order Hyprland loads them: the main file, then
                   each require("a.b") (-> <folder>/a/b.lua, else a/b/init.lua) or `source = path`
                   (~ and paths relative to the including file; globs allowed) where it appears.
                   Every file is read once, so cycles end; a file that does not exist has missing: true.
  binds            [{file, line, mods, key, action, raw, flags, from_loop}]
  workspaceRules   [{file, line, workspace, rules, raw}]
  monitors         [{file, line, raw, config}]
  unreadable       [{file, line, raw, reason}]  what was found but could not be turned into the above

Lua: hl.bind(keys, action, opts), hl.workspace_rule({...}), hl.monitor({...}) anywhere in a file.
Simple `local x = "..."` variables, `..`, arithmetic, tostring(), the table a required module returns
(`local app = require("modules.programs")` then app.terminal) and numeric `for i = a, b [, step] do`
loops are resolved; a loop's binds are listed once per value with from_loop true. The config is
parsed, never run: a bind that needs more than that (a Lua function, an unknown hl.dsp call, a
variable that is not a plain value, a bind inside a function body or a non-numeric loop) goes to
unreadable with the reason. `local b = hl.bind` aliases are not followed.
.conf: bind, binde, bindl, bindm, bindr, bindn (any flag letters, bindd with a description),
workspace =, monitor =, source =, $variables, `submap =` (a bind inside a submap carries "submap").

`add-require FILE` is the one command that writes (Sleepysettings asks first): when the
config does not load FILE yet it adds the line that does, `require("modules.x")` for Lua (the module name is FILE's place under the config
folder) or `source = path` for .conf, after the last such line of the main file, else at the end. Prints one JSON object
{ok, changed, line, main, backup, message}; exit 0 when the config loads FILE afterwards (also when it already did, nothing written),
1 when it was refused: no main file, FILE outside the config folder (a Lua module is named by its place there), a main file that cannot be read
or written, or a change that did not make FILE load (the main file is put back). Before writing, the main file is copied to
<main>.bak-YYYYMMDD-HHMMSS; the write is atomic (a temporary file in the same folder, then a rename; a symlinked main file is written
through to its target). Nothing else is touched.

`set-programs KEY=VALUE...` (Apps tab: the keybinds follow the default apps; Sleepysettings shows the exact changed lines and
asks first) is the second command that writes. It changes the value of an entry that already exists in the table `modules/programs.lua` returns, for the
four keys terminal, browser, editor and fileManager only (any other key is refused); it never adds or removes an entry, so a key the file does not have
is reported in `skipped`. An entry is changed only when it is one line `key = "string"` (or single quotes, simple escapes only) whose text agrees with
what `programs` evaluates; anything else (a concatenation, a value on several lines, two lines for one key) is left alone and listed in `skipped`. The new
string literal is built here from the value: backslash and the quote are escaped, control characters are refused, and the comment after the entry is kept.
A file whose strings or comments do not close is refused. `--dry-run` writes nothing and only reports `changes` ([{key, old, new, line, before, after}])
and `shown` (the lines as "- before" / "+ after"). A real run first copies the file to <file>.bak-YYYYMMDD-HHMMSS, writes atomically (a temporary
file in the same folder, then a rename; a symlink is written through), then reads the values back with `programs`: when they are not exactly the old
ones plus the changes, the original text is put back and the answer says so (ok false, exit 1). No programs.lua at all is not an error: ok true, nothing
written. Prints one JSON object; exit 0 when ok.

`parse-binds FILE [--resolve ROOT]` (Keybinds tab > Import) reads one file and writes nothing. It is stricter than `discover`: the file is never
evaluated, and a Lua file may hold nothing but comments and `hl.bind("KEYS", hl.dsp.<action>(<plain value>)[, { locked = true, ... }])`
statements: the arguments are string, number and true/false literals (no variables, no `..`, no require, no other function calls). The actions are
a closed list (IMPORT_ACTIONS: exec_cmd, window.close/pseudo/drag/resize/float/move, focus, layout, workspace.toggle_special), each with a fixed
shape; options: locked, repeating, release, mouse. Every other statement is an entry in `errors` with its line, a plain-language reason and
the line's text, and is not copied anywhere. For a .conf file the lines `bind... = MODS, KEY, dispatcher, ARG` with the matching dispatchers are
read (flags l, r, e, m; `$variables` set in the same file are substituted); every other line is only counted in `ignored`. Each bind carries
`lua`, the canonical line the importer writes: it is built here from the parsed values, never copied from the file, and `action`/`run` (the
readable action text of `discover`, and the command of an exec_cmd bind). `--resolve ROOT` (the "Hyprland defaults" file, data/hyprland-default-binds.lua)
fills @terminal@, @fileManager@ and @menu@ in commands from the programs.lua under ROOT (terminal, fileManager, launcher/menu; no fileManager
there: "xdg-open ~"), prints them as `variables`, and reports a bind whose value is missing as an error.
Exit code 0 when the file could be read (errors inside it are in the answer), 1 when it could not (`error` says why).

Python standard library only. `discover` reads files, writes nothing, starts nothing.
"""
import argparse
import bisect
import glob
import json
import math
import os
import re
import shutil
import sys
import time
from pathlib import Path

MAX_LOOP = 10000  # iterations of one numeric for loop that are expanded


class Unresolved(Exception):
    """A value that cannot be known without running the Lua."""


class ParseError(Exception):
    pass


class LuaFunction:
    """A Lua function value; it is never called."""


class Action:
    """A call of hl.dsp.<name>(...)"""

    def __init__(self, name, args):
        self.name = name
        self.args = args


# ---- Lua text helpers ---------------------------------------------------------------------------

LONG_OPEN = re.compile(r"\[(=*)\[")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
START_HOOK = re.compile(r"hl\s*\.\s*on\s*\(\s*([\"'])hyprland\.start\1\s*,\s*$")
CHAIN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_]*)*")


def long_bracket(text, i):
    """If a long bracket ([[, [=[ ...) opens at text[i], (level, index after it), else None."""
    m = LONG_OPEN.match(text, i)
    return (len(m.group(1)), m.end()) if m else None


def skip_string(text, i):
    """text[i] is a quote or a long bracket; the index after the string (or where it ends unterminated)."""
    q = text[i]
    n = len(text)
    if q in "\"'":
        j = i + 1
        while j < n:
            c = text[j]
            if c == "\\":
                j += 2
            elif c == q:
                return j + 1
            elif c == "\n":
                return j
            else:
                j += 1
        return n
    lb = long_bracket(text, i)
    if lb:
        close = "]" + "=" * lb[0] + "]"
        k = text.find(close, lb[1])
        return n if k < 0 else k + len(close)
    return i + 1


def blank_comments(text):
    """The text with every Lua comment replaced by spaces (newlines kept), so positions and lines stay."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in "\"'" or (c == "[" and long_bracket(text, i)):
            j = skip_string(text, i)
            out.append(text[i:j])
            i = j
        elif text.startswith("--", i):
            lb = long_bracket(text, i + 2) if text.startswith("[", i + 2) else None
            if lb:
                close = "]" + "=" * lb[0] + "]"
                k = text.find(close, lb[1])
                j = n if k < 0 else k + len(close)
            else:
                j = text.find("\n", i)
                j = n if j < 0 else j
            out.append(re.sub(r"[^\n]", " ", text[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def is_field_name(text, start):
    """True when the word at `start` follows a single . or : (a.b, a:b), so it is not a keyword."""
    prev = text[start - 1] if start else ""
    two = text[start - 2:start] if start >= 2 else ""
    return (prev == "." and two != "..") or (prev == ":" and two != "::")


def find_block_end(text, i, pending_do=0):
    """text[i] is just after a block opener (function, for, while, if, do); the index of its `end`.
    pending_do is 1 after `for`/`while`, whose `do` belongs to the header. -1 if there is no end."""
    depth, pend = 1, pending_do
    n = len(text)
    while i < n:
        c = text[i]
        if c in "\"'" or (c == "[" and long_bracket(text, i)):
            i = skip_string(text, i)
            continue
        m = IDENT.match(text, i)
        if not m:
            i += 1
            continue
        w, start = m.group(), i
        i = m.end()
        if is_field_name(text, start):
            continue
        if w in ("function", "if", "repeat"):
            depth += 1
        elif w in ("for", "while"):
            pend += 1
        elif w == "do":
            if pend:
                pend -= 1
            else:
                depth += 1
        elif w in ("end", "until"):
            depth -= 1
            if depth == 0:
                return start
    return -1


def fmt_number(v):
    if isinstance(v, float) and v.is_integer() and abs(v) < 1e15:
        return "%.1f" % v
    return str(v)


# ---- Lua expression parser ----------------------------------------------------------------------

TOKEN_OPS = ["...", "..", "==", "~=", "<=", ">=", "//", "<<", ">>", "::"]
NUMBER = re.compile(r"0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
KEYWORDS = {"end", "then", "do", "else", "elseif", "until", "local", "return", "if", "for", "while", "repeat", "break", "goto", "in"}
# (left, right) binding power, as in Lua's own parser
BIN_PRIO = {
    "or": (1, 1), "and": (2, 2),
    "<": (3, 3), ">": (3, 3), "<=": (3, 3), ">=": (3, 3), "~=": (3, 3), "==": (3, 3),
    "|": (4, 4), "~": (5, 5), "&": (6, 6), "<<": (7, 7), ">>": (7, 7),
    "..": (9, 8), "+": (10, 10), "-": (10, 10),
    "*": (11, 11), "/": (11, 11), "//": (11, 11), "%": (11, 11),
    "^": (14, 13),
}
UNARY_PRIO = 12
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def unescape(s):
    if "\\" not in s:
        return s
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c != "\\" or i + 1 >= len(s):
            out.append(c)
            i += 1
            continue
        d = s[i + 1]
        if d in ESCAPES:
            out.append(ESCAPES[d])
            i += 2
        elif d == "x" and re.match(r"[0-9a-fA-F]{2}", s[i + 2:i + 4]):
            out.append(chr(int(s[i + 2:i + 4], 16)))
            i += 4
        elif d.isdigit():
            digits = re.match(r"\d{1,3}", s[i + 1:]).group()
            out.append(chr(min(int(digits), 255)))
            i += 1 + len(digits)
        elif d == "z":
            i += 2
            while i < len(s) and s[i] in " \t\r\n":
                i += 1
        else:
            out.append(d)
            i += 2
    return "".join(out)


class Parser:
    """Turns Lua expression text into a small tree; `pos` is where it stopped."""

    def __init__(self, text, pos):
        self.t = text
        self.pos = pos

    def peek(self):
        """(kind, value, end) of the next token, without consuming it."""
        t, n = self.t, len(self.t)
        i = self.pos
        while i < n and t[i] in " \t\r\n":
            i += 1
        self.pos = i
        if i >= n:
            return ("eof", "", i)
        c = t[i]
        if c in "\"'":
            end = skip_string(t, i)
            body = t[i + 1:end - 1] if end - 1 > i and t[end - 1] == c else t[i + 1:end]
            return ("str", unescape(body), end)
        lb = long_bracket(t, i) if c == "[" else None
        if lb:
            end = skip_string(t, i)
            body = t[lb[1]:max(lb[1], end - (lb[0] + 2))]
            return ("str", body[1:] if body.startswith("\n") else body, end)
        m = IDENT.match(t, i)
        if m:
            return ("name", m.group(), m.end())
        if c.isdigit() or (c == "." and i + 1 < n and t[i + 1].isdigit()):
            m = NUMBER.match(t, i)
            s = m.group()
            if s[:2].lower() == "0x":
                v = int(s, 16)
            elif re.fullmatch(r"\d+", s):
                v = int(s)
            else:
                v = float(s)
            return ("num", v, m.end())
        for op in TOKEN_OPS:
            if t.startswith(op, i):
                return ("op", op, i + len(op))
        return ("op", c, i + 1)

    def next(self):
        tok = self.peek()
        self.pos = tok[2]
        return tok

    def accept(self, op):
        tok = self.peek()
        if tok[0] == "op" and tok[1] == op:
            self.pos = tok[2]
            return True
        return False

    def expect(self, op):
        if not self.accept(op):
            raise ParseError("expected %s at offset %d" % (op, self.pos))

    def expr(self, limit=0):
        tok = self.peek()
        if (tok[0] == "name" and tok[1] == "not") or (tok[0] == "op" and tok[1] in ("-", "#", "~")):
            self.pos = tok[2]
            left = ("un", tok[1], self.expr(UNARY_PRIO))
        else:
            left = self.simple()
        while True:
            tok = self.peek()
            op = tok[1] if (tok[0] == "op" or (tok[0] == "name" and tok[1] in ("and", "or"))) else None
            if op not in BIN_PRIO:
                return left
            lp, rp = BIN_PRIO[op]
            if lp <= limit:
                return left
            self.pos = tok[2]
            left = ("bin", op, left, self.expr(rp))

    def simple(self):
        kind, val, end = self.peek()
        if kind in ("num", "str"):
            self.pos = end
            return ("lit", val)
        if kind == "name" and val in ("true", "false", "nil"):
            self.pos = end
            return ("lit", {"true": True, "false": False, "nil": None}[val])
        if kind == "name" and val == "function":
            stop = find_block_end(self.t, end)
            if stop < 0:
                raise ParseError("function without end")
            self.pos = stop + 3
            return ("func",)
        if kind == "op" and val == "{":
            self.pos = end
            return self.table()
        return self.suffixed()

    def table(self):
        items, n = [], 0
        while True:
            if self.accept("}"):
                return ("table", items)
            kind, val, end = self.peek()
            named = False
            if kind == "name" and val not in ("true", "false", "nil", "function", "not"):
                save = self.pos
                self.pos = end
                if self.accept("="):
                    items.append((("lit", val), self.expr()))
                    named = True
                else:
                    self.pos = save
            elif kind == "op" and val == "[":
                self.pos = end
                key = self.expr()
                self.expect("]")
                self.expect("=")
                items.append((key, self.expr()))
                named = True
            if not named:
                n += 1
                items.append((("lit", n), self.expr()))
            if not (self.accept(",") or self.accept(";")):
                self.expect("}")
                return ("table", items)

    def call_args(self):
        kind, val, end = self.peek()
        if kind == "str":
            self.pos = end
            return [("lit", val)]
        if kind == "op" and val == "{":
            self.pos = end
            return [self.table()]
        self.expect("(")
        out = []
        if self.accept(")"):
            return out
        while True:
            out.append(self.expr())
            if self.accept(")"):
                return out
            self.expect(",")

    def suffixed(self):
        kind, val, end = self.next()
        if kind == "name":
            if val in KEYWORDS:
                raise ParseError("unexpected keyword " + val)
            node = ("name", val)
        elif kind == "op" and val == "(":
            node = ("paren", self.expr())
            self.expect(")")
        else:
            raise ParseError("unexpected %r at offset %d" % (val, self.pos))
        while True:
            kind, val, end = self.peek()
            if kind == "op" and val == ".":
                self.pos = end
                nm = self.next()
                if nm[0] != "name":
                    raise ParseError("name expected after .")
                node = ("field", node, nm[1])
            elif kind == "op" and val == "[":
                self.pos = end
                key = self.expr()
                self.expect("]")
                node = ("index", node, key)
            elif kind == "op" and val == ":":
                self.pos = end
                nm = self.next()
                if nm[0] != "name":
                    raise ParseError("method name expected")
                node = ("method", node, nm[1], self.call_args())
            elif (kind == "op" and val in ("(", "{")) or kind == "str":
                node = ("call", node, self.call_args())
            else:
                return node


def dotted(node):
    """'a.b.c' for a name/field chain, else None."""
    if node[0] == "name":
        return node[1]
    if node[0] == "field":
        base = dotted(node[1])
        return None if base is None else base + "." + node[2]
    return None


# ---- Lua evaluation -----------------------------------------------------------------------------

def is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def to_str(v):
    if isinstance(v, str):
        return v
    if is_num(v):
        return fmt_number(v)
    raise Unresolved("value is not a string or number")


def truthy(v):
    return v is not None and v is not False


def lua_eq(a, b):
    if is_num(a) and is_num(b):
        return a == b
    return type(a) is type(b) and a == b


def arith(op, a, b):
    if not (is_num(a) and is_num(b)):
        raise Unresolved("arithmetic on a value that is not a number")
    try:
        if op == "+":
            return a + b
        if op == "-":
            return a - b
        if op == "*":
            return a * b
        if op == "/":
            return a / b
        if op == "%":
            return a % b
        if op == "//":
            return a // b
        if op == "^":
            return float(a) ** b
    except (ZeroDivisionError, OverflowError):
        raise Unresolved("arithmetic error")
    raise Unresolved("operator " + op)


class Evaluator:
    def __init__(self, loader):
        self.loader = loader  # callable(module name) -> the table the module returns, or None

    def ev(self, node, env):
        k = node[0]
        if k == "lit":
            return node[1]
        if k == "paren":
            return self.ev(node[1], env)
        if k == "name":
            if node[1] in env:
                return env[node[1]]
            raise Unresolved("unknown variable " + node[1])
        if k == "field":
            base = self.ev(node[1], env) if not (dotted(node) or "").startswith("hl.") else None
            if isinstance(base, dict) and node[2] in base:
                return base[node[2]]
            raise Unresolved("unknown value " + (dotted(node) or node[2]))
        if k == "index":
            base, key = self.ev(node[1], env), self.ev(node[2], env)
            if isinstance(base, dict) and key in base:
                return base[key]
            raise Unresolved("unknown table entry")
        if k == "table":
            return {self.ev(key, env): self.ev(val, env) for key, val in node[1]}
        if k == "func":
            return LuaFunction()
        if k == "un":
            v = self.ev(node[2], env)
            if node[1] == "not":
                return not truthy(v)
            if node[1] == "-":
                return arith("-", 0, v)
            raise Unresolved("operator " + node[1])
        if k == "bin":
            return self.binop(node, env)
        if k == "call":
            return self.call(node, env)
        raise Unresolved("expression " + k)

    def table_partial(self, node, env):
        """(fields that resolve, names of those that do not) for a table literal; a variable holding a table works too."""
        if node[0] != "table":
            v = self.ev(node, env)
            if not isinstance(v, dict):
                raise Unresolved("not a table")
            return v, []
        out, bad = {}, []
        for key, val in node[1]:
            try:
                kv = self.ev(key, env)
            except Unresolved:
                bad.append("?")
                continue
            try:
                out[kv] = self.ev(val, env)
            except Unresolved:
                bad.append(str(kv))
        return out, bad

    def binop(self, node, env):
        op = node[1]
        if op == "and":
            a = self.ev(node[2], env)
            return self.ev(node[3], env) if truthy(a) else a
        if op == "or":
            a = self.ev(node[2], env)
            return a if truthy(a) else self.ev(node[3], env)
        a, b = self.ev(node[2], env), self.ev(node[3], env)
        if op == "..":
            return to_str(a) + to_str(b)
        if op == "==":
            return lua_eq(a, b)
        if op == "~=":
            return not lua_eq(a, b)
        if op in ("<", ">", "<=", ">="):
            if not ((is_num(a) and is_num(b)) or (isinstance(a, str) and isinstance(b, str))):
                raise Unresolved("comparison of different types")
            return {"<": a < b, ">": a > b, "<=": a <= b, ">=": a >= b}[op]
        return arith(op, a, b)

    def call(self, node, env):
        name = dotted(node[1])
        if name is None:
            raise Unresolved("call of an expression")
        if name.startswith("hl.dsp."):
            return Action(name[7:], [self.ev(a, env) for a in node[2]])
        if name.startswith("hl."):
            raise Unresolved("call of " + name)
        args = [self.ev(a, env) for a in node[2]]
        if name == "require":
            if len(args) != 1 or not isinstance(args[0], str):
                raise Unresolved("require of a value that is not a string")
            return self.loader(args[0])
        if name == "tostring" and len(args) == 1:
            if isinstance(args[0], bool):
                return "true" if args[0] else "false"
            return "nil" if args[0] is None else to_str(args[0])
        if name == "tonumber" and len(args) == 1:
            if is_num(args[0]):
                return args[0]
            s = to_str(args[0]).strip()
            try:
                return int(s) if re.fullmatch(r"-?\d+", s) else float(s)
            except ValueError:
                return None
        if name in ("math.floor", "math.ceil", "math.abs", "math.max", "math.min") and args and all(is_num(a) for a in args):
            if name == "math.floor":
                return math.floor(args[0])
            if name == "math.ceil":
                return math.ceil(args[0])
            if name == "math.abs":
                return abs(args[0])
            return (max if name == "math.max" else min)(args)
        raise Unresolved("call of " + name)


# ---- readable actions ---------------------------------------------------------------------------

def workspace_text(v):
    w = to_str(v)
    if w == "e+1":
        return "Next workspace"
    if w == "e-1":
        return "Previous workspace"
    if w == "special":
        return "Special workspace"
    if w.startswith("special:"):
        return "Special workspace " + w[8:]
    return "Workspace " + w


def lower_first(s):
    return s[:1].lower() + s[1:]


def plain(v):
    return isinstance(v, (str, int, float)) and not isinstance(v, bool)


def option_text(t):
    return " ".join("%s %s" % (k, v) for k, v in t.items() if isinstance(k, str) and plain(v))


def describe_action(act):
    """A readable text for an hl.dsp action, or raise Unresolved(reason)."""
    n, a = act.name, act.args
    arg = a[0] if a else None
    tab = arg if isinstance(arg, dict) else {}
    if n in ("exec_cmd", "exec_raw"):
        return "Run " + to_str(arg)
    if n == "event":
        return "Event " + to_str(arg)
    if n == "layout":
        return "Layout: " + to_str(arg)
    if n == "focus":
        if "direction" in tab:
            return "Focus " + to_str(tab["direction"])
        if "workspace" in tab:
            return workspace_text(tab["workspace"])
        if "monitor" in tab:
            return "Focus monitor " + to_str(tab["monitor"])
        if "window" in tab:
            return "Focus window " + to_str(tab["window"])
        raise Unresolved("hl.dsp.focus with arguments this parser does not know")
    if n.startswith("window."):
        verb = n[7:]
        fixed = {"close": "Close window", "kill": "Kill window", "pseudo": "Toggle pseudo-tiling", "drag": "Drag window",
                 "fullscreen": "Toggle fullscreen", "pin": "Toggle pin", "center": "Center window"}
        if verb in fixed:
            return fixed[verb]
        if verb == "float":
            return {"enable": "Float window", "disable": "Tile window"}.get(tab.get("action"), "Toggle floating")
        if verb == "resize":
            return "Resize window" + (" " + option_text(tab) if tab else "")
        if verb == "move":
            if "workspace" in tab:
                return "Move window to " + lower_first(workspace_text(tab["workspace"]))
            if "direction" in tab:
                return "Move window " + to_str(tab["direction"])
        extra = option_text(tab) if tab else (to_str(arg) if plain(arg) else "")
        return "Window " + verb.replace("_", " ") + (" " + extra if extra else "")
    if n.startswith("workspace."):
        verb = n[10:]
        if verb == "toggle_special":
            return "Toggle special workspace " + to_str(arg)
        extra = option_text(tab) if tab else (to_str(arg) if plain(arg) else "")
        return "Workspace " + verb.replace("_", " ") + (" " + extra if extra else "")
    raise Unresolved("unsupported action hl.dsp." + n)


def split_keys(s):
    """'SUPER + SHIFT + M' -> (['SUPER', 'SHIFT'], 'M')."""
    parts = [p.strip() for p in s.split("+") if p.strip()]
    if not parts:
        return [], s.strip()
    return [p.upper() for p in parts[:-1]], parts[-1]


# ---- Lua discovery ------------------------------------------------------------------------------

class Discovery:
    def __init__(self, root):
        self.root = root
        self.files = []
        self.seen = set()
        self.binds = []
        self.workspace_rules = []
        self.monitors = []
        self.execs = []         # hl.exec_cmd(cmd, opts) calls: the apps a config starts (the Apps tab's "apps on workspaces")
        self.window_rules = []  # hl.window_rule({...}) that send a window to a workspace
        self.unreadable = []
        self.modules = {}  # path -> the table the module returned, or None
        self.ev = Evaluator(self.load_module)
        self.stack = []  # frames of the files being scanned, innermost last
        self.last_return = None
        # inside hl.on("hyprland.start", function() ... end): run once when Hyprland starts (the usual place for autostart lines)
        self.at_start = False

    def add_file(self, path, missing=False, frm=None, line=None):
        self.files.append({"path": str(path), "missing": missing, "from": str(frm) if frm else None, "line": line})

    def cur(self):
        return self.stack[-1]

    def line_of(self, pos):
        return bisect.bisect_left(self.cur()["nl"], pos) + 1

    def load_module(self, name):
        rel = Path(*name.split("."))
        cands = [self.root / (str(rel) + ".lua"), self.root / rel / "init.lua"]
        path = next((c for c in cands if c.is_file()), None)
        frm = self.cur()
        line = self.line_of(frm["pos"])
        if path is None:
            if str(cands[0]) not in self.seen:
                self.seen.add(str(cands[0]))
                self.add_file(cands[0], True, frm["path"], line)
            return None
        key = str(path)
        if key in self.seen:
            return self.modules.get(key)  # Lua's require cache; None while that file is still loading (a cycle)
        self.seen.add(key)
        self.add_file(path, False, frm["path"], line)
        self.modules[key] = None
        self.scan_file(path)
        return self.modules.get(key)

    def scan_file(self, path):
        try:
            text = Path(path).read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            self.unreadable.append({"file": str(path), "line": 0, "raw": "", "reason": "cannot read file: " + str(e.strerror)})
            return
        clean = blank_comments(text)
        self.stack.append({"path": str(path), "text": text, "nl": [m.start() for m in re.finditer("\n", text)], "pos": 0})
        try:
            self.last_return = None
            ret = self.scan(clean, 0, len(clean), {}, False, None)
        finally:
            self.stack.pop()
        if isinstance(ret, dict):
            self.modules[str(path)] = ret

    def raw_of(self, start, end):
        return re.sub(r"\s+", " ", self.cur()["text"][start:end]).strip()

    def bad(self, start, end, reason):
        self.unreadable.append({"file": self.cur()["path"], "line": self.line_of(start), "raw": self.raw_of(start, end), "reason": reason})

    def record_call(self, kind, node, start, end, env, in_loop):
        f, line, raw, args = self.cur()["path"], self.line_of(start), self.raw_of(start, end), node[2]
        try:
            if kind == "hl.bind":
                if len(args) < 2:
                    raise Unresolved("hl.bind with fewer than two arguments")
                keys = self.ev.ev(args[0], env)
                if not isinstance(keys, str):
                    raise Unresolved("key is not a string")
                act = self.ev.ev(args[1], env)
                if isinstance(act, LuaFunction):
                    raise Unresolved("action is a Lua function")
                if not isinstance(act, Action):
                    raise Unresolved("action is not an hl.dsp call")
                text = describe_action(act)
                opts = self.ev.table_partial(args[2], env)[0] if len(args) > 2 else {}
                mods, key = split_keys(keys)
                self.binds.append({"file": f, "line": line, "mods": mods, "key": key, "action": text, "raw": raw,
                                   "flags": [k for k, v in opts.items() if isinstance(k, str) and v is True],
                                   "from_loop": in_loop})
            elif kind == "hl.exec_cmd":
                if not args:
                    raise Unresolved("exec_cmd without a command")
                cmd = self.ev.ev(args[0], env)
                if not isinstance(cmd, str):
                    raise Unresolved("the command is not a string")
                opts = {}
                if len(args) > 1:
                    o, _bad = self.ev.table_partial(args[1], env)
                    opts = {k: v for k, v in o.items() if isinstance(k, str) and not isinstance(v, (LuaFunction, Action))}
                rec = {"file": f, "line": line, "command": cmd, "raw": raw, "atStart": self.at_start}
                if "workspace" in opts:
                    rec["workspace"] = to_str(opts["workspace"])
                rest = {k: v for k, v in opts.items() if k != "workspace"}
                if rest:
                    rec["options"] = rest
                self.execs.append(rec)
            elif kind == "hl.window_rule":
                if not args:
                    raise Unresolved("window rule without arguments")
                rule, _bad = self.ev.table_partial(args[0], env)
                if "workspace" not in rule:
                    return  # only the rules that place a window on a workspace are reported
                match = rule.get("match") if isinstance(rule.get("match"), dict) else {}
                self.window_rules.append({"file": f, "line": line, "name": to_str(rule.get("name", "")),
                                          "match": {k: to_str(v) for k, v in match.items() if isinstance(k, str)},
                                          "workspace": to_str(rule["workspace"]), "raw": raw})
            elif kind == "hl.workspace_rule":
                if not args:
                    raise Unresolved("workspace rule without arguments")
                rule, bad = self.ev.table_partial(args[0], env)
                if "workspace" not in rule:
                    raise Unresolved("workspace rule without a resolvable workspace field")
                rest = {k: v for k, v in rule.items() if k != "workspace" and isinstance(k, str) and not isinstance(v, (LuaFunction, Action))}
                rec = {"file": f, "line": line, "workspace": to_str(rule["workspace"]), "rules": rest, "raw": raw}
                if bad:
                    rec["unresolved"] = bad
                self.workspace_rules.append(rec)
            else:
                cfg, bad = {}, []
                if args:
                    try:
                        cfg, bad = self.ev.table_partial(args[0], env)
                    except Unresolved:
                        cfg = {}
                cfg = {k: v for k, v in cfg.items() if isinstance(k, str) and not isinstance(v, (LuaFunction, Action))}
                rec = {"file": f, "line": line, "raw": raw, "config": cfg}
                if bad:
                    rec["unresolved"] = bad
                self.monitors.append(rec)
        except Unresolved as e:
            self.bad(start, end, str(e))

    def scan(self, text, a, b, env, in_loop, ctx):
        """Walks text[a:b]. ctx is None, or the reason that every bind found here is unreadable.
        Returns the value of a top-level `return`, if any."""
        i, depth, ret = a, 0, None
        while i < b:
            c = text[i]
            if c in "\"'" or (c == "[" and long_bracket(text, i)):
                i = skip_string(text, i)
                continue
            if c in "({[":
                depth += 1
                i += 1
                continue
            if c in ")}]":
                depth -= 1
                i += 1
                continue
            m = IDENT.match(text, i)
            if not m:
                i += 1
                continue
            start = i
            i = m.end()
            if is_field_name(text, start):
                continue
            word = m.group()
            chain = CHAIN.match(text, start)
            if chain and chain.group().startswith("hl"):
                full = re.sub(r"\s+", "", chain.group())
                if full in ("hl.bind", "hl.workspace_rule", "hl.monitor", "hl.exec_cmd", "hl.window_rule"):
                    word, i = full, chain.end()
            self.cur()["pos"] = start
            if word == "for":
                i = self.do_for(text, i, env, ctx)
            elif word == "function":
                stop = find_block_end(text, i)
                if stop < 0:
                    return ret
                # the start-up callback runs once, with nothing passed in: its calls count like the file's own (an autostart
                # file starts and places its apps there); any other function body is not run when the file loads
                if ctx is None and START_HOOK.search(text[max(a, start - 200):start]):
                    outer = self.at_start
                    self.at_start = True
                    body = re.compile(r"\s*\(\s*\)").match(text, i)
                    self.scan(text, body.end() if body else i, stop, dict(env), False, None)
                    self.at_start = outer
                else:
                    self.scan(text, i, stop, dict(env), False, "inside a function body (not run when the file loads)")
                i = stop + 3
            elif word in ("hl.bind", "hl.workspace_rule", "hl.monitor", "hl.exec_cmd", "hl.window_rule"):
                if not re.compile(r"\s*\(").match(text, i):
                    continue
                p = Parser(text, start)
                try:
                    node = p.expr()
                except ParseError as e:
                    self.bad(start, min(b, i + 80), "cannot parse the call: " + str(e))
                    continue
                if node[0] != "call" or dotted(node[1]) != word:
                    continue
                if ctx is not None:
                    self.bad(start, p.pos, ctx)
                else:
                    # the parser stops at the next token, past the blanked comments that follow the call; the raw text ends at
                    # the call, plus the rest of its line when that is only a comment (the bind's own note), so the comment
                    # heading the next block is not read as the note of the bind above it.
                    end = start + len(text[start:p.pos].rstrip())
                    eol = text.find("\n", end)
                    eol = len(text) if eol == -1 else eol
                    if eol <= p.pos and text[end:eol].strip() == "":
                        end = eol
                    self.record_call(word, node, start, end, env, in_loop)
                i = p.pos
            elif word == "local" or word == "require" or (word == "return" and depth == 0) or \
                    (depth == 0 and re.compile(r"\s*=(?!=)").match(text, i)):
                i, val = self.statement(text, word, i, env, ctx)
                if word == "return" and isinstance(val, dict):
                    ret = val
        return ret

    def statement(self, text, word, i, env, ctx):
        """local x = expr / x = expr / return expr / require("m"). Returns (index to continue at, value)."""
        start = i - len(word)
        if word == "local":
            if re.compile(r"\s+function\b").match(text, i):
                return i, None  # the scanner meets the `function` next
            names = re.compile(r"\s*([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*(?:<\w+>)?\s*=(?!=)").match(text, i)
            if not names:
                return i, None  # `local x` without a value
            for n in re.split(r"\s*,\s*", names.group(1)):
                env.pop(n, None)
            if "," in names.group(1):
                return names.end(), None
            target, pos = names.group(1), names.end()
        elif word == "return":
            target, pos = None, i
        elif word == "require":
            target, pos = None, start
        else:
            target, pos = word, re.compile(r"\s*=(?!=)").match(text, i).end()
        p = Parser(text, pos)
        try:
            node = p.expr()
        except ParseError:
            return i, None
        nxt = max(p.pos, i)
        if ctx is not None:
            return nxt, None
        try:
            val = self.ev.ev(node, env)
        except Unresolved:
            if target:
                env.pop(target, None)
            return nxt, None
        if target:
            if isinstance(val, (Action, LuaFunction)):
                env.pop(target, None)
            else:
                env[target] = val
        return nxt, val

    def do_for(self, text, i, env, ctx):
        """text[i] is just after `for`. Returns the index after the loop's `end`."""
        end = find_block_end(text, i, 1)
        if end < 0:
            return i
        header = re.compile(r"\s*([A-Za-z_]\w*)\s*=(?!=)").match(text, i)
        if ctx is not None:
            reason = ctx
        elif not header:
            reason = "loop is not a numeric for"
        else:
            reason = None
            p = Parser(text, header.end())
            try:
                lo = p.expr()
                p.expect(",")
                hi = p.expr()
                step = ("lit", 1)
                if p.accept(","):
                    step = p.expr()
                tok = p.next()
                if tok[:2] != ("name", "do"):
                    raise ParseError("do expected")
                body_start = p.pos
                lo_v, hi_v, st_v = (self.ev.ev(n, env) for n in (lo, hi, step))
                if not all(is_num(v) for v in (lo_v, hi_v, st_v)):
                    raise Unresolved("loop bound is not a number")
                if st_v == 0:
                    raise Unresolved("loop step is 0")
                values, v = [], lo_v
                while (v <= hi_v if st_v > 0 else v >= hi_v):
                    values.append(v)
                    v += st_v
                    if len(values) > MAX_LOOP:
                        raise Unresolved("loop runs more than %d times" % MAX_LOOP)
            except ParseError as e:
                reason = "loop header: " + str(e)
            except Unresolved as e:
                reason = "loop not expanded: " + str(e)
        if reason is None:
            for v in values:
                e2 = dict(env)
                e2[header.group(1)] = v
                self.scan(text, body_start, end, e2, True, None)
        else:
            # not expandable: every bind in the body is reported once as unreadable
            m = re.compile(r"\bdo\b").search(text, i, end)
            self.scan(text, m.end() if m else i, end, dict(env), True, reason)
        return end + 3


def discover_lua(main, root):
    d = Discovery(root)
    d.seen.add(str(main))
    d.add_file(main)
    d.modules[str(main)] = None
    d.scan_file(main)
    return d


# ---- .conf --------------------------------------------------------------------------------------

CONF_FLAGS = {"l": "locked", "r": "release", "e": "repeating", "n": "non_consuming", "m": "mouse", "t": "transparent",
              "i": "ignore_mods", "s": "separate", "o": "long_press", "c": "click", "g": "drag", "p": "bypass_inhibit", "k": "submap_catch"}
DIRS = {"l": "left", "r": "right", "u": "up", "d": "down"}
CONF_DISPATCH = {
    "killactive": "Close window", "forcekillactive": "Kill window", "togglefloating": "Toggle floating",
    "pseudo": "Toggle pseudo-tiling", "fullscreen": "Toggle fullscreen", "pin": "Toggle pin",
    "centerwindow": "Center window", "togglesplit": "Layout: togglesplit", "swapsplit": "Layout: swapsplit",
    "exit": "Exit Hyprland", "togglegroup": "Toggle group", "lockactivegroup": "Lock group",
    "changegroupactive": "Change group tab", "cyclenext": "Cycle windows", "swapnext": "Swap with next window",
    "bringactivetotop": "Bring window to top",
}


def conf_action(disp, arg, mouse):
    d, a = disp.strip(), arg.strip()
    if d in ("exec", "execr"):
        return "Run " + a
    if d == "movefocus":
        return "Focus " + DIRS.get(a, a)
    if d == "movewindow":
        return "Move window " + DIRS[a] if a in DIRS else ("Drag window" if mouse else "Move window")
    if d == "resizewindow":
        return "Resize window"
    if d == "resizeactive":
        return "Resize window " + a
    if d == "workspace":
        return workspace_text(a)
    if d in ("movetoworkspace", "movetoworkspacesilent"):
        return "Move window to " + lower_first(workspace_text(a))
    if d == "togglespecialworkspace":
        return "Toggle special workspace " + a
    if d == "layoutmsg":
        return "Layout: " + a
    if d == "focusmonitor":
        return "Focus monitor " + a
    if d == "submap":
        return "Submap " + a
    if d in CONF_DISPATCH:
        return CONF_DISPATCH[d] + (" " + a if a and d in ("fullscreen", "cyclenext") else "")
    raise Unresolved("unsupported dispatcher " + d)


def strip_conf_comment(line):
    s = line.replace("##", "\0")
    k = s.find("#")
    return (s[:k] if k >= 0 else s).replace("\0", "#")


def discover_conf(main, root):
    d = Discovery(root)
    variables = {}

    def subst(s):
        for name in sorted(variables, key=len, reverse=True):
            s = s.replace("$" + name, variables[name])
        return s

    def read(path, frm=None, line=None):
        key = str(path)
        if key in d.seen:
            return
        d.seen.add(key)
        if not Path(path).is_file():
            d.add_file(path, True, frm, line)
            return
        d.add_file(path, False, frm, line)
        try:
            lines = Path(path).read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError as e:
            d.unreadable.append({"file": key, "line": 0, "raw": "", "reason": "cannot read file: " + str(e.strerror)})
            return
        depth, submap = 0, ""
        for no, orig in enumerate(lines, 1):
            text = strip_conf_comment(orig).strip()
            if not text:
                continue
            if text.endswith("{") and "=" not in text:
                depth += 1
                continue
            if text == "}":
                depth = max(0, depth - 1)
                continue
            if "=" not in text:
                continue
            k, _, v = text.partition("=")
            k, v = k.strip(), v.strip()
            if k.startswith("$"):
                variables[k[1:]] = subst(v)
                continue
            if depth:
                continue
            raw = re.sub(r"\s+", " ", orig.strip())
            v = subst(v)
            if k == "source":
                target = os.path.expanduser(v)
                if not os.path.isabs(target):
                    target = os.path.join(os.path.dirname(key), target)
                if any(ch in target for ch in "*?["):
                    for hit in sorted(glob.glob(target)):
                        read(Path(hit), key, no)
                else:
                    read(Path(os.path.normpath(target)), key, no)
            elif k == "submap":
                submap = "" if v == "reset" else v
            elif k == "monitor":
                parts = [x.strip() for x in v.split(",")]
                cfg = {"output": parts[0]}
                cfg.update(zip(("mode", "position", "scale"), parts[1:4]))
                if len(parts) > 4:
                    cfg["extra"] = parts[4:]
                d.monitors.append({"file": key, "line": no, "raw": raw, "config": cfg})
            elif k == "workspace":
                parts = [x.strip() for x in v.split(",")]
                rules = {}
                for p in parts[1:]:
                    rk, sep, rv = p.partition(":")
                    rules[rk.strip()] = {"true": True, "false": False}.get(rv.strip(), rv.strip()) if sep else True
                d.workspace_rules.append({"file": key, "line": no, "workspace": parts[0], "rules": rules, "raw": raw})
            elif re.fullmatch(r"bind[a-z]*", k):
                letters = k[4:]
                if any(ch not in CONF_FLAGS and ch != "d" for ch in letters):
                    d.unreadable.append({"file": key, "line": no, "raw": raw, "reason": "unknown bind flag in " + k})
                    continue
                size = 5 if "d" in letters else 4  # mods, key, [description,] dispatcher, argument
                fields = [x.strip() for x in v.split(",", size - 1)]
                if len(fields) < size - 1:
                    d.unreadable.append({"file": key, "line": no, "raw": raw, "reason": "too few fields in bind"})
                    continue
                fields += [""] * (size - len(fields))
                flags = [CONF_FLAGS[ch] for ch in letters if ch in CONF_FLAGS]
                try:
                    action = conf_action(fields[size - 2], fields[size - 1], "m" in letters)
                except Unresolved as e:
                    d.unreadable.append({"file": key, "line": no, "raw": raw, "reason": str(e)})
                    continue
                rec = {"file": key, "line": no, "mods": [x.upper() for x in re.split(r"[\s_+]+", fields[0]) if x],
                       "key": fields[1], "action": action, "raw": raw, "flags": flags, "from_loop": False}
                if submap:
                    rec["submap"] = submap
                d.binds.append(rec)

    read(main)
    return d


# ---- main ---------------------------------------------------------------------------------------

def find_main(root):
    root = Path(root).expanduser()
    if root.is_file():
        return root.parent, root, ("lua" if root.suffix == ".lua" else "conf")
    for name, fmt in (("hyprland.lua", "lua"), ("hyprland.conf", "conf")):
        if (root / name).is_file():
            return root, root / name, fmt
    return root, None, None


def discover(root_arg=None):
    if root_arg:
        root = Path(root_arg)
    else:
        root = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "hypr"
    folder, main, fmt = find_main(root)
    out = {"format": fmt, "main": str(main) if main else None, "files": [], "binds": [], "workspaceRules": [],
           "monitors": [], "unreadable": []}
    if main is None:
        out["error"] = "no hyprland.lua or hyprland.conf in " + str(folder)
        return out
    d = discover_lua(main, folder) if fmt == "lua" else discover_conf(main, folder)
    out.update(files=d.files, binds=d.binds, workspaceRules=d.workspace_rules, monitors=d.monitors, unreadable=d.unreadable,
               execs=getattr(d, "execs", []), windowRules=getattr(d, "window_rules", []))
    return out


# ---- add-require --------------------------------------------------------------------------------

LUA_REQUIRE_LINE = re.compile(r"^(?:local\s+[A-Za-z_][\w, ]*=\s*)?require\s*\(")
CONF_SOURCE_LINE = re.compile(r"^\s*source\s*=")


def line_offsets(text):
    """Start offset of each line of text."""
    out = [0]
    for m in re.finditer("\n", text):
        out.append(m.end())
    return out


def insertion_point(text, fmt):
    """Offset to insert a new line at: after the last top-level require (Lua, a line that starts in column 0) or source line (.conf),
    else the end of the text (a newline is added first when the text does not end with one)."""
    probe = blank_comments(text) if fmt == "lua" else text
    starts = line_offsets(text)
    last = -1
    for i, st in enumerate(starts):
        en = starts[i + 1] if i + 1 < len(starts) else len(text)
        ln = probe[st:en]
        if (LUA_REQUIRE_LINE if fmt == "lua" else CONF_SOURCE_LINE).match(ln):
            last = i
    if last >= 0:
        return starts[last + 1] if last + 1 < len(starts) else len(text)
    return len(text)


def lua_closed(text):
    """False when a string, long string or comment in the Lua text is never closed (then no line can be placed safely)."""
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in "\"'":
            j = skip_string(text, i)
            if j <= i + 1 or text[j - 1] != c or text[i + 1:j - 1].count("\\") and text[j - 2] == "\\" and text[j - 3:j - 1] != "\\\\":
                return False
            i = j
        elif c == "[" and long_bracket(text, i):
            lb = long_bracket(text, i)
            if text.find("]" + "=" * lb[0] + "]", lb[1]) < 0:
                return False
            i = skip_string(text, i)
        elif text.startswith("--", i):
            lb = long_bracket(text, i + 2) if text.startswith("[", i + 2) else None
            if lb:
                k = text.find("]" + "=" * lb[0] + "]", lb[1])
                if k < 0:
                    return False
                i = k + lb[0] + 2
            else:
                j = text.find("\n", i)
                i = n if j < 0 else j
        else:
            i += 1
    return True


def new_line_for(target, folder, main_dir, fmt):
    """The line that makes the config load `target`, or (None, why)."""
    if fmt == "lua":
        if target.suffix != ".lua":
            return None, "only a .lua file can be loaded by hyprland.lua"
        try:
            rel = target.relative_to(folder)
        except ValueError:
            return None, "the file is outside the Hyprland folder, so hyprland.lua cannot load it by name; move it into that folder"
        name = ".".join(rel.with_suffix("").parts)
        if not all(re.fullmatch(r"[A-Za-z0-9_\-]+", part) for part in rel.with_suffix("").parts):
            return None, "the file name has characters a Lua module name cannot have"
        return 'require("' + name + '")', ""
    try:
        shown = str(target.relative_to(main_dir))
    except ValueError:
        home = Path.home()
        try:
            shown = "~/" + str(target.relative_to(home))
        except ValueError:
            shown = str(target)
    return "source = " + shown, ""


def add_require(target_arg, root_arg=None):
    out = {"ok": False, "changed": False, "line": "", "main": None, "backup": "", "message": ""}

    def fail(msg):
        out["message"] = msg
        return out

    root = Path(root_arg) if root_arg else Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "hypr"
    folder, main, fmt = find_main(root)
    if main is None:
        return fail("There is no hyprland.lua or hyprland.conf in " + str(folder) + ".")
    out["main"] = str(main)
    target = Path(target_arg).expanduser()
    if not target.is_absolute():
        target = folder / target
    d = discover(root_arg)
    if any(f["path"] == str(target) and not f.get("missing") for f in d["files"]):
        out.update(ok=True, message="Hyprland already loads this file.")
        return out
    line, why = new_line_for(target, folder, main.parent, fmt)
    if line is None:
        return fail("Can't add it: " + why + ".")
    out["line"] = line
    real = Path(os.path.realpath(main))
    try:
        text = real.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        return fail("Can't read " + str(main) + " (" + str(getattr(e, "strerror", None) or e) + ").")
    if not os.access(real, os.W_OK) or not os.access(real.parent, os.W_OK | os.X_OK):
        return fail("Can't change " + str(main) + ": it is read-only for you.")
    # a main file whose strings or comments do not close cannot be edited safely: the place of a line would be a guess
    if fmt == "lua" and not lua_closed(text):
        return fail("Can't read " + str(main) + " well enough to change it safely (a string or comment is not closed).")
    at = insertion_point(text, fmt)
    new = text[:at] + ("" if at == 0 or text[:at].endswith("\n") else "\n") + line + "\n" + text[at:]
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = Path(str(real) + ".bak-" + stamp)
    n = 1
    while backup.exists():
        backup = Path(str(real) + ".bak-" + stamp + "-" + str(n))
        n += 1
    try:
        shutil.copy2(real, backup)
        out["backup"] = str(backup)
        tmp = real.with_name(real.name + ".tmp-" + str(os.getpid()))
        tmp.write_text(new, encoding="utf-8")
        shutil.copymode(real, tmp)
        os.replace(tmp, real)
    except OSError as e:
        return fail("Could not write " + str(main) + " (" + str(e.strerror) + "). It was left as it was.")
    d2 = discover(root_arg)
    if not any(f["path"] == str(target) for f in d2["files"]):
        real.write_text(text, encoding="utf-8")
        return fail("The line was added but Hyprland would still not load the file, so " + str(main) + " was put back.")
    out.update(ok=True, changed=True, message="Added " + line + " to " + str(main) + ".")
    return out


def is_test_rule(r):
    """A rule of the test kit's virtual monitor ("sleepytest…"), left out of what the Apps tab shows."""
    vals = [str(r.get("workspace", "")), str(r.get("name", ""))] + [str(v) for v in (r.get("rules") or {}).values()]
    return any("sleepytest" in v for v in vals) or "(sandbox)" in str(r.get("match", ""))


def app_word(command):
    """The program a command line starts, for display: the word after the last `exec`, else the first word, without its path."""
    words = re.findall(r"[^\s;&|]+", command)
    for i in range(len(words) - 1, -1, -1):
        if words[i] == "exec" and i + 1 < len(words):
            return Path(words[i + 1]).name
    return Path(words[0]).name if words else ""


def workspace_apps(d):
    """The apps the config itself places on a workspace (the Apps tab shows them read only): hl.exec_cmd calls with a
    workspace option, and window rules with a workspace, as [{kind, app, workspace, file, line, raw}]."""
    out = []
    for e in getattr(d, "execs", []):
        if e.get("workspace"):
            out.append({"kind": "exec", "app": app_word(e["command"]), "workspace": e["workspace"], "atStart": e.get("atStart", False),
                        "file": e["file"], "line": e["line"], "raw": e["raw"]})
    for w in getattr(d, "window_rules", []):
        if is_test_rule(w):
            continue
        cls = w["match"].get("class") or w["match"].get("initial_class") or w["match"].get("title") or ""
        app = re.sub(r"[\^$\\]", "", cls)
        out.append({"kind": "rule", "app": app, "workspace": w["workspace"], "file": w["file"], "line": w["line"], "raw": w["raw"]})
    return out


def programs(root_arg=None):
    """The string entries of the table `modules/programs.lua` returns ({} and file None when there is none)."""
    if root_arg:
        root = Path(root_arg)
    else:
        root = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "hypr"
    folder, main_file, fmt = find_main(root)
    out = {"file": None, "values": {}, "workspaceRules": [], "workspaceApps": []}
    if main_file is None:
        return out
    d = discover_lua(main_file, folder) if fmt == "lua" else discover_conf(main_file, folder)
    # the test kit's virtual monitor and its rules are not the user's (sleepyshell-tests)
    out["workspaceRules"] = [r for r in d.workspace_rules if not is_test_rule(r)]
    out["workspaceApps"] = workspace_apps(d)
    if fmt != "lua":
        return out
    for path, table in d.modules.items():
        if Path(path).name == "programs.lua" and isinstance(table, dict):
            out["file"] = path
            out["values"] = {k: v for k, v in table.items() if isinstance(v, str)}
            break
    return out

# ---- set-programs (Apps tab) ------------------------------------------------------------------------

PROGRAM_KEYS = ("terminal", "browser", "editor", "fileManager")
LUA_ESCAPES = {"\\": "\\", '"': '"', "'": "'", "n": "\n", "t": "\t"}


def lua_string_at(s, i):
    """(value, end) of the short Lua string literal starting at s[i] (a quote), or None when it has other escapes or does not close on the line."""
    q = s[i]
    out, j = [], i + 1
    while j < len(s):
        c = s[j]
        if c == q:
            return "".join(out), j + 1
        if c == "\\":
            if j + 1 >= len(s) or s[j + 1] not in LUA_ESCAPES:
                return None
            out.append(LUA_ESCAPES[s[j + 1]])
            j += 2
            continue
        out.append(c)
        j += 1
    return None


def lua_quote(v):
    return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'


def set_programs(pairs, root_arg=None, dry=False):
    out = {"ok": False, "changed": False, "dryRun": dry, "file": None, "changes": [], "skipped": [], "shown": "", "backup": "", "message": ""}

    def fail(msg):
        out["message"] = msg
        return out

    wanted = {}
    for k, v in pairs:
        if k not in PROGRAM_KEYS:
            return fail("Only " + ", ".join(PROGRAM_KEYS) + " can be set (not " + repr(k) + ").")
        if not isinstance(v, str) or not v.strip() or len(v) > 500 or re.search(r"[\x00-\x1f\x7f]", v):
            return fail("The value for " + k + " is empty, too long or has control characters.")
        wanted[k] = v.strip()
    cur = programs(root_arg)
    if not cur["file"]:
        out.update(ok=True, message="There is no modules/programs.lua; nothing to change.")
        return out
    path = Path(cur["file"])
    out["file"] = str(path)
    real = Path(os.path.realpath(path))
    try:
        text = real.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        return fail("Can't read " + str(path) + " (" + str(getattr(e, "strerror", None) or e) + ").")
    if not lua_closed(text):
        return fail("Can't read " + str(path) + " well enough to change it safely (a string or comment is not closed).")
    lines = text.splitlines(keepends=True)
    new_lines = list(lines)
    for key in PROGRAM_KEYS:
        if key not in wanted:
            continue
        if key not in cur["values"]:
            out["skipped"].append({"key": key, "why": "programs.lua has no " + key + " entry (none is added)"})
            continue
        old, new = cur["values"][key], wanted[key]
        if old == new:
            continue
        hits = []
        for n, raw in enumerate(lines):
            m = re.match(r"^([ \t]*" + key + r"[ \t]*=[ \t]*)([\"'])", raw)
            if m:
                lit = lua_string_at(raw, m.end(1))
                hits.append((n, m, lit, raw))
        ok_hits = [h for h in hits if h[2] is not None and h[2][0] == old and re.match(r"^[ \t]*[,;]?[ \t]*(--.*)?$", h[3][h[2][1]:].rstrip("\r\n"))]
        if len(hits) != 1 or len(ok_hits) != 1:
            out["skipped"].append({"key": key, "why": "the entry is not a plain one-line string, so it is left alone"})
            continue
        n, m, lit, raw = ok_hits[0]
        body = raw.rstrip("\r\n")
        ending = raw[len(body):]
        after = m.group(1) + lua_quote(new) + body[lit[1]:] + ending
        new_lines[n] = after
        out["changes"].append({"key": key, "old": old, "new": new, "line": n + 1, "before": body.strip(), "after": after.rstrip("\r\n").strip()})
    out["shown"] = "\n".join("- " + c["before"] + "\n+ " + c["after"] for c in out["changes"])
    if not out["changes"]:
        out.update(ok=True, message="programs.lua already has these values." if not out["skipped"] else "Nothing could be changed.")
        return out
    if dry:
        out.update(ok=True, message="Would change " + str(len(out["changes"])) + " line(s) of " + str(path) + ".")
        return out
    if not os.access(real, os.W_OK) or not os.access(real.parent, os.W_OK | os.X_OK):
        return fail("Can't change " + str(path) + ": it is read-only for you.")
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = Path(str(real) + ".bak-" + stamp)
    n = 1
    while backup.exists():
        backup = Path(str(real) + ".bak-" + stamp + "-" + str(n))
        n += 1

    def write(content):
        tmp = real.with_name(real.name + ".tmp-" + str(os.getpid()))
        tmp.write_text(content, encoding="utf-8")
        shutil.copymode(real, tmp)
        os.replace(tmp, real)

    try:
        shutil.copy2(real, backup)
        out["backup"] = str(backup)
        write("".join(new_lines))
    except OSError as e:
        return fail("Could not write " + str(path) + " (" + str(e.strerror) + "). It was left as it was.")
    expect = dict(cur["values"])
    expect.update({c["key"]: c["new"] for c in out["changes"]})
    if programs(root_arg)["values"] != expect:
        try:
            write(text)
        except OSError:
            return fail("The new values did not read back and " + str(path) + " could not be put back: the backup is " + str(backup) + ".")
        return fail("The new values did not read back from " + str(path) + ", so it was put back.")
    out.update(ok=True, changed=True, message="Changed " + str(len(out["changes"])) + " line(s) of " + str(path) + ".")
    return out


# ---- parse-binds (Keybinds tab > Import) ----------------------------------------------------------

IMPORT_MAX_BYTES = 256 * 1024
IMPORT_MAX_COMMAND = 2000
IMPORT_MODS = {"SUPER": "SUPER", "CTRL": "CTRL", "CONTROL": "CTRL", "ALT": "ALT", "SHIFT": "SHIFT"}
IMPORT_FLAGS = ("locked", "repeating", "release", "mouse")  # the options an imported keybind may carry
IMPORT_KEY = re.compile(r"[A-Za-z0-9_:]+")
NO_MOD_OK = re.compile(r"(F\d+|Print|XF86\w+)", re.I)
# the only actions an import writes, each in a fixed shape (name -> (arguments, allowed table keys)); anything else is refused. The line written
# is built from the parsed values, never copied from the file.
IMPORT_ACTIONS = {
    "exec_cmd": ("text", ()),
    "window.close": ("none", ()), "window.pseudo": ("none", ()), "window.drag": ("none", ()), "window.resize": ("none", ()),
    "window.float": ("table", ("action",)), "window.move": ("table", ("workspace", "direction")),
    "focus": ("table", ("direction", "workspace")), "layout": ("word", ()), "workspace.toggle_special": ("word", ()),
}
IMPORT_WORD = re.compile(r"[A-Za-z0-9_:+\-.]{1,40}")
# in the Hyprland example config these names are variables; the "Hyprland defaults" file writes them as @name@ and `--resolve` fills them in
DEFAULT_VARS = ("terminal", "fileManager", "menu")


def lua_quote(s):
    """A Lua double-quoted string for s (s has no control characters: the caller checked)."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, dict):
        return "{ " + ", ".join("%s = %s" % (k, lua_value(x)) for k, x in v.items()) + " }"
    return lua_quote(v)


def import_value_ok(v):
    if isinstance(v, bool):
        return False
    if isinstance(v, int):
        return 0 <= v <= 999
    return isinstance(v, str) and bool(IMPORT_WORD.fullmatch(v))


def import_bind(keys, name, args, flags, line, raw):
    """(bind dict, None) or (None, reason): a key string, an allowed action name with its (already literal) arguments, a list of flag names."""
    parts = [p.strip() for p in keys.split("+")]
    if not keys.strip() or any(p == "" for p in parts):
        return None, "the key combination %s is not written like SUPER + SHIFT + T" % lua_quote(keys)
    mods, key = [], parts[-1]
    for m in parts[:-1]:
        if m.upper() not in IMPORT_MODS:
            return None, "%s is not a modifier (use SUPER, CTRL, ALT or SHIFT)" % m
        n = IMPORT_MODS[m.upper()]
        if n not in mods:
            mods.append(n)
    if not IMPORT_KEY.fullmatch(key):
        return None, "%s is not a key name" % lua_quote(key)
    if not mods and not NO_MOD_OK.fullmatch(key):
        return None, "the keybind needs at least one modifier (SUPER, CTRL, ALT or SHIFT)"
    shape, tkeys = IMPORT_ACTIONS[name]
    run = ""
    if shape == "text":
        run = args[0].strip()
        if run == "":
            return None, "the command is empty"
        if len(run) > IMPORT_MAX_COMMAND:
            return None, "the command is longer than %d characters" % IMPORT_MAX_COMMAND
        if any(ord(c) < 32 or ord(c) == 127 for c in run):
            return None, "the command has a line break or another control character in it"
        argtext = lua_quote(run)
        args = [run]
    elif shape == "none":
        argtext = ""
    elif shape == "word":
        if not import_value_ok(args[0]) or not isinstance(args[0], str):
            return None, "the value %s is not allowed here" % lua_quote(str(args[0]))
        argtext = lua_quote(args[0])
    else:
        t = args[0]
        if not t or any(k not in tkeys or not import_value_ok(v) for k, v in t.items()):
            return None, "the options of this action are not ones an import may write"
        argtext = lua_value(t)
    try:
        action = describe_action(Action(name, args))
    except Unresolved:
        action = name
    combo = " + ".join(mods + [key])
    opts = [f for f in IMPORT_FLAGS if f in flags]
    lua = "hl.bind(%s, hl.dsp.%s(%s)%s)" % (lua_quote(combo), name, argtext, (", { " + ", ".join(f + " = true" for f in opts) + " }") if opts else "")
    return {"line": line, "raw": raw, "combo": combo, "mods": mods, "key": key, "action": action, "run": run, "flags": opts, "lua": lua}, None


def clip(s, n=160):
    s = re.sub(r"\s+", " ", s).strip()
    return s if len(s) <= n else s[:n - 1] + "…"


def literal_of(node):
    """The plain value of a literal node (string, number, boolean, or a table of named literals), else raise Unresolved."""
    if node[0] == "lit" and node[1] is not None:
        return node[1]
    if node[0] == "table":
        out = {}
        for k, v in node[1]:
            if k[0] != "lit" or not isinstance(k[1], str):
                raise Unresolved("table key")
            out[k[1]] = literal_of(v)
        return out
    raise Unresolved("not a plain value")


def make_resolver(variables):
    """A function that fills @name@ in a command from `variables` (None: the text is left as it is); returns (text, error)."""
    def resolve(text):
        if variables is None:
            return text, None
        missing = []

        def sub(m):
            if m.group(1) in variables:
                return variables[m.group(1)]
            missing.append(m.group(1))
            return m.group(0)
        out = re.sub(r"@(%s)@" % "|".join(DEFAULT_VARS), sub, text)
        return out, (("%s is not set in your programs.lua" % missing[0]) if missing else None)
    return resolve


def parse_lua_binds(text, resolve):
    """Strictly: comments, blank lines and hl.bind(...) statements; everything else is an error."""
    clean = blank_comments(text)
    lines = text.split("\n")
    nl = [m.start() for m in re.finditer("\n", text)]
    line_of = lambda pos: bisect.bisect_left(nl, pos) + 1
    binds, errors = [], []

    def err(pos, reason):
        n = line_of(pos)
        errors.append({"line": n, "raw": clip(lines[n - 1] if n <= len(lines) else ""), "reason": reason})

    def skip_line(pos):
        k = clean.find("\n", pos)
        return len(clean) if k < 0 else k + 1

    i, n = 0, len(clean)
    while i < n:
        c = clean[i]
        if c in " \t\r\n;":
            i += 1
            continue
        start = i
        if not re.compile(r"hl\s*\.\s*bind\s*\(").match(clean, i):
            err(i, "this is not a keybind, so it is not imported (only hl.bind lines are)")
            i = skip_line(i)
            continue
        p = Parser(clean, i)
        try:
            node = p.expr()
        except ParseError:
            err(start, "the keybind could not be read: it is not a complete hl.bind(...) call")
            i = skip_line(start)
            continue
        stop = p.pos  # the parser has skipped the blanks after the call: the call ends before them
        while stop > start and clean[stop - 1] in " \t\r\n":
            stop -= 1
        end_line = clean.find("\n", stop)
        tail = clean[stop:(len(clean) if end_line < 0 else end_line)].strip().rstrip(";").strip()
        if tail:
            err(start, "something follows the keybind on the same line, so the line is not imported")
            i = skip_line(stop)
            continue
        i = stop
        if node[0] != "call" or dotted(node[1]) != "hl.bind":
            err(start, "this is not a plain hl.bind(...) call")
            continue
        args = node[2]
        if len(args) not in (2, 3):
            err(start, "hl.bind needs the keys, the action and optionally the options")
            continue
        if args[0][0] != "lit" or not isinstance(args[0][1], str):
            err(start, "the key combination must be written out in quotes (no variables or code)")
            continue
        act = args[1]
        if act[0] != "call" or not (dotted(act[1]) or "").startswith("hl.dsp."):
            err(start, "the action must be an hl.dsp call such as hl.dsp.exec_cmd(\"...\"); functions and other code are not imported")
            continue
        name = dotted(act[1])[7:]
        if name not in IMPORT_ACTIONS:
            err(start, "this keybind does something an import cannot add (hl.dsp.%s). Imports take command keybinds and a few window and workspace actions" % name)
            continue
        shape = IMPORT_ACTIONS[name][0]
        try:
            vals = [literal_of(a) for a in act[2]]
        except Unresolved:
            err(start, "the action's arguments must be plain values in quotes (no variables or code)")
            continue
        okshape = {"none": len(vals) == 0, "text": len(vals) == 1 and isinstance(vals[0], str), "word": len(vals) == 1 and isinstance(vals[0], str),
                   "table": len(vals) == 1 and isinstance(vals[0], dict)}[shape]
        if not okshape:
            err(start, "the action has arguments of a kind an import does not accept")
            continue
        if shape == "text":
            vals[0], why = resolve(vals[0])
            if why:
                err(start, why)
                continue
        flags, bad = [], None
        if len(args) == 3:
            o = args[2]
            if o[0] != "table":
                bad = "the options must be a table such as { locked = true }"
            else:
                for k, v in o[1]:
                    if k[0] != "lit" or not isinstance(k[1], str) or v[0] != "lit" or not isinstance(v[1], bool):
                        bad = "the options may only be names set to true or false"
                    elif k[1] not in IMPORT_FLAGS:
                        bad = "the option %s is not supported for imported keybinds (supported: %s)" % (k[1], ", ".join(IMPORT_FLAGS))
                    elif v[1]:
                        flags.append(k[1])
        if bad:
            err(start, bad)
            continue
        b, why = import_bind(args[0][1], name, vals, flags, line_of(start), clip(text[start:stop]))
        if why:
            err(start, why)
        else:
            binds.append(b)
    return binds, errors, 0


DIR_WORDS = {"l": "left", "r": "right", "u": "up", "d": "down", "left": "left", "right": "right", "up": "up", "down": "down"}


def conf_import_action(disp, arg, mouse):
    """(action name, arguments) of a .conf dispatcher an import can write, or None."""
    num = lambda s: int(s) if re.fullmatch(r"\d{1,3}", s) else s
    if disp in ("exec", "execr"):
        return "exec_cmd", [arg]
    if disp == "killactive":
        return "window.close", []
    if disp == "togglefloating":
        return "window.float", [{"action": "toggle"}]
    if disp == "pseudo":
        return "window.pseudo", []
    if disp == "movefocus" and arg in DIR_WORDS:
        return "focus", [{"direction": DIR_WORDS[arg]}]
    if disp == "workspace" and arg:
        return "focus", [{"workspace": num(arg)}]
    if disp in ("movetoworkspace", "movetoworkspacesilent") and arg:
        return "window.move", [{"workspace": num(arg)}]
    if disp == "movewindow" and mouse:
        return "window.drag", []
    if disp == "movewindow" and arg in DIR_WORDS:
        return "window.move", [{"direction": DIR_WORDS[arg]}]
    if disp == "resizewindow":
        return "window.resize", []
    if disp == "togglespecialworkspace" and arg:
        return "workspace.toggle_special", [arg]
    if disp == "layoutmsg" and arg:
        return "layout", [arg]
    return None


def parse_conf_binds(text, resolve):
    binds, errors, ignored = [], [], 0
    variables = {}
    for no, orig in enumerate(text.split("\n"), 1):
        line = strip_conf_comment(orig).strip()
        if not line or "=" not in line:
            if line:
                ignored += 1
            continue
        k, _, v = line.partition("=")
        k, v = k.strip(), v.strip()
        if k.startswith("$"):
            variables[k[1:]] = v
            continue
        if not re.fullmatch(r"bind[a-z]*", k):
            ignored += 1
            continue
        for name in sorted(variables, key=len, reverse=True):
            v = v.replace("$" + name, variables[name])
        raw = clip(orig)
        letters = k[4:]
        if any(ch not in CONF_FLAGS and ch != "d" for ch in letters):
            errors.append({"line": no, "raw": raw, "reason": "unknown option letters in %s" % k})
            continue
        size = 5 if "d" in letters else 4
        fields = [x.strip() for x in v.split(",", size - 1)]
        if len(fields) < size - 1:
            errors.append({"line": no, "raw": raw, "reason": "the bind line has too few fields (MODS, KEY, dispatcher, argument)"})
            continue
        fields += [""] * (size - len(fields))  # a dispatcher without an argument
        disp, arg = fields[size - 2], fields[size - 1]
        flags, bad = [], None
        for ch in letters:
            if ch == "d":
                continue
            f = CONF_FLAGS[ch]
            if f in IMPORT_FLAGS:
                flags.append(f)
            else:
                bad = "the bind option %s (%s) cannot be imported" % (ch, f)
        if bad:
            errors.append({"line": no, "raw": raw, "reason": bad})
            continue
        got = conf_import_action(disp, arg, "mouse" in flags)
        if got is None:
            errors.append({"line": no, "raw": raw, "reason": "this keybind does something an import cannot add (%s). Imports take command keybinds and a few window and workspace actions" % disp})
            continue
        name, vals = got
        if name == "exec_cmd":
            vals[0], why = resolve(vals[0])
            if why:
                errors.append({"line": no, "raw": raw, "reason": why})
                continue
        mods = [x for x in re.split(r"[\s_+]+", fields[0]) if x]
        b, why = import_bind(" + ".join(mods + [fields[1]]), name, vals, flags, no, raw)
        if why:
            errors.append({"line": no, "raw": raw, "reason": why})
        else:
            binds.append(b)
    return binds, errors, ignored


def parse_binds(file_arg, resolve_root=None):
    out = {"format": None, "file": str(file_arg), "binds": [], "errors": [], "ignored": 0}
    variables = None
    if resolve_root:
        # the Hyprland example's variables, from the user's programs.lua (the same table the Apps tab reads)
        vals = programs(resolve_root)["values"]
        variables = {"terminal": vals.get("terminal", ""), "menu": vals.get("launcher") or vals.get("menu", ""),
                     "fileManager": vals.get("fileManager") or vals.get("filemanager") or "xdg-open ~"}
        variables = {k: v for k, v in variables.items() if v}
        out["variables"] = variables
    path = Path(file_arg).expanduser()
    try:
        if not path.is_file():
            out["error"] = "That is not a file."
            return out
        if path.stat().st_size > IMPORT_MAX_BYTES:
            out["error"] = "That file is too big to be a keybinds file (over %d KB)." % (IMPORT_MAX_BYTES // 1024)
            return out
        data = path.read_bytes()
    except OSError as e:
        out["error"] = "The file could not be read: %s." % (e.strerror or "unknown error")
        return out
    if b"\0" in data:
        out["error"] = "That does not look like a text file."
        return out
    text = data.decode("utf-8", errors="replace")
    fmt = "conf" if path.suffix.lower() == ".conf" else "lua"
    out["format"] = fmt
    out["binds"], out["errors"], out["ignored"] = (parse_conf_binds if fmt == "conf" else parse_lua_binds)(text, make_resolver(variables))
    return out



def main():
    ap = argparse.ArgumentParser(description="Find what a Hyprland config loads and binds.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    dp = sub.add_parser("discover", help="print the config's files, binds, workspace rules and monitors as JSON")
    dp.add_argument("--root", help="config folder or main file (default ~/.config/hypr)")
    ap2 = sub.add_parser("add-require", help="add the line that makes the config load FILE (a backup of the main file is kept)")
    ap2.add_argument("file", help="the file the config should load")
    ap2.add_argument("--root", help="config folder or main file (default ~/.config/hypr)")
    pp = sub.add_parser("programs", help="print the program names modules/programs.lua returns as JSON")
    pp.add_argument("--root", help="config folder or main file (default ~/.config/hypr)")
    sp = sub.add_parser("set-programs", help="set terminal, browser, editor or fileManager in modules/programs.lua (existing entries only; a backup is kept)")
    sp.add_argument("pairs", nargs="*", metavar="KEY=VALUE")
    sp.add_argument("--root", help="config folder or main file (default ~/.config/hypr)")
    sp.add_argument("--dry-run", action="store_true", help="only report the lines that would change")
    bp = sub.add_parser("parse-binds", help="print the importable keybinds of an export or .conf file as JSON (read-only)")
    bp.add_argument("file", help="the file to read")
    bp.add_argument("--resolve", metavar="ROOT", help="fill @terminal@, @fileManager@ and @menu@ in commands from the programs.lua under ROOT (the Hyprland defaults file)")
    args = ap.parse_args()
    if args.cmd == "parse-binds":
        result = parse_binds(args.file, args.resolve)
        json.dump(result, sys.stdout, indent=2, ensure_ascii=False)
        sys.stdout.write("\n")
        return 1 if "error" in result else 0
    if args.cmd == "add-require":
        result = add_require(args.file, args.root)
        json.dump(result, sys.stdout, indent=2, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0 if result["ok"] else 1
    if args.cmd == "set-programs":
        pairs = [tuple(x.split("=", 1)) if "=" in x else (x, "") for x in args.pairs]
        result = set_programs(pairs, args.root, args.dry_run)
        json.dump(result, sys.stdout, indent=2, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0 if result["ok"] else 1
    if args.cmd == "programs":
        json.dump(programs(args.root), sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0
    result = discover(args.root)
    json.dump(result, sys.stdout, indent=2, ensure_ascii=False, default=str)
    sys.stdout.write("\n")
    return 1 if "error" in result else 0


if __name__ == "__main__":
    sys.exit(main())
