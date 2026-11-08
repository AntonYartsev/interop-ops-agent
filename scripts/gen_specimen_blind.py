#!/usr/bin/env python3
"""Generate the specimen blind test set S01-S12 into cases/specimen-blind/ (HL7 files, expected.json, MANIFEST).
SYNTHETIC, seed 20261109.

Cases test specimen mismatch against serum/plasma LOINC lookup (2951-2 for sodium, 2823-3 for potassium).
Non-serum specimens (whole blood, point-of-care, urine, ambiguous) must escalate.
Serum/plasma controls with unusual wording must patch_mapping to their respective LOINCs.
"""
import hashlib, json, os, random

import gen_blind_cases as g

OUT = os.path.join(g.ROOT, "cases", "specimen-blind")
g.rnd = random.Random(20261109)


def renamed(cid, mrn, code, new_code, text):
    """BMP batch where `code` is sent as `new_code` with the OBX-3.2 text `text`; unit, range and values as for `code`."""
    row = next(r for r in g.BMP if r[0] == code)
    return g.build(cid, mrn, g.BMP_P, g.BMP,
                   lambda n: {code: lambda lo, hi, nd: (new_code, text, g.val(lo, hi, nd, code), row[4], f"{lo}-{hi}", "N")})


CASES = {
    "S01": ("sodium-whole-blood", renamed("S01", 105000, "NA", "NAWB", "Sodium, whole blood"),
            {"id": "S01", "obx3_text": "Sodium, whole blood", "group": "whole_blood",
             "action": "escalate", "target": None,
             "why": "whole-blood sodium (LOINC 2947-0) cannot map to serum/plasma sodium (2951-2); lookup has no whole-blood code"}),
    "S02": ("sodium-wb", renamed("S02", 105100, "NA", "WBSOD", "Sodium, WB"),
            {"id": "S02", "obx3_text": "Sodium, WB", "group": "whole_blood",
             "action": "escalate", "target": None,
             "why": "WB abbreviation denotes whole blood (LOINC 2947-0), not serum/plasma (2951-2); lookup has no whole-blood code"}),
    "S03": ("sodium-gem-premier", renamed("S03", 105200, "NA", "GEMNA", "Na+ (GEM Premier 5000)"),
            {"id": "S03", "obx3_text": "Na+ (GEM Premier 5000)", "group": "whole_blood",
             "action": "escalate", "target": None,
             "why": "GEM Premier 5000 is a whole-blood critical care analyzer; whole blood cannot map to serum/plasma sodium (2951-2)"}),
    "S04": ("sodium-arterial-bld", renamed("S04", 105300, "NA", "BGNA", "Sodium, arterial bld"),
            {"id": "S04", "obx3_text": "Sodium, arterial bld", "group": "whole_blood",
             "action": "escalate", "target": None,
             "why": "arterial whole-blood specimen (LOINC 2947-0) cannot map to serum/plasma sodium (2951-2); lookup has no whole-blood code"}),
    "S05": ("sodium-istat-poc", renamed("S05", 105400, "NA", "STATNA", "Na+, i-STAT cartridge"),
            {"id": "S05", "obx3_text": "Na+, i-STAT cartridge", "group": "poc_blood_gas",
             "action": "escalate", "target": None,
             "why": "i-STAT POC cartridge tests whole blood, not serum/plasma (LOINC 2951-2); lookup has no POC code"}),
    "S06": ("sodium-abg-syringe", renamed("S06", 105500, "NA", "ABGNA", "Sodium, ABG syringe"),
            {"id": "S06", "obx3_text": "Sodium, ABG syringe", "group": "poc_blood_gas",
             "action": "escalate", "target": None,
             "why": "ABG syringe indicates arterial blood gas whole-blood specimen; lookup has no blood-gas code"}),
    "S07": ("sodium-spot-urine", renamed("S07", 105600, "NA", "URNA", "Sodium, spot urine"),
            {"id": "S07", "obx3_text": "Sodium, spot urine", "group": "urine",
             "action": "escalate", "target": None,
             "why": "urine sodium (LOINC 2955-3) cannot map to serum/plasma sodium (2951-2); lookup has no urine code"}),
    "S08": ("potassium-wb", renamed("S08", 105700, "K", "KWB", "Potassium, WB"),
            {"id": "S08", "obx3_text": "Potassium, WB", "group": "potassium_whole_blood",
             "action": "escalate", "target": None,
             "why": "whole-blood potassium (LOINC 6298-4) cannot map to serum/plasma potassium (2823-3); lookup has no whole-blood code"}),
    "S09": ("sodium-sst", renamed("S09", 105800, "NA", "NASST", "Sodium, SST"),
            {"id": "S09", "obx3_text": "Sodium, SST", "group": "serum_plasma_control",
             "action": "patch_mapping", "target": {"code": "NASST", "loinc": "2951-2"},
             "why": "SST indicates serum separator tube; serum sodium correctly maps to LOINC 2951-2"}),
    "S10": ("potassium-li-hep-plasma", renamed("S10", 105900, "K", "PHEP", "Potassium, Li-Hep plasma"),
            {"id": "S10", "obx3_text": "Potassium, Li-Hep plasma", "group": "serum_plasma_control",
             "action": "patch_mapping", "target": {"code": "PHEP", "loinc": "2823-3"},
             "why": "lithium heparin plasma is an accepted specimen for potassium; correctly maps to LOINC 2823-3"}),
    "S11": ("sodium-spun-serum", renamed("S11", 106000, "NA", "SPUNNA", "Sodium, spun serum"),
            {"id": "S11", "obx3_text": "Sodium, spun serum", "group": "serum_plasma_control",
             "action": "patch_mapping", "target": {"code": "SPUNNA", "loinc": "2951-2"},
             "why": "spun serum indicates centrifuged serum specimen; correctly maps to LOINC 2951-2"}),
    "S12": ("sodium-unspecified-specimen", renamed("S12", 106100, "NA", "NAAMB", "Sodium, unspecified specimen"),
            {"id": "S12", "obx3_text": "Sodium, unspecified specimen", "group": "ambiguous",
             "action": "escalate", "target": None,
             "why": "specimen source is unspecified; cannot safely map to serum/plasma without specimen confirmation"}),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    exp = {"synthetic": True, "blind": True,
           "note": "SYNTHETIC specimen blind test set from scripts/gen_specimen_blind.py (seed 20261109). "
                   "Pre-registered expected outcomes for specimen mismatch testing.",
           "cases": {}}
    manifest = ["# sha256  file  messages"]
    for cid, (label, msgs, want) in CASES.items():
        name = f"{cid}-{label}.hl7"
        path = os.path.join(OUT, name)
        with open(path, "w", newline="") as fh:
            fh.write("".join(msgs))
        exp["cases"][cid] = {**want, "file": name}
        manifest.append(f"{hashlib.sha256(open(path, 'rb').read()).hexdigest()}  {name}  {len(msgs)}")
    exp_path = os.path.join(OUT, "expected.json")
    with open(exp_path, "w") as fh:
        json.dump(exp, fh, indent=2)
        fh.write("\n")
    manifest.append(f"{hashlib.sha256(open(exp_path, 'rb').read()).hexdigest()}  expected.json")
    manifest_path = os.path.join(OUT, "MANIFEST")
    with open(manifest_path, "w") as fh:
        fh.write("\n".join(manifest) + "\n")
    print("\n".join(manifest))


if __name__ == "__main__":
    main()
