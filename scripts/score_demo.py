#!/usr/bin/env python3
"""Score Decision.ReportJSON output against cases/expected.json (prereg rules: final action after gate equals truth;
patch_mapping code+LOINC equal; convert_unit code equal and multiplier within 0.25%; quarantine MSH-10 equal;
C10 escalate only with the Evidence array naming PID-2 and 30/30). Cross-checked against a frozen reference scorer by scripts/test_score.py. Reads report JSON from stdin. Never crashes on partial data.
A REPLAY row whose cassette no longer matches (prompt hash differs or a replayed tool result changed) is DRIFT, not OK:
the recorded answer was given for other evidence. Exit 0 only if every scored case is OK."""
import json, os, re, sys

WEB = os.environ.get("WEB_PORT", "52273")
NS = os.environ.get("NS", "IRISAPP")
EXP = os.environ.get("EXPECTED_MAP_FILE", "cases/expected.json")
STATUS_TO_ACTION = {"passed": "pass", "quarantined": "quarantine", "escalated": "escalate", "rejected": "escalate"}

def g(r, *keys):
    for k in keys:
        for kk in (k, k[0].upper() + k[1:], k.lower()):
            if kk in r and r[kk] not in (None, ""):
                return r[kk]
    return ""

def parse_target(t):
    """Accept JSON object string, 'CODE->LOINC', 'CODE=LOINC', 'CODE:LOINC', 'CODE LOINC', or a bare code/MSH-10."""
    if isinstance(t, dict):
        return t
    s = str(t or "").strip()
    if s.startswith("{"):
        try:
            return json.loads(s)
        except Exception:
            pass
    m = re.match(r"^\s*([A-Za-z0-9_]+)\s*(?:->|=>|=|:|\s|\u2192)\s*([0-9]+-[0-9])\s*$", s)
    if m:
        return {"code": m.group(1), "loinc": m.group(2)}
    return {"raw": s, "code": s.split("/")[0].strip() if s else ""}

def drift(r):
    """Reason text if the row replayed a cassette that does not match the current prompt or tool results, else ''."""
    gd = g(r, "gateDetail")
    cas = ((gd.get("agent") or {}).get("cassette") or {}) if isinstance(gd, dict) else {}
    if cas.get("replay") != "hit":
        return ""
    why = []
    if cas.get("prompt_match") in (0, False):
        why.append("prompt hash differs")
    if int(cas.get("tool_results_changed") or 0) > 0:
        why.append(f"{cas['tool_results_changed']} tool results changed")
    return ", ".join(why)

def judge(cid, exp, r):
    if not r:
        return "MISSING", "no decision row"
    d = drift(r)
    if d:
        return "DRIFT", "cassette out of date: " + d
    status = str(g(r, "finalStatus")).lower()
    action = str(g(r, "action")).lower()
    if status == "pending_review":
        return "PENDING", "waiting in Workflow Inbox"
    final = action if status in ("applied", "") else STATUS_TO_ACTION.get(status, action)
    if status == "rejected":
        final = "escalate"
    want = exp["action"]
    if final != want:
        return "WRONG", f"final {final or '-'} != {want}"
    tgt = exp.get("target") or {}
    got = parse_target(g(r, "target"))
    if want == "patch_mapping":
        loinc = got.get("loinc") or got.get("canonical_code") or ""
        if str(got.get("code", "")).upper() != tgt["code"].upper() or loinc != tgt["loinc"]:
            return "WRONG", f"target {got} != {tgt['code']}->{tgt['loinc']}"
    elif want == "convert_unit":
        try:
            f = float(g(r, "factor") or got.get("multiplier") or got.get("factor"))
            if not g(r, "factor") and not got.get("multiplier") and str(got.get("operation", "")).lower() == "divide":
                f = 1 / f  # prereg: effective multiplier = factor, or 1/factor if divide
        except Exception:
            return "WRONG", "no factor"
        code = str(got.get("code", "")).upper()
        if code != tgt["code"].upper():  # prereg: convert_unit code must be equal (a missing code is not correct)
            return "WRONG", f"code {code} != {tgt['code']}"
        m = tgt["multiplier"]
        if abs(f - m) / m > 0.0025:
            return "WRONG", f"factor {f} vs {m:.6g}"
    elif want == "quarantine":
        msh = got.get("msh10") or got.get("raw") or g(r, "msh10")
        if str(msh) != tgt["msh10"]:
            return "WRONG", f"msh10 {msh} != {tgt['msh10']}"
    if exp.get("evidence_regex"):
        ev = g(r, "evidence")  # prereg: only the evidence array text counts, not reason or gate output
        text = " ".join(str(e) for e in ev) if isinstance(ev, list) else (json.dumps(ev) if isinstance(ev, dict) else str(ev))
        if exp.get("evidence_must_contain", "") not in text or not re.search(exp["evidence_regex"], text, re.I):
            return "WRONG", "evidence lacks PID-2 and 30/30"
    return "OK", ""

