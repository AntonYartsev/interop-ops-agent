#!/usr/bin/env python3
"""Cross-check scripts/score_demo.py against a frozen reference scorer.

Reads Agent.json and A.json (frozen run results with their reference scores) from tests/fixtures/ (sha256 in
tests/fixtures/README.md), converts every case into a row in
Decision.ReportJSON format (CaseId, MSH10 like C06-MSG031, Source, Action, Target, Factor, Reason, GateResult,
GateDetail, Evidence, FinalStatus, ...), pipes the rows through score_demo.py and asserts the reference numbers:
Agent 10/12, A 8/12. Both Target styles are checked: JSON object text and plain text ("SOD->2951-2").
Usage: python3 scripts/test_score.py [--fixtures DIR] [-v]
  default: tests/fixtures/. --fixtures DIR or env TEST_SCORE_FIXTURES: a directory with Agent.json and A.json.
Exit 0 if every check matches, 1 on mismatch, 2 if inputs are missing. Writes nothing, makes no LLM calls."""
import json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXPECT = {"Agent.json": 10, "A.json": 8}
# per-case misses of the reference scorer: same cases must miss here
REF_WRONG = {"Agent.json": {"C07", "C10"}, "A.json": {"C01", "C05", "C07", "C11"}}
PATCHES = ("patch_mapping", "convert_unit", "quarantine")
FINAL_STATUS = {"pass": "passed", "escalate": "escalated", "quarantine": "quarantined",
                "patch_mapping": "applied", "convert_unit": "applied"}

def msh(s):
    """Fixture MSH-10 C06_MSG031 -> ours C06-MSG031 (cases/expected.json rewrote the separator)."""
    return re.sub(r"\b(C\d\d)_(MSG\d+)\b", r"\1-\2", str(s))

def fix(v):
    if isinstance(v, str):
        return msh(v)
    if isinstance(v, list):
        return [fix(x) for x in v]
    if isinstance(v, dict):
        return {k: fix(x) for k, x in v.items()}
    return v

def multiplier(t):
    f = float(t.get("factor") or 0)
    if f <= 0:
        return 0.0
    return 1 / f if str(t.get("operation", "")).lower() == "divide" else f

def to_row(i, c, variant, style):
    d = fix(c.get("decision") or {})
    gate = c.get("gate") or {}
    action = d.get("action") or ""
    final = c.get("final_action") or ""
    t = d.get("target") or {}
    target, factor = "", ""
    if action == "patch_mapping":
        target = json.dumps({"code": t.get("code"), "loinc": t.get("loinc")}) if style == "json" else f"{t.get('code')}->{t.get('loinc')}"
    elif action == "convert_unit":
        factor = multiplier(t)
        target = json.dumps({k: t.get(k) for k in ("code", "from_unit", "to_unit")}) if style == "json" else str(t.get("code") or "")
    elif action == "quarantine":
        target = json.dumps({"msh10": t.get("msh10")}) if style == "json" else str(t.get("msh10") or "")
    status = FINAL_STATUS.get(final, "escalated")
    if final == "escalate" and action in PATCHES and gate.get("gate_status") != "GATE_PASSED":
        status = "rejected"  # gate turned the proposed patch into an escalation
    agent = c.get("agent") or {}
    return {"ID": i + 1, "CaseId": c["case_id"], "MSH10": msh(t.get("msh10") or ""),
            "SessionId": c.get("session_id") or "", "Mode": "REPLAY",
            "Source": "agent" if c.get("agent_used") else "rules", "Action": action, "Target": target,
            "Factor": factor, "Reason": d.get("reason") or "", "GateResult": gate.get("gate_status") or "",
            "FinalStatus": status, "Evidence": d.get("evidence") or [],
            "GateDetail": fix({"reasons": gate.get("gate_reasons") or [], "checks": gate.get("checks") or {}}),
            "TaskId": "", "LLMCalls": int(agent.get("llm_calls") or 0),
            "TokensIn": int(agent.get("prompt_tokens") or 0), "TokensOut": int(agent.get("completion_tokens") or 0),
            "CreatedAt": ""}

def score(rows):
    env = dict(os.environ, EXPECTED_MAP_FILE=os.path.join(ROOT, "cases", "expected.json"))
    p = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "score_demo.py")], input=json.dumps(rows),
                       capture_output=True, text=True, cwd=ROOT, env=env)
    m = re.search(r"correct (\d+)/(\d+)", p.stdout)
    wrong = {l[:3] for l in p.stdout.splitlines() if re.match(r"^C\d\d ", l) and "| OK " not in l}
    return (int(m.group(1)) if m else -1), wrong, p.stdout + p.stderr

