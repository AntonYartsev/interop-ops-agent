/// IOA.Evidence.Ucum: per OBX of the batch, InteropOps.Py.Ucum.ParseOBX + Compare(OBX-6, expected unit of the
/// lookup entry for OBX-3, code). Findings are aggregated by (code, unit, expected unit, verdict) with message counts.
/// Verdicts: same_unit, spelling_variant (UCUM-equal, different spelling), convertible (factor), analyte_dependent,
/// not_convertible, unit_missing (empty OBX-6), code_not_in_lookup. Never faults: on error Status=unavailable.
Class InteropOps.Evidence.UcumCheck Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method Check(pRequest As InteropOps.Msg.EvidenceRequest, Output pResponse As InteropOps.Msg.EvidenceResponse) As %Status
{
    Set pResponse = ##class(InteropOps.Msg.EvidenceResponse).%New()
    Set pResponse.CaseId = pRequest.CaseId, pResponse.Kind = "ucum"
    Try {
        Set tOut = ..Run(pRequest.CaseId)
        Set pResponse.Status = "ok", pResponse.Summary = tOut.summary, pResponse.FindingsJSON = tOut.findings.%ToJSON()
    } Catch tEx {
        Set tWhy = $EXTRACT(tEx.DisplayString(), 1, 300)
        $$$LOGWARNING("UCUM evidence " _ pRequest.CaseId _ " unavailable: " _ tWhy)
        Set pResponse.Status = "unavailable", pResponse.Summary = "UCUM check unavailable: " _ tWhy
        Set pResponse.FindingsJSON = [{"severity": "warning", "code": "UCUM_UNAVAILABLE", "message": (pResponse.Summary), "count": 0}].%ToJSON()
    }
    Quit $$$OK
}

/// {summary, findings[], obx_checked}. Usable without a production (unit tests, tools).
ClassMethod Run(pCaseId As %String) As %DynamicObject
{
    Set tLookup = ##class(InteropOps.Rules.Data).Lookup(), tN = ##class(InteropOps.Rules.Data).BatchCount(pCaseId)
    Set tAgg = {}, tOrder = [], tObx = 0
    For i = 1:1:tN {
        Set tRaw = ##class(InteropOps.Rules.Data).BatchRaw(pCaseId, i), tSegs = $LENGTH(tRaw, $CHAR(13))
        Set tMsh = $PIECE(tRaw, $CHAR(13)), tDelims = $EXTRACT(tMsh, 5, 8), tMsh10 = $PIECE(tMsh, $EXTRACT(tMsh, 4), 10)
        For s = 1:1:tSegs {
            Set tSeg = $PIECE(tRaw, $CHAR(13), s)
            Continue:$EXTRACT(tSeg, 1, 3)'="OBX"
            Set tObx = tObx + 1
            Set tP = {}.%FromJSON(##class(InteropOps.Py.Ucum).ParseOBX(tSeg, tDelims))
            Set tCode = tP.code.id, tUnit = tP.units.raw, tSet = tP."set_id"
            Set tMeta = tLookup.%Get(tCode), tExp = $SELECT($ISOBJECT(tMeta): tMeta."expected_unit", 1: "")
            Set (tFactor, tBasis, tNote) = ""
            If tCode = "" { Set tVerdict = "code_missing" }
            ElseIf '$ISOBJECT(tMeta) { Set tVerdict = $SELECT(tUnit = "": "code_not_in_lookup+unit_missing", 1: "code_not_in_lookup") }
            ElseIf tUnit = "" { Set tVerdict = "unit_missing" }
            Else {
                Set tKey = tUnit _ "|" _ tExp _ "|" _ tCode
                If '$DATA(tCmp(tKey)) Set tCmp(tKey) = ##class(InteropOps.Py.Ucum).Compare(tUnit, tExp, tCode)
                Set tC = {}.%FromJSON(tCmp(tKey))
                Set tFactor = tC.factor, tBasis = tC.basis, tNote = tC.note
                Set tVerdict = $SELECT(tC."same_unit" && (tUnit = tExp): "same_unit", tC."same_unit" || (tC.convertible && (+tC.factor = 1)): "spelling_variant",
                    tC.convertible && tC."analyte_dependent": "analyte_dependent", tC.convertible: "convertible", 1: "not_convertible")
            }
            Set tK = tCode _ "|" _ tUnit _ "|" _ tExp _ "|" _ tVerdict
            Set tA = tAgg.%Get(tK)
            If '$ISOBJECT(tA) {
                Set tA = {"code": (tCode), "obx": ("OBX[" _ tSet _ "]"), "unit": (tUnit), "expected_unit": (tExp), "verdict": (tVerdict),
                    "severity": ($CASE(tVerdict, "same_unit": "info", "spelling_variant": "info", : "warning")),
                    "count": 0, "flags": {}, "examples": []}
                If tFactor '= "" Do tA.%Set("factor", tFactor, "number"), tA.%Set("basis", tBasis)
                If (tNote '= "") && (tVerdict '= "same_unit") Set tA.note = tNote
                Do tAgg.%Set(tK, tA), tOrder.%Push(tK)
            }
            Set tA.count = tA.count + 1
            Do:(tA.examples.%Size() < 3)&&(tMsh10 '= "")&&(tA.examples.%ToJSON() '[ ("""" _ tMsh10 _ """")) tA.examples.%Push(tMsh10)
            Set tF = tP."abnormal_flags".%GetIterator()
            While tF.%GetNext(, .tFlag) { Continue:(tFlag="")||(tFlag="N")  Do tA.flags.%Set(tFlag, tA.flags.%Get(tFlag) + 1) }
        }
    }
    Set tFindings = [], (tWarn, tInfo) = 0, tIt = tOrder.%GetIterator()
    While tIt.%GetNext(, .tK) {
        Set tA = tAgg.%Get(tK)
        If tA.flags.%ToJSON() = "{}" Do tA.%Remove("flags")
        Do tFindings.%Push(tA)
        If tA.severity = "warning" { Set tWarn = tWarn + tA.count } Else { Set tInfo = tInfo + tA.count }
    }
    Set tSummary = "UCUM: " _ tObx _ " OBX in " _ tN _ " messages; " _ tInfo _ " unit OK vs lookup, " _ tWarn _ " need attention"
    Return {"summary": (tSummary), "findings": (tFindings), "obx_checked": (tObx)}
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="InteropOps.Msg.EvidenceRequest">
    <Method>Check</Method>
  </MapItem>
</MapItems>
}

}
