/// IOA.Lookup.Apply: apply an approved patch_mapping / convert_unit, then reprocess the case batch.
/// patch_mapping : Ens.Util.LookupTable IOA.LabCodeMap  CODE -> LOINC
/// convert_unit  : ^IOA.UnitFactor(CODE, fromUnit) = multiplier (used by InteropOps.Rules.LabToCanonical)
/// Reprocessing = every message of ^IOA.Batch(caseId) is resent through IOA.Reprocess (DTL + validity check),
/// so it shows in the Visual Trace of the session. IOA.Reprocess is a leaf: it never reaches triage, the agent or a Decision row.
/// If any message is still invalid after the patch, the patch is rolled back and the result has an error (the case ends escalated).
/// If the stored batch is not the batch that was reviewed (BatchSHA differs), nothing is applied.
/// If the lookup entry (or unit factor) got another value after the gate, nothing is applied. If reprocess fails with an error, the patch is rolled back.
Class InteropOps.Lookup.Apply Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As InteropOps.Msg.ApplyRequest, Output pResponse As InteropOps.Msg.ApplyResponse) As %Status
{
    Set pResponse = ##class(InteropOps.Msg.ApplyResponse).%New()
    If pRequest.TaskId '= "" {
        Set tN = 0
        &sql(SELECT COUNT(*) INTO :tN FROM InteropOps_Data.Decision WHERE TaskId = :pRequest.TaskId)
        If SQLCODE < 0 {
            Set pResponse.ResultJSON = {"applied": "", "error": ("sql " _ SQLCODE _ " " _ $GET(%msg))}.%ToJSON()
            Return $$$OK
        }
        If 'tN {
            Set pResponse.ResultJSON = {"applied": "", "skipped": "no Decision row for task (purged)"}.%ToJSON()
            $$$LOGWARNING("apply " _ pRequest.CaseId _ " skipped: " _ pResponse.ResultJSON)
            Return $$$OK
        }
    }
    Try {
        Set tRes = ..Run(pRequest.CaseId, {}.%FromJSON(pRequest.DecisionJSON), $THIS, pRequest.BatchSHA)
    } Catch tEx {
        Set tRes = {"applied": "", "error": ($EXTRACT(tEx.DisplayString(), 1, 500))}
    }
    Set pResponse.ResultJSON = tRes.%ToJSON()
    $$$LOGINFO("apply " _ pRequest.CaseId _ ": " _ pResponse.ResultJSON)
    Return $$$OK
}

ClassMethod Run(pCaseId As %String, pDecision As %DynamicObject, pHost As Ens.BusinessOperation = "", pBatchSHA As %String = "") As %DynamicObject
{
    // the reviewer approved a decision for one batch: if the batch was replaced since (same CaseId sent again), apply nothing
    If (pBatchSHA '= "") && (pBatchSHA '= ##class(InteropOps.Rules.Data).BatchSHA(pCaseId)) {
        Return {"applied": "", "error": ("batch_changed: batch " _ pCaseId _ " is not the batch that was reviewed, nothing applied")}
    }
    Set tT = pDecision.target, tCode = $ZCONVERT(tT.code, "U"), tTable = ##class(InteropOps.Rules.Data).#LOOKUPTABLE
    If pDecision.action = "patch_mapping" {
        Set tOld = $GET(^Ens.LookupTable(tTable, tCode)), tNew = tT.loinc, tApplied = tCode _ "->" _ tNew
    } ElseIf pDecision.action = "convert_unit" {
        Set tOld = $GET(^IOA.UnitFactor(tCode, tT."from_unit")), tNew = ##class(InteropOps.Gate.Replay).Multiplier(tT)
        Set tApplied = tCode _ " " _ tT."from_unit" _ " x " _ tNew
    } Else {
        Return {"applied": "", "error": ("nothing to apply for " _ pDecision.action)}
    }
    // the gate checked the patch against the lookup as it was then (no entry for the code): if another value was set
    // while the task waited, the gate result is out of date, so apply nothing
    If (tOld '= "") && (tOld '= tNew) {
        Return {"applied": "", "error": ("lookup_changed: " _ tCode _ " is " _ tOld _ " now, not the state the gate checked, nothing applied")}
    }
    Do ..Set(pDecision.action, tTable, tCode, tT."from_unit", tNew)
    Try {
        Set tRe = ..Reprocess(pCaseId, pHost)
    } Catch tEx {
        // reprocess did not finish: the patch must not stay applied for a case that ends escalated
        Do ..Set(pDecision.action, tTable, tCode, tT."from_unit", tOld)
        Return {"applied": "", "rolled_back": (tApplied), "llm_calls": 0, "error": ("reprocess_error: " _ $EXTRACT(tEx.DisplayString(), 1, 300) _ ", patch rolled back")}
    }
    If tRe.valid = tRe.total Return {"applied": (tApplied), "reprocess": (tRe), "llm_calls": 0}
    // not every message of the batch is valid after the patch: roll the patch back, the case ends escalated
    Do ..Set(pDecision.action, tTable, tCode, tT."from_unit", tOld)
    Return {"applied": "", "rolled_back": (tApplied), "reprocess": (tRe), "llm_calls": 0,
        "error": ("reprocess_failed: " _ tRe.valid _ "/" _ tRe.total _ " messages valid after " _ tApplied _ ", patch rolled back")}
}

/// Write (pValue '= "") or remove (pValue = "") the lookup entry or the unit factor
ClassMethod Set(pAction As %String, pTable As %String, pCode As %String, pFromUnit As %String, pValue As %String) [ Private ]
{
    If pAction = "patch_mapping" {
        If pValue = "" { $$$ThrowOnError(##class(Ens.Util.LookupTable).%RemoveValue(pTable, pCode)) } Else { $$$ThrowOnError(##class(Ens.Util.LookupTable).%UpdateValue(pTable, pCode, pValue)) }
    } ElseIf pValue = "" {
        Kill ^IOA.UnitFactor(pCode, pFromUnit)
    } Else {
        Set ^IOA.UnitFactor(pCode, pFromUnit) = pValue
    }
}

/// Resend each stored message through IOA.Reprocess (sync). Without a host (direct call) fall back to the plain DTL batch.
ClassMethod Reprocess(pCaseId As %String, pHost As Ens.BusinessOperation) As %DynamicObject
{
    If '$ISOBJECT(pHost) Return ##class(InteropOps.Rules.LabToCanonical).RunBatch(pCaseId)
    Set (tTotal, tOk, tUnmapped, tUnit, tRange, tNoMrn) = 0
    For i = 1:1:##class(InteropOps.Rules.Data).BatchCount(pCaseId) {
        Set tIn = ##class(EnsLib.HL7.Message).ImportFromString(##class(InteropOps.Rules.Data).BatchRaw(pCaseId, i), .tSC)
        $$$ThrowOnError(tSC)
        $$$ThrowOnError(pHost.SendRequestSync("IOA.Reprocess", tIn, .tResp))
        Set tR = {}.%FromJSON(tResp.StringValue)
        Set tTotal = tTotal + 1, tUnmapped = tUnmapped + tR."bad_code", tUnit = tUnit + tR."bad_unit", tRange = tRange + tR."bad_range", tNoMrn = tNoMrn + tR."no_mrn", tOk = tOk + tR.valid
    }
    Return {"total": (tTotal), "valid": (tOk), "with_unmapped_code": (tUnmapped), "with_unit_mismatch": (tUnit), "with_range_mismatch": (tRange), "missing_mrn_pid3": (tNoMrn), "via": "IOA.Reprocess"}
}

}
