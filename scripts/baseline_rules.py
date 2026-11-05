"""Offline deterministic baseline for IOA cases (no IRIS, no LLM).

FROZEN DEFINITION (written before the first run of this script):
  Inputs: the case batch, data/labcodemap.csv, data/history_200.json, data/baseline_dtl.json.
  Same facts the agent gets through its tools. No case ids, no gold, no cassettes.
  1. Existing rules of Rules.Engine: A1 identical duplicate MSH-10 -> quarantine;
     with exactly one anomaly: A2a OBX-3.4 LOINC in lookup, A2b exact name, A2c UCUM unit pair.
  2. New rule B1: exactly one anomaly, an unmapped code -> candidate lookup targets that pass the
     Gate.Reference map_code checks (target code absent in batch, every unit = expected unit,
     batch median within 15 % of the target history median). Exactly one candidate -> patch_mapping.
  3. New rule B2: anything else -> propose pass.
  Then the same gate logic as Gate.Replay/Reference: a patch or pass with any unresolved reason
  (except a case-only unit spelling variant for pass) becomes escalate.
This is a Python re-implementation of the ObjectScript checks, not the production code.
Rule logic frozen on 2026-11-05 before the run on cases/pair. It was written after the 17 main and blind cases and the
agent results were known, so on C01-C17 it is a post-hoc baseline.
Run: python3 scripts/baseline_rules.py [gold.json:folder ...]   (default: the main and the blind set)
"""
import csv, json, re, statistics, sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOL = 0.15


def lookup():
    out = {}
    for r in csv.DictReader(l for l in open(ROOT / "data/labcodemap.csv") if not l.startswith("#")):
        out[r["local_code"]] = r
    return out


def split_msgs(text):
    segs = [s for s in re.split(r"[\r\n]+", text) if s]
    msgs, cur = [], []
    for s in segs:
        if s.startswith("MSH|") and cur:
            msgs.append(cur); cur = []
        cur.append(s)
    if cur: msgs.append(cur)
    return msgs


def summary(msgs):
    codes = defaultdict(lambda: {"units": Counter(), "vals": [], "desc": "", "alt": Counter()})
    msh10, raw, pid3, pid2, segs = Counter(), defaultdict(set), 0, 0, set()
    for m in msgs:
        f = m[0].split("|"); msh10[f[9]] += 1; raw[f[9]].add("\r".join(m))
        for s in m:
            p = s.split("|"); segs.add(p[0])
            if p[0] == "PID":
                pid3 += bool(p[3].strip()) if len(p) > 3 else 0
                pid2 += bool(re.match(r"^MRN-\d{6}", p[2])) if len(p) > 2 else 0
            if p[0] == "OBX":
                c = p[3].split("^"); code = c[0].upper(); st = codes[code]
                st["desc"] = c[1] if len(c) > 1 else ""
                if len(c) > 3 and c[3]: st["alt"][c[3]] += 1
                st["units"][p[6]] += 1
                try: st["vals"].append(float(p[5]))
                except ValueError: pass
    for st in codes.values():
        st["median"] = statistics.median(st["vals"]) if st["vals"] else 0
    return {"codes": codes, "msh10": msh10, "raw": raw, "pid3": pid3, "pid2": pid2, "n": len(msgs), "segs": segs}


LK = lookup()
HIST = summary([split_msgs(m["raw_hl7"])[0] for m in json.load(open(ROOT / "data/history_200.json"))["messages"]])
DTL = json.load(open(ROOT / "data/baseline_dtl.json"))
KNOWN = set(DTL["known_segments"])


def hmed(code):
    return HIST["codes"][code]["median"] if code in HIST["codes"] else 0


def ucum(code, frm, to):
    cc = LK[code]["canonical_code"]
    for e in DTL["ucum_conversions"]:
        if e["canonical_code"] in (cc, "*") and e["from_unit"] == frm and e["to_unit"] == to:
            return e["factor"]
    return 0


def anomalies(S):
    a = []
    if S["pid3"] < S["n"]: a.append({"cat": "empty_required_field", "pid2": S["pid2"]})
    for code, st in S["codes"].items():
        if code not in LK:
            a.append({"cat": "unmapped_code", "code": code}); continue
        exp = LK[code]["expected_unit"]; other = [u for u in st["units"] if u != exp]
        hm = hmed(code); shift = hm > 0 and abs(st["median"] - hm) / hm > TOL
        if other or shift:
            a.append({"cat": "unit_or_value_shift", "code": code, "unit_changed": bool(other),
                      "drift_unit": other[0] if other else "", "expected_unit": exp,
                      "ucum_factor": ucum(code, other[0], exp) if len(other) == 1 else 0})
    return a


