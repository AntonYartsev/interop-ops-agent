"""Build results JSON + per-case summary from main-run{1,2,3}.json. Usage: analyze.py <scratch> <repo>"""
import json, os, re, sys

S, R = sys.argv[1], sys.argv[2]
exp = json.load(open(os.path.join(R, "cases/specimen-blind/expected.json")))["cases"]
OLD = {"C%02d" % (n + 20): "S%02d" % n for n in range(1, 13)}
# Ex-ante predictions, PREREGISTRATION.md section 5: (agent escalate?, warning fired?)
PRED = {"C21": (0, 1), "C22": (0, 0), "C23": (0, 0), "C24": (0, 0), "C25": (0, 0), "C26": (0, 0),
        "C27": (1, 1), "C28": (0, 0), "C29": (0, 0), "C30": (0, 0), "C31": (0, 0), "C32": (1, 0)}


def warn(card):
    return any(l.lstrip().startswith("! WARNING specimen") for l in (card or "").splitlines())


def tgt(s):
    m = re.match(r"^\s*([A-Za-z0-9_]+)\s*->\s*([0-9]+-[0-9])\s*$", s or "")
    return {"code": m.group(1), "loinc": m.group(2)} if m else None


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

json.dump({"runs": runs}, open(os.path.join(S, "results.json"), "w"), indent=1, ensure_ascii=False)

# summary
for cid in sorted(exp):
    rr = [r for r in runs if r["case"] == cid]
    print(cid, OLD[cid], exp[cid]["action"], [(r.get("error") or (r["source"], r["action"], r["target"], r["gateResult"], r["warningFired"], r["agentCorrect"], r["llmCalls"])) for r in rr])
