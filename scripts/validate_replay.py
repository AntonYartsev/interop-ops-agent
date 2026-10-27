#!/usr/bin/env python3
"""Validate REPLAY cassettes (schema ioa-replay/1) and scan them for secrets.

Usage: python3 scripts/validate_replay.py [--require] [--keys-only] [DIR_OR_FILE ...]   (default: replay/)
  --keys-only  skip the schema and scan any file only for sk- keys and key env values (used by --staged for
               non-cassette files, where the words Bearer/Authorization may legitimately appear in code or docs)
  --staged     check the git index in memory (no temp files): staged replay/*.json get schema + full scan,
               every other staged file gets the --keys-only scan; a staged .env is a failure (its content is not read)
Schema: case_id (Cnn), match{msh10, prompt_sha256 (64 hex)}, recorded{profile, model, build, at}, turns (list),
usage (object), expected (object); optional "schema" must be "ioa-replay/1".
Secret scan: OpenAI-style "sk-..." keys, "Bearer", an Authorization header, and the values of key-like environment
variables (*_API_KEY, *TOKEN*, *SECRET*, *PASSWORD*; names also taken from .env.example, never from .env).
Matched values are never printed, only file + kind of finding.
Exit: 0 all valid (or no cassettes, unless --require), 1 a finding or schema error, 2 bad arguments."""
import glob, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA = "ioa-replay/1"
KEYLIKE = re.compile(r"(_API_KEY$|^API_KEY$|TOKEN|SECRET|PASSWORD)", re.I)
PATTERNS = [
    ("openai-style key (sk-...)", re.compile(r"\bsk-[A-Za-z0-9_\-]{8,}")),
    ("Bearer token", re.compile(r"\bBearer\b", re.I)),
    ("Authorization header", re.compile(r"[\"']?\bAuthorization\b[\"']?\s*[:=]", re.I)),
]

def secret_names():
    names = {k for k in os.environ if KEYLIKE.search(k)}
    try:  # names only; .env itself is never opened
        for line in open(os.path.join(ROOT, ".env.example")):
            k = line.split("=", 1)[0].strip()
            if k and not k.startswith("#") and KEYLIKE.search(k):
                names.add(k)
    except OSError:
        pass
    return sorted(names)

def env_values():
    # only values present in this process environment and long enough to be meaningful
    return [(k, v) for k in secret_names() for v in [os.environ.get(k, "")] if len(v) >= 8]

def scan_text(text, keys_only=False):
    out = [kind for kind, rx in (PATTERNS[:1] if keys_only else PATTERNS) if rx.search(text)]
    out += [f"value of ${k}" for k, v in env_values() if v in text]
    return out

def check_schema(path, d):
    errs = []
    if not isinstance(d, dict):
        return ["top level is not an object"]
    if "schema" in d and d["schema"] != SCHEMA:
        errs.append(f"schema is not {SCHEMA}")
    cid = d.get("case_id")
    if not isinstance(cid, str) or not re.match(r"^C\d\d$", cid):
        errs.append("case_id missing or not Cnn")
    else:
        stem = os.path.basename(path).split(".")[0]
        if re.match(r"^C\d\d$", stem) and stem != cid:
            errs.append(f"case_id {cid} does not match file name {stem}")
    m = d.get("match")
    if not isinstance(m, dict):
        errs.append("match missing or not an object")
    else:
        if not isinstance(m.get("msh10"), str) or not m.get("msh10"):
            errs.append("match.msh10 missing")
        if not isinstance(m.get("prompt_sha256"), str) or not re.match(r"^[0-9a-f]{64}$", m.get("prompt_sha256", "")):
            errs.append("match.prompt_sha256 missing or not 64 lowercase hex")
    r = d.get("recorded")
    if not isinstance(r, dict):
        errs.append("recorded missing or not an object")
    else:
        for k in ("profile", "model", "build", "at"):
            if r.get(k) in (None, ""):
                errs.append(f"recorded.{k} missing")
    if not isinstance(d.get("turns"), list):
        errs.append("turns missing or not a list")
    for k in ("usage", "expected"):
        if not isinstance(d.get(k), dict):
            errs.append(f"{k} missing or not an object")
    return errs

def collect(args):
    files = []
    for a in args or [os.path.join(ROOT, "replay")]:
        if os.path.isdir(a):
            files += sorted(glob.glob(os.path.join(a, "*.json")))
        elif os.path.isfile(a):
            files.append(a)
        elif args:
            print(f"ERROR: no such file or directory: {a}", file=sys.stderr)
            sys.exit(2)
    return files

def check_one(name, text, keys_only, path_for_schema):
    problems = [f"secret: {k}" for k in scan_text(text, keys_only)]
    if not keys_only:
        try:
            problems += check_schema(path_for_schema, json.loads(text))
        except ValueError:
            problems.append("not valid JSON")
    return problems

def staged():
    git = lambda *a: subprocess.run(["git", *a], cwd=ROOT, capture_output=True).stdout
    names = [n for n in git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z").decode().split("\0") if n]
    if not names:
        print("PRECOMMIT: nothing staged"); return 0
    bad = 0
    for n in names:
        base = os.path.basename(n)
        if (base == ".env" or base.startswith(".env.")) and base != ".env.example":
            print(f"FAIL {n}: .env files must never be committed"); bad += 1; continue
        cassette = n.startswith("replay/") and n.endswith(".json")
        text = git("show", ":" + n).decode("utf-8", errors="replace")
        problems = check_one(n, text, not cassette, n)
        bad += bool(problems)
        if problems or cassette:
            print(f"{'FAIL' if problems else 'OK  '} {n}" + (": " + "; ".join(problems) if problems else ""))
    print(f"PRECOMMIT: {'OK' if not bad else f'FAIL ({bad})'} ({len(names)} staged files scanned)")
    return 1 if bad else 0

def main(argv):
    if "--staged" in argv:
        return staged()
    require = "--require" in argv
    keys_only = "--keys-only" in argv
    files = collect([a for a in argv if not a.startswith("--")])
    if not files:
        print("VALIDATE_REPLAY: no cassettes found" + (" (required)" if require else " (nothing to validate)"))
        return 1 if require else 0
    bad = 0
    for f in files:
        name = os.path.relpath(f, ROOT) if f.startswith(ROOT) else f
        try:
            text = open(f, encoding="utf-8", errors="replace").read()
        except OSError as e:
            print(f"FAIL {name}: cannot read ({e.strerror})"); bad += 1; continue
        problems = check_one(name, text, keys_only, f)
        bad += bool(problems)
        print(f"{'FAIL' if problems else 'OK  '} {name}" + (": " + "; ".join(problems) if problems else ""))
    print(f"VALIDATE_REPLAY: {len(files) - bad}/{len(files)} OK" + ("" if not bad else f", {bad} FAIL"))
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
