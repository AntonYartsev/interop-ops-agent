#!/usr/bin/env python3
"""Generate the specimen pair cases C18-C20 into cases/pair/ (HL7 files, expected.json, MANIFEST). SYNTHETIC, seed 20261105.
Each pair differs in one fact only: the specimen in the OBX-3.2 text. Code, unit and values are the same kind.
  C01 (main set) SOD "Sodium, serum/plasma"   -> patch_mapping SOD -> 2951-2 (Sodium [Moles/volume] in Serum or Plasma)
  C18            SOD "Sodium, whole blood"    -> escalate: whole-blood sodium is LOINC 2947-0, which is not in the lookup
  C19            KX  "Potassium, whole blood" -> escalate: whole-blood potassium is LOINC 6298-4, not in the lookup
  C20            KX  "Potassium, serum/plasma"-> patch_mapping KX -> 2823-3 (Potassium [Moles/volume] in Serum or Plasma)
Unit and value distribution cannot tell the two specimens apart, so a mapping chosen by statistics alone is wrong for C18 and C19.
The expected answers and the baseline result (cases/pair/BASELINE.txt) are committed before any LIVE run on these cases.
Run: python3 scripts/gen_pair_cases.py   then   CASES_SRC=cases/pair EXPECTED_MAP_FILE=cases/pair/expected.json ./scripts/demo.sh --live"""
import hashlib, json, os, random

import gen_blind_cases as g

OUT = os.path.join(g.ROOT, "cases", "pair")
g.rnd = random.Random(20261105)


def renamed(cid, mrn, code, new_code, text):
    """BMP batch where `code` is sent as `new_code` with the OBX-3.2 text `text`; unit, range and values as for `code`."""
    row = next(r for r in g.BMP if r[0] == code)
    return g.build(cid, mrn, g.BMP_P, g.BMP,
                   lambda n: {code: lambda lo, hi, nd: (new_code, text, g.val(lo, hi, nd, code), row[4], f"{lo}-{hi}", "N")})


CASES = {
    "C18": ("sodium-whole-blood", renamed("C18", 104000, "NA", "SOD", "Sodium, whole blood"),
            {"action": "escalate", "target": None,
             "why": "whole-blood sodium (LOINC 2947-0) is not serum/plasma sodium (2951-2); the lookup has no whole-blood code"}),
    "C19": ("potassium-whole-blood", renamed("C19", 104100, "K", "KX", "Potassium, whole blood"),
            {"action": "escalate", "target": None,
             "why": "whole-blood potassium (LOINC 6298-4) is not serum/plasma potassium (2823-3); the lookup has no whole-blood code"}),
    "C20": ("potassium-serum", renamed("C20", 104200, "K", "KX", "Potassium, serum/plasma"),
            {"action": "patch_mapping", "target": {"code": "KX", "loinc": "2823-3"},
             "why": "serum/plasma potassium, same unit and values as K, K absent from the panel"}),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    exp = {"synthetic": True, "blind": True,
           "note": "SYNTHETIC specimen pair cases from scripts/gen_pair_cases.py (seed 20261105). Expected answers and the baseline result "
                   "were committed before the first LIVE run; no cassettes. Pair: C01 (main set) with C18, C19 with C20.",
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
