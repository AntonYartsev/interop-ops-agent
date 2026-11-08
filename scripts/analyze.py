"""Specimen blind set: per-run records, final results JSON, M1-M5 (PREREGISTRATION.md section 4).

Build from raw dumps (main-run{1,2,3}.json from scripts/collect.sh, main-run{1,2,3}.start = UTC start time):
    analyze.py <dir> <repo> [<out.json> [<probe.json>]]
Recompute the table and metrics from a committed results file:
    analyze.py --from results/specimen-blind-2026-11.json <repo>

Runs were made like this (3 times, collect after each, before the next reset):
    date -u +%FT%TZ > <dir>/main-runN.start
    CASES_SRC=cases/specimen-blind EXPECTED_MAP_FILE=cases/specimen-blind/expected.json ./scripts/demo.sh --live
    scripts/collect.sh > <dir>/main-runN.json
"""
import json, os, re, sys

OLD = {"C%02d" % (n + 20): "S%02d" % n for n in range(1, 13)}
# Ex-ante predictions, PREREGISTRATION.md section 5: (agent escalate?, warning fired?)
PRED = {"C21": (0, 1), "C22": (0, 0), "C23": (0, 0), "C24": (0, 0), "C25": (0, 0), "C26": (0, 0),
        "C27": (1, 1), "C28": (0, 0), "C29": (0, 0), "C30": (0, 0), "C31": (0, 0), "C32": (1, 0)}
CONTROLS = {"C29", "C30", "C31"}
DISPUTED = "C32"


def warn(card):
    return any(l.lstrip().startswith("! WARNING specimen") for l in (card or "").splitlines())


def tgt(s):
    m = re.match(r"^\s*([A-Za-z0-9_]+)\s*->\s*([0-9]+-[0-9])\s*$", s or "")
    return {"code": m.group(1), "loinc": m.group(2)} if m else None


def build_runs(S, exp):
    runs = []
    for i in (1, 2, 3):
        rows = json.load(open(os.path.join(S, "main-run%d.json" % i)))
        start = open(os.path.join(S, "main-run%d.start" % i)).read().strip()
        for cid in sorted(exp):
            rs = [r for r in rows if r["caseId"] == cid]
            first = next((r for r in rs if r["source"] in ("agent", "rules")), None)
            if not first:
                runs.append({"run": i, "case": cid, "old": OLD[cid], "error": "no agent/rules decision row", "rows": rs})
                continue
            e = exp[cid]
            t = tgt(first["target"]) if first["action"] == "patch_mapping" else None
            correct = first["action"] == e["action"] and (e["target"] is None or t == e["target"])
            m = re.search(r"history_replay=(\d+)/(\d+)", first.get("gateResult") or "")
            card = next((r.get("card") for r in rs if r.get("card")), None)
            runs.append({
                "run": i, "runStartUtc": start, "case": cid, "old": OLD[cid], "sessionId": first["sessionId"],
                "source": first["source"], "mode": first["mode"], "action": first["action"], "target": first["target"] or None,
                "gateResult": first["gateResult"], "gatePassed": (first["gateResult"] or "").startswith("GATE_PASSED"),
                "historyReplay": (m.group(1) + "/" + m.group(2)) if m else None,
                "finalStatus": [r["finalStatus"] for r in rs], "llmCalls": first["llmCalls"],
                "tokensIn": first["tokensIn"], "tokensOut": first["tokensOut"], "taskId": first["taskId"] or None,
                "card": card, "warningFired": warn(card), "agentCorrect": correct, "reason": first["reason"],
                "rows": rs,
            })
    return runs