def probes(run):
    """Prereg edge cases where an earlier score_demo.py was looser than the reference scorer."""
    base = {r["CaseId"]: r for r in (to_row(i, c, "", "json") for i, c in enumerate(run["cases"]))}
    out = []
    r = dict(base["C10"], Reason="PID-2 holds the MRN in 30/30 messages", GateDetail="PID-2 30/30")
    out.append(("C10 30/30 only in Reason/GateDetail -> not correct", [r], "C10", False))
    r = dict(base["C10"], Evidence=["MRN found in PID-2 in 30/30 messages"])
    out.append(("C10 PID-2 + 30/30 in Evidence -> correct", [r], "C10", True))
    r = dict(base["C03"], Target="")
    out.append(("C03 convert_unit without code -> not correct", [r], "C03", False))
    r = dict(base["C04"], Factor="", Target=json.dumps({"code": "GLU", "factor": 18.0, "operation": "divide"}))
    out.append(("C04 factor 18 divide in Target -> correct", [r], "C04", True))
    return out

def main(argv):
    src = os.environ.get("TEST_SCORE_FIXTURES") or os.path.join(ROOT, "tests", "fixtures")
    if "--fixtures" in argv:
        src = argv[argv.index("--fixtures") + 1]
    print(f"fixtures: {os.path.relpath(src, ROOT) if os.path.abspath(src).startswith(ROOT) else src}")
    verbose = "-v" in argv
    bad = 0
    for name, want in EXPECT.items():
        path = os.path.join(src, name)
        try:
            run = json.load(open(path))
        except Exception as e:
            print(f"FAIL  {name}: cannot read {path}: {e}")
            return 2
        for style in ("json", "plain"):
            rows = [to_row(i, c, run.get("variant"), style) for i, c in enumerate(run["cases"])]
            got, wrong, out = score(rows)
            ok = got == want and wrong == REF_WRONG[name]
            bad += not ok
            print(f"{'OK  ' if ok else 'FAIL'}  {name:<10} target={style:<5} score_demo {got}/12 miss {','.join(sorted(wrong)) or '-'}, reference {want}/12 miss {','.join(sorted(REF_WRONG[name]))}")
            if verbose or not ok:
                print(out)
        if name == "Agent.json":
            for label, rows, cid, want_ok in probes(run):
                _, wrong, out = score(rows)
                ok = (cid not in wrong) == want_ok
                bad += not ok
                print(f"{'OK  ' if ok else 'FAIL'}  probe: {label}")
                if not ok:
                    print(out)
            # mode header: derived from the rows' Mode values, "mixed" when they differ
            for label, mode_of, want_line in (("all REPLAY", lambda i: "REPLAY", "Mode: REPLAY "),
                                              ("all MOCK", lambda i: "MOCK", "Mode: MOCK "),
                                              ("mixed", lambda i: "MOCK" if i == 0 else "REPLAY", "Mode: mixed (MOCK x1, REPLAY x11)")):
                rows = [dict(to_row(i, c, run.get("variant"), "json"), Mode=mode_of(i)) for i, c in enumerate(run["cases"])]
                _, _, out = score(rows)
                ok = out.splitlines()[0].startswith(want_line) if out else False
                bad += not ok
                print(f"{'OK  ' if ok else 'FAIL'}  mode header: {label}")
                if not ok:
                    print(out)
    # exit code: 1 unless every case is OK; a replayed cassette that drifted is DRIFT, not OK
    exp = json.load(open(os.path.join(ROOT, "cases", "expected.json")))["cases"]
    env = dict(os.environ, EXPECTED_MAP_FILE=os.path.join(ROOT, "cases", "expected.json"), SCORE_CASES="C06")
    good = [{"CaseId": "C06", "Action": "quarantine", "Target": exp["C06"]["target"]["msh10"], "FinalStatus": "quarantined"}]
    drifted = [dict(good[0], GateDetail={"agent": {"cassette": {"replay": "hit", "prompt_match": False, "tool_results_changed": 2}}})]
    for label, rows, want_rc in (("empty input -> exit 1", [], 1), ("all OK -> exit 0", good, 0), ("cassette drift -> DRIFT, exit 1", drifted, 1)):
        p = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "score_demo.py")], input=json.dumps(rows),
                           capture_output=True, text=True, cwd=ROOT, env=dict(env, SCORE_CASES="" if not rows else "C06"))
        ok = p.returncode == want_rc and ("DRIFT" in p.stdout) == ("drift" in label)
        bad += not ok
        print(f"{'OK  ' if ok else 'FAIL'}  exit code: {label} (rc={p.returncode})")
    print("TEST_SCORE: " + ("OK" if not bad else f"FAIL ({bad})"))
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
