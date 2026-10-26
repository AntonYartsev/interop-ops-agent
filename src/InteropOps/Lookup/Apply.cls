/// IOA.Lookup.Apply: apply an approved patch_mapping / convert_unit, then reprocess the case batch.
/// patch_mapping : Ens.Util.LookupTable IOA.LabCodeMap  CODE -> LOINC
/// convert_unit  : ^IOA.UnitFactor(CODE, fromUnit) = multiplier (used by InteropOps.Rules.LabToCanonical)
/// Reprocessing = every message of ^IOA.Batch(caseId) is resent through IOA.Reprocess (DTL + validity check),
/// so it shows in the Visual Trace of the session. IOA.Reprocess is a leaf: it never reaches triage, the agent or a Decision row.
Class InteropOps.Lookup.Apply Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As InteropOps.Msg.ApplyRequest, Output pResponse As InteropOps.Msg.ApplyResponse) As %Status
{
    Set pResponse = ##class(InteropOps.Msg.ApplyResponse).%New()
    Set tRes = ..Run(pRequest.CaseId, {}.%FromJSON(pRequest.DecisionJSON), $THIS)
    Set pResponse.ResultJSON = tRes.%ToJSON()
    $$$LOGINFO("apply " _ pRequest.CaseId _ ": " _ pResponse.ResultJSON)
    Return $$$OK
}

ClassMethod Run(pCaseId As %String, pDecision As %DynamicObject, pHost As Ens.BusinessOperation = "") As %DynamicObject
{
    Set tT = pDecision.target, tCode = $ZCONVERT(tT.code, "U")
    If pDecision.action = "patch_mapping" {
        $$$ThrowOnError(##class(Ens.Util.LookupTable).%UpdateValue(##class(InteropOps.Rules.Data).#LOOKUPTABLE, tCode, tT.loinc))
        Set tApplied = tCode _ "->" _ tT.loinc
    } ElseIf pDecision.action = "convert_unit" {
        Set tMult = ##class(InteropOps.Gate.Replay).Multiplier(tT)
        Set ^IOA.UnitFactor(tCode, tT."from_unit") = tMult
        Set tApplied = tCode _ " " _ tT."from_unit" _ " x " _ tMult
    } Else {
        Return {"applied": "", "error": ("nothing to apply for " _ pDecision.action)}
    }
    Return {"applied": (tApplied), "reprocess": (..Reprocess(pCaseId, pHost)), "llm_calls": 0}
}

/// Resend each stored message through IOA.Reprocess (sync). Without a host (direct call) fall back to the plain DTL batch.
ClassMethod Reprocess(pCaseId As %String, pHost As Ens.BusinessOperation) As %DynamicObject
{
    If '$ISOBJECT(pHost) Return ##class(InteropOps.Rules.LabToCanonical).RunBatch(pCaseId)
    Set (tTotal, tOk, tUnmapped, tUnit, tNoMrn) = 0
    For i = 1:1:##class(InteropOps.Rules.Data).BatchCount(pCaseId) {
        Set tIn = ##class(EnsLib.HL7.Message).ImportFromString(##class(InteropOps.Rules.Data).BatchRaw(pCaseId, i), .tSC)
        $$$ThrowOnError(tSC)
        $$$ThrowOnError(pHost.SendRequestSync("IOA.Reprocess", tIn, .tResp))
        Set tR = {}.%FromJSON(tResp.StringValue)
        Set tTotal = tTotal + 1, tUnmapped = tUnmapped + tR."bad_code", tUnit = tUnit + tR."bad_unit", tNoMrn = tNoMrn + tR."no_mrn", tOk = tOk + tR.valid
    }
    Return {"total": (tTotal), "valid": (tOk), "with_unmapped_code": (tUnmapped), "with_unit_mismatch": (tUnit), "missing_mrn_pid3": (tNoMrn), "via": "IOA.Reprocess"}
}

}