def report(runs, exp):
    """Print the per-case table and M1-M5 (all cases, and without the disputed case)."""
    yn = lambda b: "yes" if b else "no"
    ok_runs = [r for r in runs if not r.get("error")]
    print("| Case | OBX-3 text | Group | Expected | Agent x/3 | Gate passed wrong | Warning fired | Prediction (agent / warning) | Match prediction? |")
    print("|---|---|---|---|---|---|---|---|---|")
    for cid in sorted(exp):
        rr = [r for r in ok_runs if r["case"] == cid]
        e = exp[cid]
        card = [r for r in rr if r["card"]]
        pa, pw = PRED[cid]
        ex = e["action"] + ("" if not e["target"] else " %s->%s" % (e["target"]["code"], e["target"]["loinc"]))
        print("| %s (%s) | `%s` | %s | %s | %d/3 | %d | %d/%d | %s / %s | agent %d/3, warning %d/%d |" % (
            cid, OLD[cid], e["obx3_text"], e["group"], ex, sum(r["agentCorrect"] for r in rr),
            sum(r["gatePassed"] and not r["agentCorrect"] for r in rr), sum(r["warningFired"] for r in card), len(card),
            yn(pa), yn(pw), sum((r["action"] == "escalate") == bool(pa) for r in rr),
            sum(r["warningFired"] == bool(pw) for r in card), len(card)))
    for label, sel in (("all 12 cases", ok_runs), ("without " + DISPUTED, [r for r in ok_runs if r["case"] != DISPUTED])):
        wrong = [r for r in sel if not r["agentCorrect"]]
        fired = {}
        for r in sel:
            if r["card"]:
                f = fired.setdefault(r["case"], [0, 0])
                f[0] += r["warningFired"]; f[1] += 1
        print("\n%s:" % label)
        print("M1 agent_correct: %d/%d runs" % (sum(r["agentCorrect"] for r in sel), len(sel)))
        print("M2 gate_passed_wrong: %d runs" % sum(r["gatePassed"] and not r["agentCorrect"] for r in sel))
        print("M3 warning_fired: " + ", ".join("%s %d/%d" % (c, f[0], f[1]) for c, f in sorted(fired.items()) if f[0]))
        print("M4 signal_to_human: %d/%d wrong runs" % (sum(r["action"] == "escalate" or r["warningFired"] for r in wrong), len(wrong)))
        print("M5 false_warning: %d" % sum(r["warningFired"] for r in sel if r["case"] in CONTROLS))
    print("\nerrors: %d, LLM calls: %d, tokens in %d / out %d" % (
        len(runs) - len(ok_runs), sum(r["llmCalls"] for r in ok_runs),
        sum(r["tokensIn"] for r in ok_runs), sum(r["tokensOut"] for r in ok_runs)))


if __name__ == "__main__":
    if sys.argv[1] == "--from":
        R = sys.argv[3]
        exp = json.load(open(os.path.join(R, "cases/specimen-blind/expected.json")))["cases"]
        report(json.load(open(sys.argv[2]))["runs"], exp)
        sys.exit(0)
    S, R = sys.argv[1], sys.argv[2]
    exp = json.load(open(os.path.join(R, "cases/specimen-blind/expected.json")))["cases"]
    runs = build_runs(S, exp)
    json.dump({"runs": runs}, open(os.path.join(S, "results.json"), "w"), indent=1, ensure_ascii=False)
    if len(sys.argv) > 3:
        doc = {"set": "cases/specimen-blind", "preregistrationCommit": "6f57bb69cd0e81fbad5ceb27e08c06d685c08b6e",
               "amendmentCommit": "0ab4568281bdcbce2f1fc54cb8c037f2eb61f581", "codeCommit": "0ab4568281bdcbce2f1fc54cb8c037f2eb61f581",
               "codeNote": "src/, data/, scripts/ identical to 6f57bb6 (git diff 6f57bb6 HEAD -- src data scripts is empty)",
               "date": "2026-11-08", "mode": "LIVE", "profile": "openai", "model": "gpt-5.4-mini", "autoapprove": 1,
               "command": "CASES_SRC=cases/specimen-blind EXPECTED_MAP_FILE=cases/specimen-blind/expected.json ./scripts/demo.sh --live",
               "warningRule": "card has a line that starts with '! WARNING specimen' after leading spaces are removed",
               "runs": runs}
        if len(sys.argv) > 4:
            doc["excludedProbe"] = {"note": "single C21 probe run before the main runs (session 995), not counted in metrics",
                                    "rows": json.load(open(sys.argv[4]))}
        doc["excludedAttempt"] = {"note": "attempt with S01-S12 IDs before Amendment 1: 0 decision rows, 0 LLM calls"}
        json.dump(doc, open(sys.argv[3], "w"), indent=1, ensure_ascii=False)
    report(runs, exp)
