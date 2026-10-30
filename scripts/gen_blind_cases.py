#!/usr/bin/env python3
"""Generate blind cases C13-C17 into cases/blind/ (HL7 files, expected.json, MANIFEST). SYNTHETIC, seed 20261030.
The expected answers are written here, before any LIVE run on these cases; no cassettes exist for them.
Run: python3 scripts/gen_blind_cases.py   then   CASES_SRC=cases/blind EXPECTED_MAP_FILE=cases/blind/expected.json ./scripts/demo.sh --live"""
import hashlib, json, os, random, statistics

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "cases", "blind")
rnd = random.Random(20261030)

BMP = [("GLU", "Glucose", 3.9, 5.8, "mmol/L", 1), ("NA", "Sodium", 135, 145, "mmol/L", 1),
       ("K", "Potassium", 3.5, 5.1, "mmol/L", 2), ("CREAT", "Creatinine", 53, 106, "umol/L", 0),
       ("BUN", "Urea nitrogen", 7, 20, "mg/dL", 0)]
CBC = [("WBC", "White Blood Cells", 4.5, 11.0, "10*3/uL", 1), ("HGB", "Hemoglobin", 12.0, 17.5, "g/dL", 1),
       ("HCT", "Hematocrit", 36.0, 50.0, "%", 1), ("PLT", "Platelets", 150, 400, "10*3/uL", 0)]

def history_stats():
    """code -> (median, stdev) from data/history_200.json, so a clean code stays within the triage 15% median band"""
    vals = {}
    for m in json.load(open(os.path.join(ROOT, "data", "history_200.json")))["messages"]:
        for seg in m["raw_hl7"].split("\r"):
            f = seg.split("|")
            if f[0] == "OBX":
                vals.setdefault(f[3].split("^")[0], []).append(float(f[5]))
    return {k: (statistics.median(v), statistics.pstdev(v)) for k, v in vals.items()}

HIST = history_stats()

def val(lo, hi, nd, code=None, exact=False):
    if code in HIST:
        med, sd = HIST[code]
        v = round(med if exact else min(max(rnd.gauss(med, sd), lo), hi), nd)
    else:
        v = round(rnd.uniform(lo + (hi - lo) * 0.1, hi - (hi - lo) * 0.1), nd)
    return str(int(v)) if nd == 0 else str(v)

def msg(cid, n, ts, mrn, panel, rows):
    hh, mm = divmod(8 * 60 + 2 * (n - 1), 60)
    t = f"20261030{hh:02d}{mm:02d}00" if ts is None else ts
    segs = [f"MSH|^~\\&|LAB_LIS|REGIONAL_LAB|HOSP_EHR|MAIN_HOSP|{t}||ORU^R01^ORU_R01|{cid}-MSG{n:03d}|P|2.5.1",
            f"PID|1||MRN-{mrn:06d}^^^REGIONAL_LAB^MR||SYNTHETIC^PATIENT{mrn % 10000:04d}||19{50 + n % 40}0{1 + n % 9}1{n % 10}|{'MF'[n % 2]}",
            f"ORC|RE|ORD-{mrn - 40000}|LAB-{mrn - 10000}||||||{t}",
            f"OBR|1|ORD-{mrn - 40000}|LAB-{mrn - 10000}|{panel}|||{t}"]
    for i, (code, name, v, unit, rng, flag) in enumerate(rows, 1):
        segs.append(f"OBX|{i}|NM|{code}^{name}^L||{v}|{unit}|{rng}|{flag}|||F")
    return "\r".join(segs) + "\r", t

def normal_rows(table, swap=None, exact=False):
    """swap: code -> function(lo, hi, nd) returning (code, name, value, unit, range, flag)"""
    rows = []
    for code, name, lo, hi, unit, nd in table:
        if swap and code in swap:
            r = swap[code](lo, hi, nd)
            if r:
                rows.append(r)
            continue
        rows.append((code, name, val(lo, hi, nd, code, exact), unit, f"{lo}-{hi}", "N"))
    return rows

