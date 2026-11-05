/// IOA.Gate.Replay: replay gate for a proposed decision (batch checks in InteropOps.Gate.Reference).
/// patch_mapping : reference map_code checks + history replay (DTL output of all 200 historical messages, with and without the patch: 0 may change)
/// convert_unit  : reference convert_unit checks + strict UCUM factor + history replay (same DTL comparison with the proposed factor)
/// quarantine    : >=2 copies, byte-identical copies, no historical message has that MSH-10, and reference no_action check on the batch
/// pass          : not a patch; rejected (final escalate) if the reference no_action check finds ANY unresolved anomaly, except a unit
///                 that differs from the expected unit only in letter case (unit_spelling_variant) with an unchanged value distribution
/// escalate      : not a patch; the reference no_action result is recorded for information only
/// A patch that does not pass the gate is not applied: final_action = escalate.
Class InteropOps.Gate.Replay Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Parameter UCUMTOLERANCE = 0.0025;

Method OnMessage(pRequest As InteropOps.Msg.GateRequest, Output pResponse As InteropOps.Msg.GateResponse) As %Status
{
    Set pResponse = ##class(InteropOps.Msg.GateResponse).%New()
    Set tGate = ..Evaluate(pRequest.CaseId, {}.%FromJSON(pRequest.DecisionJSON))
    Set pResponse.GateStatus = tGate."gate_status", pResponse.FinalAction = tGate."final_action"
    Set pResponse.Summary = ..Summary(tGate), pResponse.GateJSON = tGate.%ToJSON()
    Return $$$OK
}

ClassMethod Evaluate(pCaseId As %String, pDecision As %DynamicObject) As %DynamicObject
{
    Set tAction = pDecision.action
    Set tT = pDecision.target
    Set tReasons = []
    Set tOut = {"action": (tAction), "is_patch": 0, "checks": {}}

    If tAction = "escalate" {
        Set tOut."gate_status" = "NOT_A_PATCH"
        Set tOut."final_action" = tAction
        Set tOut."reference_no_action_info" = ##class(InteropOps.Gate.Reference).Evaluate(pCaseId, {"type": "no_action"})
        Return tOut
    }
    If tAction = "pass" {
        // pass forwards the batch as is: an unmapped code or an empty required field would reach the feed unresolved
        Set tRef = ##class(InteropOps.Gate.Reference).Evaluate(pCaseId, {"type": "no_action"})
        Set tOut."reference_no_action_info" = tRef, tIt = tRef."gate_reasons".%GetIterator()
        While tIt.%GetNext(, .tR) { Do:$EXTRACT(tR, 1, 22)'="unit_spelling_variant:" tReasons.%Push("pass_would_forward:" _ tR) }
        Set tOut."gate_reasons" = tReasons
        Set tOut."gate_status" = $SELECT(tReasons.%Size() = 0: "NOT_A_PATCH", 1: "GATE_REJECTED")
        Set tOut."final_action" = $SELECT(tReasons.%Size() = 0: "pass", 1: "escalate")
        Return tOut
    }
    Set tOut."is_patch" = 1
    If '$ISOBJECT(tT) {
        Do tReasons.%Push("missing_target")
    } ElseIf tAction = "patch_mapping" {
        Set tRef = ##class(InteropOps.Gate.Reference).Evaluate(pCaseId, {"type": "lookup", "change": {"action": "map_code", "from_code": (tT.code), "to_code": (tT.loinc)}})
        Set tOut.reference = tRef
        If tRef."gate_status" '= "GATE_PASSED" Do tReasons.%Push("reference:" _ tRef."gate_reasons".%ToJSON())
        Set tHist = ..HistoryReplay(pDecision)
        Set tOut.checks."history_replay" = tHist
        If tHist.changed || (tHist."invalid_after" > tHist."invalid_before") Do tReasons.%Push("history_changed:" _ tHist.%ToJSON())
    } ElseIf tAction = "convert_unit" {
        Set tMult = ..Multiplier(tT)
        Set tOut.checks."effective_multiplier" = tMult
        Set tRef = ##class(InteropOps.Gate.Reference).Evaluate(pCaseId, {"type": "dtl", "change": {"action": "convert_unit", "code": (tT.code), "from_unit": (tT."from_unit"), "to_unit": (tT."to_unit"), "factor": (tMult)}})
        Set tOut.reference = tRef
        If tRef."gate_status" '= "GATE_PASSED" Do tReasons.%Push("reference:" _ tRef."gate_reasons".%ToJSON())
        Set tUcum = ..StrictUCUM(tT.code, tT."from_unit", tT."to_unit", tMult)
        Set tOut.checks."strict_ucum" = tUcum
        If 'tUcum.ok Do tReasons.%Push("strict_ucum:" _ tUcum.reason)
        Set tHist = ..HistoryReplay(pDecision)
        Set tOut.checks."history_replay" = tHist
        If tHist.changed || (tHist."invalid_after" > tHist."invalid_before") Do tReasons.%Push("history_changed:" _ tHist.%ToJSON())
    } ElseIf tAction = "quarantine" {
        Set tMsh10 = ##class(InteropOps.Util.Ids).NormMSH10(tT.msh10)
        Set tQ = ..CheckQuarantine(pCaseId, tMsh10)
        Set tOut.checks.quarantine = tQ
        If 'tQ.ok Do tReasons.%Push("quarantine:" _ tQ.reason)
        Set tHist = ..HistoryMSH10(tMsh10)
        Set tOut.checks."history_same_msh10" = tHist
        If tHist > 0 Do tReasons.%Push("history_same_msh10:" _ tHist)
        Set tRef = ##class(InteropOps.Gate.Reference).Evaluate(pCaseId, {"type": "no_action"})
        Set tOut.reference = tRef
        If tRef."gate_status" '= "GATE_PASSED" Do tReasons.%Push("reference_batch_not_clean:" _ tRef."gate_reasons".%ToJSON())
    } Else {
        Do tReasons.%Push("action_not_in_closed_list:" _ tAction)
    }
    Set tOut."gate_reasons" = tReasons
    Set tOut."gate_status" = $SELECT(tReasons.%Size() = 0: "GATE_PASSED", 1: "GATE_REJECTED")
    Set tOut."final_action" = $SELECT(tReasons.%Size() = 0: tAction, 1: "escalate")
    Return tOut
}

