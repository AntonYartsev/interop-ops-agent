/// Text embedders for the Vector Search KB (bonus; agent evidence via Evidence.Builder.Similar).
///   local  (default): deterministic hashed bag-of-words + word bigrams + char 3-grams, small synonym map, lowercase,
///          L2-normalized, 384 dimensions, Embedded Python standard library only. Free, no network.
///   openai (IOA_KB_EMBED=openai): text-embedding-3-small, 1536 dimensions, key from the OPENAI_API_KEY variable of the
///          IRIS process. UNVERIFIED (never called in tests or demo). Guarded, see Embed().
Class InteropOps.KB.Embedder
{

Parameter LOCALDIM = 384;

Parameter LOCALMODEL = "local-hash-384-v1";

Parameter OPENAIDIM = 1536;

Parameter OPENAIMODEL = "text-embedding-3-small";

/// Requested embedder: "openai" only if IOA_KB_EMBED=openai (env or ^IOA.Config), else "local"
ClassMethod Kind() As %String
{
    Quit $SELECT($ZCONVERT(##class(InteropOps.Config.LLMConfig).GetVar("IOA_KB_EMBED"), "L") = "openai": "openai", 1: "local")
}

/// Embed pText with pKind ("" = Kind()). Returns the vector as a comma-separated string (TO_VECTOR input).
/// Output: pUsed = embedder really used ("local" | "openai"), pModel, pDim, pWarn (why openai fell back to local).
/// The openai path runs only if ALL hold: pKind = openai, LLMConfig.Mode() = LIVE, profile openai, the IRIS process
/// sees OPENAI_API_KEY, IOA_MAX_USD not reached, and Operation.Reserve(1) succeeds. Otherwise it falls back to local.
/// Spend: 1 call in ^IOA.Budget("calls"); tokens * IOA_KB_EMBED_PRICE_PER_M (default 0.02) / 1e6 added to ^IOA.Budget("usd").
ClassMethod Embed(pText As %String, pKind As %String = "", Output pUsed As %String, Output pModel As %String, Output pDim As %Integer, Output pWarn As %String) As %String
{
    Set pWarn = "", tKind = $SELECT(pKind = "": ..Kind(), 1: $ZCONVERT(pKind, "L"))
    If tKind = "openai" {
        Set tVec = ..OpenAIGuarded(pText, .pWarn)
        If tVec '= "" Set pUsed = "openai", pModel = ..#OPENAIMODEL, pDim = ..#OPENAIDIM Quit tVec
    }
    Set pUsed = "local", pModel = ..#LOCALMODEL, pDim = ..#LOCALDIM
    Quit ..Local(pText)
}

/// OpenAI path with all guards and budget accounting; "" plus pWarn when it does not run or fails
ClassMethod OpenAIGuarded(pText As %String, Output pWarn As %String) As %String [ Private ]
{
    Set pWarn = "", C = "InteropOps.Config.LLMConfig", O = "InteropOps.Agent.Operation"
    If $CLASSMETHOD(C, "Mode") '= "LIVE" Set pWarn = "openai embedder needs LIVE mode; used local" Quit ""
    If $CLASSMETHOD(C, "Profile") '= "openai" Set pWarn = "openai embedder needs LLM profile openai; used local" Quit ""
    If '$CLASSMETHOD(C, "ProcessKeyPresent", "OPENAI_API_KEY") Set pWarn = "OPENAI_API_KEY not set in the IRIS process; used local" Quit ""
    If $CLASSMETHOD(O, "OverUSD", .tSpent, .tCap) Set pWarn = "IOA_MAX_USD reached ("_tSpent_" >= "_tCap_"); used local" Quit ""
    If '$CLASSMETHOD(O, "Reserve", 1, .tUsedCalls) Set pWarn = "LLM call budget exhausted; used local" Quit ""
    Set tRes = {}.%FromJSON(..OpenAI(pText))
    Set tTok = +tRes.tokens
    Do $CLASSMETHOD(O, "Settle", 1, 1, tTok, 0)
    If tTok > 0 {
        Lock +^IOA.Budget:10
        Set tL = $TEST
        Set ^IOA.Budget("usd") = $GET(^IOA.Budget("usd")) + (tTok * $CLASSMETHOD(O, "Price", "IOA_KB_EMBED_PRICE_PER_M", 0.02) / 1000000)
        Lock:tL -^IOA.Budget
    }
    If tRes.error '= "" Set pWarn = "openai embedding failed: "_tRes.error_"; used local" Quit ""
    Quit tRes.vector
}

/// Raw OpenAI call (no guards; use Embed). JSON {vector: "comma string", tokens, error?}. The key is never returned or logged.
ClassMethod OpenAI(pText As %String) As %String [ Language = python ]
{
    import json, os, urllib.request
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key:
        return json.dumps({"vector": "", "tokens": 0, "error": "no key"})
    body = json.dumps({"model": "text-embedding-3-small", "input": str(pText or ""), "dimensions": 1536}).encode("utf-8")
    req = urllib.request.Request("https://api.openai.com/v1/embeddings", data=body, method="POST",
                                 headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            d = json.loads(r.read().decode("utf-8"))
        v = d["data"][0]["embedding"]
        tok = int(d.get("usage", {}).get("total_tokens", 0))
        return json.dumps({"vector": ",".join(repr(float(x)) for x in v), "tokens": tok})
    except Exception as e:
        return json.dumps({"vector": "", "tokens": 0, "error": type(e).__name__ + ": " + str(e)[:200]})
}

/// Local deterministic embedder: comma-separated 384 floats (6 decimals), L2-normalized; all zeros for empty text.
/// Must stay identical to the generator of data/kb_runbook.json (KBTest checks parity).
ClassMethod Local(pText As %String) As %String [ Language = python ]
{
    import hashlib, math, re
    DIM = 384
    MODEL = "local-hash-384-v1"
    STOP = set("a an the of to in on for and or is are was were be by with from as at it its this that than then into per no not".split())
    SYN = {"glucose": "glu", "sugar": "glu", "potassium": "k", "sodium": "na", "creatinine": "creat", "hemoglobin": "hb",
           "haemoglobin": "hb", "hgb": "hb", "hematocrit": "hct", "haematocrit": "hct", "urea": "bun", "duplicate": "dup",
           "duplicates": "dup", "duplicated": "dup", "repeated": "dup", "resent": "resend", "resends": "resend",
           "retransmitted": "resend", "corrected": "correction", "amended": "correction", "mmol": "mmol", "umol": "umol",
           "micromol": "umol", "identifier": "id", "mrn": "id", "unit": "units", "uom": "units", "critical": "critical",
           "panic": "critical", "alarm": "critical", "route": "routing", "routed": "routing", "router": "routing",
           "injection": "inject", "injected": "inject", "instructions": "instruction", "ack": "ack", "acknowledgement": "ack",
           "acknowledgment": "ack", "control": "control", "mapping": "map", "mapped": "map", "loinc": "loinc"}
    
    def tokens(text):
        t = str(text or "").lower().replace("\u00b5", "u").replace("\u03bc", "u")
        out = []
        for w in re.findall(r"[a-z0-9]+(?:[./][a-z0-9]+)*", t):
            parts = [w] + (re.split(r"[./]", w) if ("/" in w or "." in w) and not re.fullmatch(r"[0-9.]+", w) else [])
            for p in parts:
                if not p or p in STOP:
                    continue
                p = SYN.get(p, p)
                if len(p) > 4 and p.endswith("s") and not p.endswith("ss"):
                    p = SYN.get(p[:-1], p[:-1])
                out.append(p)
        return out
    
    def _add(vec, feat, w):
        h = int.from_bytes(hashlib.blake2b(feat.encode("utf-8"), digest_size=8).digest(), "big")
        vec[h % DIM] += w if (h >> 40) & 1 else -w
    
    def embed(text):
        vec = [0.0] * DIM
        toks = tokens(text)
        for i, tk in enumerate(toks):
            _add(vec, "w:" + tk, 1.0)
            if i + 1 < len(toks):
                _add(vec, "b:" + tk + "_" + toks[i + 1], 0.5)
            if len(tk) >= 4 and not tk.isdigit():
                g = "#" + tk + "#"
                grams = [g[j:j + 3] for j in range(len(g) - 2)]
                for gr in grams:
                    _add(vec, "c:" + gr, 0.6 / len(grams))
        n = math.sqrt(sum(x * x for x in vec))
        if n > 0:
            vec = [x / n for x in vec]
        return ",".join("%.6f" % x for x in vec)
    return embed(pText)
}

}