def build(cid, base_mrn, panel, table, swap_for, count=30, dup=None):
    out = []
    for n in range(1, count + 1):
        m, t = msg(cid, n, None, base_mrn + n, panel, normal_rows(table, swap_for(n), exact=bool(dup and n == dup[0])))  # flooded copy at the history median: 41 copies must not shift the batch median
        out.append(m)
        if dup and n == dup[0]:
            out.extend([m] * (dup[1] - 1))  # flood: the same message (same MSH-10 and MSH-7) resent
    return out

CBC_P, BMP_P = "CBC^Complete Blood Count^L", "BMP^Basic Metabolic Panel^L"
CASES = {
    # PLT renamed to PLAT, same unit and values: map to the missing panel counterpart PLT (777-3)
    "C13": ("new-code-plat", build("C13", 103000, CBC_P, CBC,
            lambda n: {"PLT": lambda lo, hi, nd: ("PLAT", "Platelet count", val(lo, hi, nd, "PLT"), "10*3/uL", "150-400", "N")}),
            {"action": "patch_mapping", "target": {"code": "PLAT", "loinc": "777-3"}}),
    # HGB sent in g/L (x10) instead of g/dL: UCUM g/L -> g/dL factor 0.1
    "C14": ("hgb-gl", build("C14", 103100, CBC_P, CBC,
            lambda n: {"HGB": lambda lo, hi, nd: ("HGB", "Hemoglobin", str(int(round(float(val(lo, hi, nd, "HGB")) * 10))), "g/L", "120-175", "N")}),
            {"action": "convert_unit", "target": {"code": "HGB", "from_unit": "g/L", "to_unit": "g/dL", "multiplier": 0.1}}),
    # brand-new test LAC added, every existing panel code still present, LAC not in the lookup: no safe mapping
    "C15": ("new-code-lac", build("C15", 103200, BMP_P, BMP + [("LAC", "Lactate", 0.5, 2.2, "mmol/L", 1)],
            lambda n: {"LAC": lambda lo, hi, nd: ("LAC", "Lactate", val(lo, hi, nd), "mmol/L", "0.5-2.2", "N")}),
            {"action": "escalate", "target": None}),
    # 2 of 30 patients with critical glucose (HH); median unchanged: a clinical value, not feed drift
    "C16": ("critical-glu", build("C16", 103300, BMP_P, BMP,
            lambda n: {"GLU": lambda lo, hi, nd: ("GLU", "Glucose", "27.4" if n == 9 else "31.2", "mmol/L", "3.9-5.8", "HH")} if n in (9, 22) else None),
            {"action": "pass", "target": None}),
    # message 17 resent 40 times (70 messages in the batch): quarantine that MSH-10
    "C17": ("duplicate-flood-bmp", build("C17", 103400, BMP_P, BMP, lambda n: None, dup=(17, 41)),
            {"action": "quarantine", "target": {"msh10": "C17-MSG017"}}),
}

def main():
    os.makedirs(OUT, exist_ok=True)
    exp = {"synthetic": True, "blind": True,
           "note": "SYNTHETIC blind cases from scripts/gen_blind_cases.py (seed 20261030). Expected answers fixed before the first LIVE run; no cassettes.",
           "criteria": "same as cases/expected.json", "cases": {}}
    manifest = ["# sha256  file  messages"]
    for cid, (label, msgs, want) in CASES.items():
        name = f"{cid}-{label}.hl7"
        path = os.path.join(OUT, name)
        with open(path, "w", newline="") as fh:
            fh.write("".join(msgs))
        exp["cases"][cid] = {**want, "file": name}
        manifest.append(f"{hashlib.sha256(open(path, 'rb').read()).hexdigest()}  {name}  {len(msgs)}")
    with open(os.path.join(OUT, "expected.json"), "w") as fh:
        json.dump(exp, fh, indent=2)
        fh.write("\n")
    manifest.append(f"{hashlib.sha256(open(os.path.join(OUT, 'expected.json'), 'rb').read()).hexdigest()}  expected.json")
    with open(os.path.join(OUT, "MANIFEST"), "w") as fh:
        fh.write("\n".join(manifest) + "\n")
    print("\n".join(manifest))

if __name__ == "__main__":
    main()
