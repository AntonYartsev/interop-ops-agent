/// Vector Search KB (bonus; agent evidence via Evidence.Builder.Similar): load the fixture and search with SQL VECTOR_COSINE.
///   do ##class(InteropOps.KB.Store).Load()                    // data/kb_runbook.json, precomputed local vectors
///   write ##class(InteropOps.KB.Store).Search("glucose in mg/dL, receiver wants mmol/L", 3)
/// Self-test: do ##class(InteropOps.KB.KBTest).Run()
Class InteropOps.KB.Store
{

Parameter FIXTURE = "kb_runbook.json";

/// (Re)load the fixture from DataDir() (pFile = file name or absolute path): deletes and re-inserts all KB rows
/// (InteropOps_KB.Entry only), EmbLocal from the precomputed vectors, no embedding call. pCount = rows loaded.
ClassMethod Load(pFile As %String = "", Output pCount As %Integer) As %Status
{
    Set pCount = 0, tSC = $$$OK
    Try {
        Set tFile = $SELECT(pFile = "": ..#FIXTURE, 1: pFile)
        If $EXTRACT(tFile) = "/" {
            Set tStream = ##class(%Stream.FileCharacter).%New(), tStream.TranslateTable = "UTF8"
            $$$ThrowOnError(tStream.LinkToFile(tFile))
            Set tFix = ##class(%DynamicAbstractObject).%FromJSON(tStream)
        } Else {
            Set tFix = ##class(InteropOps.Util.Paths).ReadJSON(tFile)
        }
        Set tDim = ##class(InteropOps.KB.Embedder).#LOCALDIM
        If (tFix.dim '= tDim) || (tFix.model '= ##class(InteropOps.KB.Embedder).#LOCALMODEL) {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "fixture model/dim "_tFix.model_"/"_tFix.dim_" does not match the local embedder"))
        }
        Set tR = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM InteropOps_KB.Entry")
        If tR.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tR.%SQLCODE, tR.%Message))
        Set tSql = "INSERT INTO InteropOps_KB.Entry (Slug, Title, Body, Tags, LocalModel, EmbLocal) VALUES (?, ?, ?, ?, ?, TO_VECTOR(?, DOUBLE, "_tDim_"))"
        Set tSt = ##class(%SQL.Statement).%New()
        $$$ThrowOnError(tSt.%Prepare(tSql))
        Set tIt = tFix.entries.%GetIterator()
        While tIt.%GetNext(, .e) {
            Set tVec = ..Join(e.vector)
            If $LENGTH(tVec, ",") '= tDim $$$ThrowStatus($$$ERROR($$$GeneralError, "entry "_e.key_": vector length "_$LENGTH(tVec, ",")))
            Set tR = tSt.%Execute(e.key, e.title, e.body, e.tags, tFix.model, tVec)
            If tR.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tR.%SQLCODE, tR.%Message))
            Set pCount = pCount + 1
        }
    } Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// Top pTopK (1..50) entries for pText by cosine similarity. pEmbedder: "" = Embedder.Kind() (IOA_KB_EMBED), "local", "openai".
/// openai searches EmbOpenAI (only rows embedded by Reembed("openai")); if its guards fail, it falls back to local + warning.
/// Returns JSON: {"query","embedder","model","dim","topK","results":[{"rank","slug","title","body","tags","score"}],"warnings":[]}
/// or {"query","error"}. score = VECTOR_COSINE, rounded to 4 decimals.
ClassMethod Search(pText As %String, pTopK As %Integer = 3, pEmbedder As %String = "") As %String
{
    Set tOut = {"query": (pText)}
    Try {
        Set tTop = +pTopK
        Set:(tTop < 1) tTop = 1
        Set:(tTop > 50) tTop = 50
        Set tVec = ##class(InteropOps.KB.Embedder).Embed(pText, pEmbedder, .tUsed, .tModel, .tDim, .tWarn)
        Set tCol = $SELECT(tUsed = "openai": "EmbOpenAI", 1: "EmbLocal")
        Set tSql = "SELECT TOP "_tTop_" Slug, Title, Body, Tags, VECTOR_COSINE("_tCol_", TO_VECTOR(?, DOUBLE, "_tDim_")) AS Score"
            _" FROM InteropOps_KB.Entry WHERE "_tCol_" IS NOT NULL ORDER BY Score DESC"
        Set tR = ##class(%SQL.Statement).%ExecDirect(, tSql, tVec)
        If tR.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tR.%SQLCODE, tR.%Message))
        Set tRes = [], tRank = 0
        While tR.%Next() {
            Set tRank = tRank + 1
            Do tRes.%Push({"rank": (tRank), "slug": (tR.Slug), "title": (tR.Title), "body": (tR.Body), "tags": (tR.Tags), "score": ($FNUMBER(tR.Score, "", 4) + 0)})
        }
        Set tW = []
        Do:(tWarn '= "") tW.%Push(tWarn)
        Do:(tRank = 0) tW.%Push("no rows with "_tCol_"; run Load()"_$SELECT(tUsed = "openai": " and Reembed(""openai"")", 1: ""))
        Set tOut.embedder = tUsed, tOut.model = tModel, tOut.dim = tDim, tOut.topK = tTop, tOut.results = tRes, tOut.warnings = tW
    } Catch ex {
        Set tOut.error = $SYSTEM.Status.GetErrorText(ex.AsStatus())
    }
    Quit tOut.%ToJSON()
}

/// Re-embed every row with pEmbedder ("local" or "openai"; text = title. body tags, as in the fixture).
/// openai: one guarded, budget-counted API call per row (UNVERIFIED, never run in tests); stops at the first fallback.
/// pCount = rows updated, pWarn = reason it stopped.
ClassMethod Reembed(pEmbedder As %String = "local", Output pCount As %Integer, Output pWarn As %String) As %Status
{
    Set pCount = 0, pWarn = "", tSC = $$$OK
    Try {
        Set tKind = $ZCONVERT(pEmbedder, "L")
        Set tR = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Title, Body, Tags FROM InteropOps_KB.Entry ORDER BY ID")
        While tR.%Next() {
            Set tVec = ##class(InteropOps.KB.Embedder).Embed(tR.Title_". "_tR.Body_" "_tR.Tags, tKind, .tUsed, .tModel, .tDim, .tW)
            If tUsed '= tKind Set pWarn = tW Quit
            Set tCol = $SELECT(tUsed = "openai": "EmbOpenAI", 1: "EmbLocal"), tMCol = $SELECT(tUsed = "openai": "OpenAIModel", 1: "LocalModel")
            Set tU = ##class(%SQL.Statement).%ExecDirect(, "UPDATE InteropOps_KB.Entry SET "_tCol_" = TO_VECTOR(?, DOUBLE, "_tDim_"), "_tMCol_" = ? WHERE ID = ?", tVec, tModel, tR.ID)
            If tU.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tU.%SQLCODE, tU.%Message))
            Set pCount = pCount + 1
        }
    } Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// Number of KB rows
ClassMethod Count() As %Integer
{
    Set tR = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM InteropOps_KB.Entry")
    Quit $SELECT(tR.%Next(): +tR.N, 1: 0)
}

/// Dynamic array of numbers -> "n1,n2,..."
ClassMethod Join(pArr As %DynamicArray) As %String [ Private ]
{
    Set tS = "", tIt = pArr.%GetIterator()
    While tIt.%GetNext(, .v) { Set tS = tS_$SELECT(tS = "": "", 1: ",")_v }
    Quit tS
}

}
