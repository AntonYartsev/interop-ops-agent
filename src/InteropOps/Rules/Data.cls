/// Data access for rules, gate and agent tools. Nothing here reads ground truth.
/// - lookup: Ens.Util.LookupTable "IOA.LabCodeMap" (local_code -> LOINC, loaded by Setup) joined with the metadata
///   columns of data/labcodemap.csv by LOINC (so an applied patch, e.g. SOD -> 2951-2, gets the Sodium metadata)
/// - baseline DTL: data/baseline_dtl.json; history: data/history_200.json (raws + summary cached in ^IOA.Cache)
/// - current batch: ^IOA.Batch(caseId, n) = raw HL7 (segments end with $C(13)), written by the BPL at ingest
Class InteropOps.Rules.Data
{

Parameter LOOKUPTABLE = "IOA.LabCodeMap";

ClassMethod Lookup() As %DynamicObject
{
    Set tStream = ##class(%Stream.FileCharacter).%New()
    $$$ThrowOnError(tStream.LinkToFile(##class(InteropOps.Util.Paths).DataDir() _ "labcodemap.csv"))
    While 'tStream.AtEnd {
        Set tLine = $ZSTRIP(tStream.ReadLine(), "<>WC")
        Continue:(tLine="")||($EXTRACT(tLine)="#")||($PIECE(tLine, ",")="local_code")
        Set tMeta = {"canonical_code": ($PIECE(tLine, ",", 2)), "canonical_name": ($PIECE(tLine, ",", 3)), "short_name": ($PIECE(tLine, ",", 4)),
            "expected_unit": ($PIECE(tLine, ",", 5)), "ref_range": ($PIECE(tLine, ",", 6)), "panel": ($PIECE(tLine, ",", 7))}
        Set tByLocal($PIECE(tLine, ",")) = tMeta.%ToJSON()
        Set:'$DATA(tByLoinc(tMeta."canonical_code")) tByLoinc(tMeta."canonical_code") = tMeta.%ToJSON()
    }
    Set tOut = {}, tLocal = ""
    For {
        Set tLocal = $ORDER(^Ens.LookupTable(..#LOOKUPTABLE, tLocal), 1, tLoinc)
        Quit:tLocal=""
        Set tJ = $GET(tByLocal(tLocal))
        If (tJ = "") || ({}.%FromJSON(tJ)."canonical_code" '= tLoinc) Set tJ = $GET(tByLoinc(tLoinc), {"canonical_code": (tLoinc)}.%ToJSON())
        Do tOut.%Set(tLocal, {}.%FromJSON(tJ))
    }
    Return tOut
}

ClassMethod BaselineDTL() As %DynamicObject
{
    Return ##class(InteropOps.Util.Paths).ReadJSON("baseline_dtl.json")
}

/// Load history_200.json into ^IOA.Cache once per file version (mtime + size)
ClassMethod EnsureHistory()
{
    Set tFile = ##class(InteropOps.Util.Paths).DataDir() _ "history_200.json"
    Set tStamp = ##class(%File).GetFileDateModified(tFile) _ "/" _ ##class(%File).GetFileSize(tFile)
    Quit:$GET(^IOA.Cache("history", "stamp"))=tStamp
    Kill ^IOA.Cache("history")
    Set tMsgs = ##class(InteropOps.Util.Paths).ReadJSON("history_200.json").messages, tRaws = []
    For i = 0:1:tMsgs.%Size() - 1 {
        Set tRaw = tMsgs.%Get(i)."raw_hl7", ^IOA.Cache("history", "raw", i + 1) = tRaw
        Do tRaws.%Push(tRaw)
    }
    Set ^IOA.Cache("history", "summary") = ##class(InteropOps.Rules.BatchStats).Summarize(tRaws, ..BaselineDTL()).%ToJSON()
    Set ^IOA.Cache("history", "stamp") = tStamp
}

ClassMethod HistorySummary() As %DynamicObject
{
    Do ..EnsureHistory()
    Return {}.%FromJSON(^IOA.Cache("history", "summary"))
}

/// Raw history message n (1..HistoryCount())
ClassMethod HistoryRaw(pN As %Integer) As %String
{
    Return $GET(^IOA.Cache("history", "raw", pN))
}

ClassMethod HistoryCount() As %Integer
{
    Do ..EnsureHistory()
    Return +$ORDER(^IOA.Cache("history", "raw", ""), -1)
}

ClassMethod BatchCount(pCaseId As %String) As %Integer
{
    Return +$ORDER(^IOA.Batch(pCaseId, ""), -1)
}

ClassMethod BatchRaw(pCaseId As %String, pN As %Integer) As %String
{
    Return $GET(^IOA.Batch(pCaseId, pN))
}

/// SHA-256 (hex) of the stored batch, written by the BPL at ingest: ^IOA.Batch(caseId) = sha
ClassMethod BatchSHA(pCaseId As %String) As %String
{
    Return $GET(^IOA.Batch(pCaseId))
}

/// Summary of the current batch (same shape as history summary)
ClassMethod BatchSummary(pCaseId As %String) As %DynamicObject
{
    Set tRaws = []
    For i = 1:1:..BatchCount(pCaseId) Do tRaws.%Push(^IOA.Batch(pCaseId, i))
    Return ##class(InteropOps.Rules.BatchStats).Summarize(tRaws, ..BaselineDTL())
}

/// MSH-10 of a raw message (MSH-1 is the field separator, so MSH-10 is piece 10)
ClassMethod MSH10(pRaw As %String) As %String
{
    Return $PIECE($PIECE(pRaw, $CHAR(13), 1), "|", 10)
}

}