/// One line for the Decision row (GateResult)
ClassMethod Summary(pGate As %DynamicObject) As %String
{
    Set tS = pGate."gate_status" _ " final=" _ pGate."final_action"
    If $ISOBJECT(pGate."gate_reasons") && pGate."gate_reasons".%Size() Set tS = tS _ " reasons=" _ pGate."gate_reasons".%ToJSON()
    If $ISOBJECT(pGate.checks."history_replay") Set tS = tS _ " history_replay=" _ pGate.checks."history_replay".changed _ "/" _ pGate.checks."history_replay".total _ " changed"
    If $ISOBJECT(pGate.checks."strict_ucum") Set tS = tS _ " ucum=" _ pGate.checks."strict_ucum".%ToJSON()
    If $ISOBJECT(pGate.checks.quarantine) Set tS = tS _ " copies=" _ pGate.checks.quarantine.copies
    Return tS
}

/// Value applied to incoming results: factor (multiply, default) or 1/factor (divide)
ClassMethod Multiplier(pT As %DynamicObject) As %Numeric
{
    Set tF = +pT.factor
    If tF <= 0 Return 0
    Return $SELECT($ZCONVERT(pT.operation, "L") = "divide": 1 / tF, 1: tF)
}

/// Strict UCUM: an entry for (canonical code or *, from_unit, to_unit) must exist with exact, case-sensitive units,
/// to_unit must be the lookup expected unit, and the multiplier must match within UCUMTOLERANCE (relative).
ClassMethod StrictUCUM(pCode As %String, pFrom As %String, pTo As %String, pMult As %Numeric) As %DynamicObject
{
    Set tMeta = ##class(InteropOps.Rules.Data).Lookup().%Get($ZCONVERT(pCode, "U"))
    If '$ISOBJECT(tMeta) Return {"ok": 0, "reason": "unknown_code"}
    If pTo '= tMeta."expected_unit" Return {"ok": 0, "reason": ("to_unit_not_expected_unit:" _ tMeta."expected_unit")}
    Set tIter = ##class(InteropOps.Rules.Data).BaselineDTL()."ucum_conversions".%GetIterator()
    While tIter.%GetNext(.i, .tE) {
        If ((tE."canonical_code" = tMeta."canonical_code") || (tE."canonical_code" = "*")) && (tE."from_unit" '= "") && (tE."from_unit" = pFrom) && (tE."to_unit" = pTo) {
            Set tRel = $ZABS(pMult - tE.factor) / tE.factor
            Return {"ok": (tRel <= ..#UCUMTOLERANCE), "ucum_factor": (tE.factor), "rel_diff": ($FNUMBER(tRel, "", 5)), "reason": ($SELECT(tRel <= ..#UCUMTOLERANCE: "", 1: "factor_mismatch"))}
        }
    }
    Return {"ok": 0, "reason": ("no_ucum_entry:" _ pFrom _ "->" _ pTo)}
}

/// History replay of a patch: run the DTL over every historical message twice, with the current configuration and with the
/// proposed patch (lookup entry or unit factor passed in aux, nothing is written). changed = messages whose DTL output differs;
/// invalid_before / invalid_after = messages that fail LabToCanonical.CheckMessage. A safe patch for a new sender change has changed = 0.
ClassMethod HistoryReplay(pDecision As %DynamicObject) As %DynamicObject
{
    Set tT = pDecision.target, tCode = $ZCONVERT(tT.code, "U")
    Set tBase("lookup") = ##class(InteropOps.Rules.Data).Lookup()
    Set tPatch("lookup") = ##class(InteropOps.Rules.Data).Lookup()
    If pDecision.action = "patch_mapping" {
        Set tMeta = {"canonical_code": (tT.loinc)}, tIt = tBase("lookup").%GetIterator()
        While tIt.%GetNext(, .tM) { If tM."canonical_code" = tT.loinc Set tMeta = tM Quit }
        Do tPatch("lookup").%Set(tCode, tMeta)
    } Else {
        Set tPatch("factor", tCode, tT."from_unit") = ..Multiplier(tT)
    }
    Set (tChanged, tBadBefore, tBadAfter) = 0, tN = ##class(InteropOps.Rules.Data).HistoryCount()
    For i = 1:1:tN {
        Set tIn = ##class(EnsLib.HL7.Message).ImportFromString(##class(InteropOps.Rules.Data).HistoryRaw(i), .tSC)
        $$$ThrowOnError(tSC)
        $$$ThrowOnError(##class(InteropOps.Rules.LabToCanonical).Transform(tIn, .tOutB, .tBase))
        $$$ThrowOnError(##class(InteropOps.Rules.LabToCanonical).Transform(tIn, .tOutP, .tPatch))
        Set tChanged = tChanged + (tOutB.OutputToString() '= tOutP.OutputToString())
        Set tBadBefore = tBadBefore + '##class(InteropOps.Rules.LabToCanonical).CheckMessage(tIn, .tBase).valid
        Set tBadAfter = tBadAfter + '##class(InteropOps.Rules.LabToCanonical).CheckMessage(tIn, .tPatch).valid
    }
    Return {"total": (tN), "changed": (tChanged), "invalid_before": (tBadBefore), "invalid_after": (tBadAfter)}
}

/// Historical messages with this MSH-10 (a quarantine of that id would also hold them)
ClassMethod HistoryMSH10(pKey As %String) As %Integer
{
    Set tN = 0
    For i = 1:1:##class(InteropOps.Rules.Data).HistoryCount() {
        Set tN = tN + (##class(InteropOps.Util.Ids).NormMSH10(##class(InteropOps.Rules.Data).MSH10(##class(InteropOps.Rules.Data).HistoryRaw(i))) = pKey)
    }
    Return tN
}

/// >=2 copies of pMsh10 in the batch, all byte-identical (ids compared in canonical form)
ClassMethod CheckQuarantine(pCaseId As %String, pMsh10 As %String) As %DynamicObject
{
    Set tCount = 0, tFirst = "", tSame = 1, tKey = ##class(InteropOps.Util.Ids).NormMSH10(pMsh10)
    For i = 1:1:##class(InteropOps.Rules.Data).BatchCount(pCaseId) {
        Set tRaw = ##class(InteropOps.Rules.Data).BatchRaw(pCaseId, i)
        Continue:##class(InteropOps.Util.Ids).NormMSH10(##class(InteropOps.Rules.Data).MSH10(tRaw))'=tKey
        Set tCount = tCount + 1
        If tCount = 1 { Set tFirst = tRaw } ElseIf tRaw '= tFirst { Set tSame = 0 }
    }
    If tCount < 2 Return {"ok": 0, "copies": (tCount), "reason": "fewer_than_2_copies"}
    If 'tSame Return {"ok": 0, "copies": (tCount), "reason": "copies_not_identical_would_drop_data"}
    Return {"ok": 1, "copies": (tCount), "reason": ""}
}

}