def reference(S, mapped=None, converted=None):
    """Gate.Reference reasons for the batch after an optional mapping {from: to_local} or conversion {code: (from_unit, factor)}."""
    mapped, converted, r = mapped or {}, converted or {}, []
    if S["pid3"] < S["n"]: r.append("unresolved_required_field:PID-3")
    for z in S["segs"] - KNOWN: r.append("unresolved_segment:" + z)
    for code, st in S["codes"].items():
        if code not in LK:
            if code not in mapped: r.append("unresolved_unmapped_code:" + code)
            continue
        exp = LK[code]["expected_unit"]
        if code in converted:
            frm, fac = converted[code]
            if [u for u in st["units"] if u not in (exp, frm)]: r.append("unresolved_unit_mismatch:" + code)
            continue
        other = [u for u in st["units"] if u != exp]
        if other:
            r.append(("unit_spelling_variant:" if all(u.lower() == exp.lower() for u in other) else "unresolved_unit_mismatch:") + code)
        hm = hmed(code)
        if hm > 0 and abs(st["median"] - hm) / hm > TOL: r.append("unresolved_distribution_shift:" + code)
    return r


def map_ok(S, frm, to):
    st = S["codes"][frm]
    if to in S["codes"]: return False
    if any(u != LK[to]["expected_unit"] for u in st["units"]): return False
    hm = hmed(to)
    return not (hm > 0 and abs(st["median"] - hm) / hm > TOL)


def decide(S):
    for k, c in S["msh10"].items():
        if c > 1 and len(S["raw"][k]) == 1 and k not in HIST["msh10"]:
            return {"action": "quarantine", "msh10": k, "rule": "A1"}
    a = anomalies(S)
    if len(a) == 1 and a[0]["cat"] == "unmapped_code":
        code = a[0]["code"]; st = S["codes"][code]
        for alt in st["alt"]:
            for loc, m in LK.items():
                if m["canonical_code"] == alt: return {"action": "patch_mapping", "code": code, "to": loc, "rule": "A2a"}
        d = st["desc"].strip().lower()
        for loc, m in LK.items():
            if d and d in (m["short_name"].lower(), m["canonical_name"].lower()):
                return {"action": "patch_mapping", "code": code, "to": loc, "rule": "A2b"}
        cands = [loc for loc in LK if map_ok(S, code, loc)]
        if len(cands) == 1: return {"action": "patch_mapping", "code": code, "to": cands[0], "rule": "B1", "cands": cands}
        return {"action": "pass", "rule": "B2", "cands": cands}
    if len(a) == 1 and a[0]["cat"] == "unit_or_value_shift" and a[0]["unit_changed"] and a[0]["ucum_factor"] > 0:
        return {"action": "convert_unit", "code": a[0]["code"], "from": a[0]["drift_unit"], "factor": a[0]["ucum_factor"], "rule": "A2c"}
    return {"action": "pass", "rule": "B2"}


def gate(S, d):
    if d["action"] == "pass":
        r = [x for x in reference(S) if not x.startswith("unit_spelling_variant:")]
    elif d["action"] == "patch_mapping":
        r = ([] if map_ok(S, d["code"], d["to"]) else ["map_checks"]) + reference(S, mapped={d["code"]: d["to"]})
    elif d["action"] == "convert_unit":
        st = S["codes"][d["code"]]; hm = hmed(d["code"])
        r = ([] if not hm or abs(st["median"] * d["factor"] - hm) / hm <= TOL else ["distribution_after_convert"]) \
            + reference(S, converted={d["code"]: (d["from"], d["factor"])})
    else:
        r = reference(S)
    return ("escalate" if r else d["action"]), r


def correct(final, d, S, g):
    if final != g["action"]: return False
    t = g.get("target") or {}
    if final == "patch_mapping": return d["code"] == t["code"] and LK[d["to"]]["canonical_code"] == t["loinc"]
    if final == "convert_unit": return d["code"] == t["code"] and abs(d["factor"] - t["multiplier"]) / t["multiplier"] <= 0.0025
    if final == "quarantine": return d["msh10"] == t["msh10"]
    if "evidence_must_contain" in g:  # C10: triage evidence names the sibling field with valid MRN format and the share
        return S["pid3"] == 0 and S["pid2"] == S["n"]
    return True


SETS = [a.split(":") for a in sys.argv[1:]] or [("cases/expected.json", "cases"), ("cases/blind/expected.json", "cases/blind")]
for gold_file, folder in SETS:
    gold = json.load(open(ROOT / gold_file))["cases"]; ok = 0
    for cid, g in gold.items():
        S = summary(split_msgs(open(ROOT / folder / g["file"]).read()))
        d = decide(S); final, reasons = gate(S, d); c = correct(final, d, S, g); ok += c
        print(f"{cid} rule={d['rule']:3} proposed={d['action']:13} final={final:13} gold={g['action']:13} {'OK' if c else 'WRONG'} "
              f"{d.get('code','')}{'->'+LK[d['to']]['canonical_code'] if 'to' in d else ''} cands={d.get('cands','')} reasons={reasons[:3]}")
    print(f"== {folder}: {ok}/{len(gold)}\n")
