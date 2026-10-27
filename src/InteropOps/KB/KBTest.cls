/// Self-test for the Vector Search KB (local embedder only, no network, no LLM call).
/// Run: do ##class(InteropOps.KB.KBTest).Run() -> writes KB_TEST=PASS|FAIL. Reloads InteropOps_KB.Entry from the fixture.
Class InteropOps.KB.KBTest
{

ClassMethod Run() As %Boolean
{
    Set tFail = ""
    Try {
        Set S = "InteropOps.KB.Store", E = "InteropOps.KB.Embedder"
        Set tSC = $CLASSMETHOD(S, "Load", "", .tN)
        If $$$ISERR(tSC) Set tFail = tFail_" load:"_$SYSTEM.Status.GetErrorText(tSC)
        If (tN < 15) || (tN > 30) || ($CLASSMETHOD(S, "Count") '= tN) Set tFail = tFail_" count="_tN
        // parity: the IRIS local embedder reproduces the fixture vector of every entry
        Set tR = ##class(%SQL.Statement).%ExecDirect(, "SELECT Slug, Title, Body, Tags FROM InteropOps_KB.Entry")
        Set tSt = ##class(%SQL.Statement).%New()
        Do tSt.%Prepare("SELECT VECTOR_COSINE(EmbLocal, TO_VECTOR(?, DOUBLE, 384)) AS C FROM InteropOps_KB.Entry WHERE Slug = ?")
        Set tMin = 1
        While tR.%Next() {
            Set tC = tSt.%Execute($CLASSMETHOD(E, "Local", tR.Title_". "_tR.Body_" "_tR.Tags), tR.Slug)
            Do tC.%Next()
            Set:(tC.C < tMin) tMin = tC.C
        }
        If tMin < 0.9999 Set tFail = tFail_" parity_min="_tMin
        Write "KB entries=", tN, " parity_min_cosine=", $FNUMBER(tMin, "", 6), !
        // three queries with an expected top-1; explicit "local" so IOA_KB_EMBED never triggers a network call
        For i = 1:1:3 {
            Set tQ = $LIST($LISTBUILD("glucose came in mg/dl but the receiver wants mmol/l", "same message control id received again and again", "potassium panic value flagged HH"), i)
            Set tExp = $LIST($LISTBUILD("kb-glucose-units", "kb-duplicate-flood", "kb-critical-potassium"), i)
            Set r = {}.%FromJSON($CLASSMETHOD(S, "Search", tQ, 3, "local"))
            Set t1 = r.results.%Get(0), t2 = r.results.%Get(1)
            Set tOk = (r.error = "") && (r.embedder = "local") && (r.dim = 384) && (r.results.%Size() = 3) && $ISOBJECT(t1)
            Set tOk = tOk && (t1.slug = tExp) && (t1.score > 0.25) && (t1.score > (t2.score + 0.05))
            Write "Q", i, " """, tQ, """ -> ", $SELECT($ISOBJECT(t1): t1.slug_" score="_t1.score_" (2nd "_t2.slug_" "_t2.score_")", 1: r.%ToJSON()), !
            If 'tOk Set tFail = tFail_" q"_i
        }
        // empty query: valid JSON, zero vector, no error
        Set r = {}.%FromJSON($CLASSMETHOD(S, "Search", "", 1, "local"))
        If r.error '= "" Set tFail = tFail_" empty_query"
    } Catch ex {
        Set tFail = tFail_" exception:"_ex.DisplayString()
    }
    Write:(tFail '= "") "KB_TEST failures:", tFail, !
    Write "KB_TEST=", $SELECT(tFail = "": "PASS", 1: "FAIL"), !
    Quit (tFail = "")
}

}
