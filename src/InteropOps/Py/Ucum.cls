/// Embedded Python helpers (standard library only): UCUM-style unit normalization/comparison and OBX parsing for evidence.
/// Not wired into the agent or Tools.CheckUnitEquivalence. All methods take %String and return a JSON string
/// (load with {}.%FromJSON(json)). Self-test: do ##class(InteropOps.Py.UcumTest).Run()
Class InteropOps.Py.Ucum
{

/// Normalize one unit: JSON {input, normalized, known, factor_to_base, dimension{mass|volume|amount|enzyme|charge: exp}, error?}.
/// factor_to_base is relative to g, L, mol, U (e.g. mg/dL -> 0.01 g/L).
ClassMethod Normalize(pUnit As %String) As %String
{
    Quit ..Units(pUnit, "", "")
}

/// Compare two units, optionally for an analyte (local code, e.g. GLU). JSON {from, to, analyte, same_unit, convertible,
/// factor (multiply a value in pFrom by it to get pTo; null if not convertible), basis (prefix|lab_convention|molar_mass),
/// analyte_dependent, factor_molar_mass?, molar_mass_g_per_mol?, note}.
/// Mass <-> amount (mg/dL <-> mmol/L) is ANALYTE-DEPENDENT: it needs the molar mass and is refused without a known analyte.
/// GLU uses the lookup convention 0.0555556 (1/18; molar mass 180.156 gives 0.0555074), CREAT 88.4.
ClassMethod Compare(pFrom As %String, pTo As %String, pAnalyte As %String = "") As %String
{
    Quit ..Units(pFrom, pTo, pAnalyte)
}

/// Python core of Normalize (pTo = "") and Compare. Case-insensitive synonyms (mg/dl = mg/dL, umol/l, \u00b5/\u03bc -> u, mcg -> ug, cc -> mL).
ClassMethod Units(pFrom As %String, pTo As %String = "", pAnalyte As %String = "") As %String [ Language = python ]
{
    import json, re, math
    ANALYTES = {
        "GLU": {"name": "glucose", "mw": 180.156, "convention": {("mg/dL", "mmol/L"): 0.0555556}},
        "CREAT": {"name": "creatinine", "mw": 113.12, "convention": {("mg/dL", "umol/L"): 88.4}},
        "BUN": {"name": "urea nitrogen (as N2)", "mw": 28.014, "convention": {}},
    }
    PREFIX = {"": 1.0, "k": 1e3, "h": 1e2, "da": 1e1, "d": 1e-1, "c": 1e-2, "m": 1e-3, "u": 1e-6, "n": 1e-9, "p": 1e-12, "f": 1e-15}
    BASE = {"g": "mass", "L": "volume", "mol": "amount", "U": "enzyme", "eq": "charge"}
    SYN = {"mcg": "ug", "cc": "mL", "mmol": "mmol", "gm": "g", "gr": "g", "iu": "[IU]"}
    def clean(u):
        s = (u or "").strip().replace("\u00b5", "u").replace("\u03bc", "u").replace(" ", "")
        s = re.sub(r"(?i)^/?(l|liter|litre)$", "L", s)
        return s
    def atom(a):
        if a == "" or a == "1":
            return {"ok": True, "f": 1.0, "dim": {}, "norm": "1" if a == "1" else ""}
        m = re.fullmatch(r"10\*(-?\d+)", a) or re.fullmatch(r"10\^(-?\d+)", a)
        if m:
            return {"ok": True, "f": 10.0 ** int(m.group(1)), "dim": {}, "norm": "10*" + m.group(1)}
        if a == "%":
            return {"ok": True, "f": 0.01, "dim": {}, "norm": "%"}
        low = a.lower()
        if low in SYN:
            a = SYN[low]; low = a.lower()
        for base in sorted(BASE, key=len, reverse=True):
            bl = base.lower()
            if low.endswith(bl):
                pre = low[: len(low) - len(bl)]
                if pre in PREFIX:
                    return {"ok": True, "f": PREFIX[pre], "dim": {BASE[base]: 1}, "norm": pre + base, "base": base, "prefix": pre}
        return {"ok": False, "norm": a}
    def parse(u):
        s = clean(u)
        out = {"input": u, "normalized": s, "known": False, "factor_to_base": None, "dimension": {}}
        if s == "":
            out["error"] = "empty unit"; return out
        parts = s.split("/")
        if len(parts) > 2:
            out["error"] = "more than one '/' not supported"; return out
        num = atom(parts[0]); den = atom(parts[1]) if len(parts) == 2 else {"ok": True, "f": 1.0, "dim": {}, "norm": ""}
        if not (num["ok"] and den["ok"]) or (len(parts) == 2 and den["norm"] in ("", "1")):
            out["error"] = "unknown unit atom"; return out
        dim = dict(num["dim"])
        for k, v in den["dim"].items():
            dim[k] = dim.get(k, 0) - v
        dim = {k: v for k, v in dim.items() if v != 0}
        out["normalized"] = num["norm"] + ("/" + den["norm"] if len(parts) == 2 else "")
        if out["normalized"].startswith("/"):
            out["normalized"] = "1" + out["normalized"]
        out["known"] = True
        out["factor_to_base"] = num["f"] / den["f"]
        out["dimension"] = dim
        return out
    def close(a, b):
        return abs(a - b) <= 1e-9 * max(abs(a), abs(b), 1e-300)
    fr = parse(pFrom)
    if (pTo or "") == "":
        return json.dumps(fr, sort_keys=True)
    to = parse(pTo)
    code = (pAnalyte or "").strip().upper()
    res = {"from": fr, "to": to, "analyte": code, "same_unit": False, "convertible": False,
           "factor": None, "basis": None, "analyte_dependent": False, "note": ""}
    if not (fr["known"] and to["known"]):
        res["note"] = "unknown unit"; return json.dumps(res, sort_keys=True)
    if fr["dimension"] == to["dimension"]:
        f = fr["factor_to_base"] / to["factor_to_base"]
        res.update({"convertible": True, "factor": float("%.10g" % f), "basis": "prefix"})
        res["same_unit"] = close(f, 1.0)
        res["note"] = "same unit" if res["same_unit"] else "same dimension, prefix/scale factor only"
        return json.dumps(res, sort_keys=True)
    def swap(d):
        return {("mass" if k == "amount" else k): v for k, v in d.items()}
    fa, ta = fr["dimension"], to["dimension"]
    mass_amount = (fa.get("mass") == 1 and swap(ta) == fa and ta.get("amount") == 1) or (fa.get("amount") == 1 and swap(fa) == ta and ta.get("mass") == 1)
    if not mass_amount:
        res["note"] = "different dimensions, not convertible"
        return json.dumps(res, sort_keys=True)
    res["analyte_dependent"] = True
    a = ANALYTES.get(code)
    if a is None:
        res["note"] = "mass<->amount conversion needs the analyte molar mass; analyte unknown or not given"
        return json.dumps(res, sort_keys=True)
    f = fr["factor_to_base"] / to["factor_to_base"]
    f = f / a["mw"] if fa.get("mass") == 1 else f * a["mw"]
    res["factor_molar_mass"] = float("%.6g" % f)
    res["molar_mass_g_per_mol"] = a["mw"]
    res["convertible"] = True
    conv = a["convention"].get((fr["normalized"], to["normalized"]))
    if conv is not None:
        res.update({"factor": conv, "basis": "lab_convention"})
        res["note"] = "analyte-dependent (%s, M=%s g/mol); factor is the lab/lookup convention, molar-mass factor %s" % (a["name"], a["mw"], res["factor_molar_mass"])
    else:
        res.update({"factor": res["factor_molar_mass"], "basis": "molar_mass"})
        res["note"] = "analyte-dependent (%s, M=%s g/mol)" % (a["name"], a["mw"])
    return json.dumps(res, sort_keys=True)
}

/// Parse one OBX segment to JSON {segment, delimiters, set_id, value_type, code{id,text,system,alt_id,alt_text,alt_system}, sub_id,
/// value (string, or list for repetitions), value_num, units{raw,id,text,system}, ref_range{raw,low,high}, abnormal_flags[], status, field_count, error}.
/// pDelims: the full MSH segment, or MSH-2 (e.g. "^~\&"), or "" for the default |^~\&; the field separator is taken from the OBX itself unless an MSH is given.
ClassMethod ParseOBX(pSegment As %String, pDelims As %String = "") As %String [ Language = python ]
{
    import json, re
    seg = (pSegment or "").strip("\r\n")
    enc = pDelims or ""
    fs, cs, rs, es, ss = "|", "^", "~", "\\", "&"
    if enc.startswith("MSH") and len(enc) >= 8:
        fs = enc[3]; enc = enc[4:8]
    if len(enc) >= 4:
        cs, rs, es, ss = enc[0], enc[1], enc[2], enc[3]
    if seg[:3] == "OBX" and len(seg) > 3 and not (pDelims or "").startswith("MSH"):
        fs = seg[3]
    out = {"segment": seg[:3], "delimiters": fs + cs + rs + es + ss, "error": None}
    if seg[:3] != "OBX":
        out["error"] = "not an OBX segment"
        return json.dumps(out, sort_keys=True)
    def unesc(v):
        if es not in v:
            return v
        m = {"F": fs, "S": cs, "R": rs, "E": es, "T": ss}
        return re.sub(re.escape(es) + r"([FSRET])" + re.escape(es), lambda x: m[x.group(1)], v)
    f = seg.split(fs)
    def fld(i):
        return f[i] if i < len(f) else ""
    def comps(v):
        return [unesc(c) for c in v.split(cs)] if v != "" else []
    def num(v):
        try:
            return float(v)
        except ValueError:
            return None
    c3 = comps(fld(3)) + [""] * 6
    out["set_id"] = fld(1)
    out["value_type"] = fld(2)
    out["code"] = {"id": c3[0], "text": c3[1], "system": c3[2], "alt_id": c3[3], "alt_text": c3[4], "alt_system": c3[5]}
    out["sub_id"] = fld(4)
    reps = [unesc(r) for r in fld(5).split(rs)] if fld(5) != "" else []
    out["value"] = reps[0] if len(reps) == 1 else (reps if reps else "")
    out["value_num"] = num(reps[0]) if len(reps) == 1 and out["value_type"] in ("NM", "SN", "") else None
    c6 = comps(fld(6)) + [""] * 3
    out["units"] = {"raw": unesc(fld(6)), "id": c6[0], "text": c6[1], "system": c6[2]}
    rr = unesc(fld(7))
    rng = {"raw": rr, "low": None, "high": None}
    m = re.fullmatch(r"\s*(-?\d+(?:\.\d+)?)\s*-\s*(-?\d+(?:\.\d+)?)\s*", rr)
    if m:
        rng["low"], rng["high"] = float(m.group(1)), float(m.group(2))
    else:
        m = re.fullmatch(r"\s*([<>]=?)\s*(-?\d+(?:\.\d+)?)\s*", rr)
        if m:
            rng["low" if m.group(1).startswith(">") else "high"] = float(m.group(2))
    out["ref_range"] = rng
    out["abnormal_flags"] = [unesc(x) for x in fld(8).split(rs) if x != ""]
    out["status"] = fld(11)
    out["field_count"] = len(f) - 1
    return json.dumps(out, sort_keys=True)
}

}