def mode_line(rows):
    """Run mode taken from the rows' Mode values (MOCK / REPLAY / LIVE, or mixed); CONFIG_MODE (demo.sh) only as a note."""
    counts = {}
    for r in rows:
        m = str(g(r, "mode") or "?").upper()
        counts[m] = counts.get(m, 0) + 1
    if not counts:
        mode = "unknown (no rows)"
    elif len(counts) == 1:
        mode = next(iter(counts))
    else:
        mode = "mixed (" + ", ".join(f"{k} x{v}" for k, v in sorted(counts.items())) + ")"
    calls = 0
    for r in rows:
        try:
            calls += int(float(g(r, "LLMCalls") or 0))
        except (TypeError, ValueError):
            pass
    cfg = os.environ.get("CONFIG_MODE", "").strip()
    note = f"; provider kind at start: {cfg}" if cfg and cfg.upper() != mode else ""
    return f"Mode: {mode} (from Decision rows; LLM calls: {calls}{note})"

def main():
    raw = sys.stdin.read().strip()
    try:
        rows = json.loads(raw) if raw else []
    except Exception:
        print("ERROR: ReportJSON output is not valid JSON", file=sys.stderr)
        rows = []
    if isinstance(rows, dict):
        rows = rows.get("decisions") or rows.get("rows") or []
    try:
        expected = json.load(open(EXP))["cases"]
    except Exception as e:
        print(f"ERROR: cannot read {EXP}: {e}", file=sys.stderr)
        return 2
    only = [c.strip().upper() for c in os.environ.get("SCORE_CASES", "").split(",") if c.strip()]
    if only:  # demo.sh --case: score only the cases that were sent
        expected = {k: v for k, v in expected.items() if k.upper() in only}
    by = {}
    for r in rows if isinstance(rows, list) else []:
        if isinstance(r, dict):
            m = re.match(r"^(C\d\d)", str(g(r, "caseId")), re.I)
            if m:
                by[m.group(1).upper()] = r
    print(mode_line(list(by.values())))
    hdr = f"{'Case':<4} | {'Decision (action/target/factor)':<38} | {'Src':<6} | {'Final':<14} | {'Expected':<14} | {'Verdict':<7} | Visual Trace"
    print(hdr); print("-" * len(hdr))
    ok = 0; pending = []
    for cid in sorted(expected):
        e = expected[cid]; r = by.get(cid, {})
        v, why = judge(cid, e, r)
        ok += v == "OK"
        dec = "MISSING" if not r else f"{g(r,'action') or '-'}/{g(r,'target') or '-'}/{g(r,'factor') or '-'}"
        sid = g(r, "sessionId")
        link = f"http://localhost:{WEB}/csp/irisapp/EnsPortal.VisualTrace.zen?SESSIONID={sid}" if sid else "-"
        src = str(g(r, "source") or "-")
        src = "auto" if src.lower() == "human:auto" else src  # human:auto counts as human, but is shown as auto
        print(f"{cid:<4} | {dec[:38]:<38} | {src:<6} | {str(g(r,'finalStatus') or '-'):<14} | {e['action']:<14} | {v:<7} | {link}" + (f"  ({why})" if why and v != "OK" else ""))
        if v == "PENDING":
            pending.append(cid)
    print("-" * len(hdr))
    print(f"correct {ok}/{len(expected)}")
    if pending:
        print(f"pending review ({', '.join(pending)}): http://localhost:{WEB}/csp/irisapp/EnsPortal.WFWorklist.zen?$NAMESPACE={NS}")
    return 0 if expected and ok == len(expected) else 1

if __name__ == "__main__":
    sys.exit(main())
