/// Reference-free replay gate. Batch/history summaries, lookup and DTL come from InteropOps.Rules.Data (computed from the
/// received batch). Patch shapes: {"type":"no_action"}, {"type":"lookup","change":{"action":"map_code",...}},
/// {"type":"dtl","change":{"action":"convert_unit",...}}.
Class InteropOps.Gate.Reference
{

Parameter MEDIANTOLERANCE = 0.15;

ClassMethod Evaluate(pCaseId As %String, pPatch As %DynamicObject) As %DynamicObject
{
    Set tType = $ZCONVERT($ZSTRIP(pPatch.%Get("type"), "<>W"), "L")
    Set tHist = ##class(InteropOps.Rules.Data).HistorySummary()
    Set tDrift = ##class(InteropOps.Rules.Data).BatchSummary(pCaseId)
    Set tLookup = ##class(InteropOps.Rules.Data).Lookup()

    Set tReasons = []
    Set tHistoryBroken = 0
    Set tMappedUnknownCodes = {}
    Set tConvertedCodes = {}
    Set tChangedSomething = 0
    Set tChecks = ""

    Set cObj = pPatch.%Get("change")
    If $ISOBJECT(cObj) {
        Set tAction = $ZCONVERT(cObj.%Get("action"), "L")
        If (tType = "lookup") || (tAction = "map_code") {
            Set tFrom = $ZCONVERT($ZSTRIP(cObj.%Get("from_code"), "<>W"), "U")
            Set tTo = $ZCONVERT($ZSTRIP(cObj.%Get("to_code"), "<>W"), "U")
            Do {
                If (tFrom = "") || (tTo = "") { Do tReasons.%Push("invalid_map_code_empty") Quit }
                If tLookup.%IsDefined(tFrom) {
                    Set tHistoryBroken = 200
                    Do tReasons.%Push("history_regression:overwrote_existing_code:" _ tFrom)
                    Quit
                }
                // Resolve target local code if canonical LOINC was supplied
                If 'tLookup.%IsDefined(tTo) {
                    Set tLIter = tLookup.%GetIterator()
                    While tLIter.%GetNext(.lKey, .lVal) {
                        If lVal.%Get("canonical_code") = tTo Set tTo = lKey Quit
                    }
                }
                If 'tLookup.%IsDefined(tTo) { Do tReasons.%Push("map_code_unknown_target:" _ tTo) Quit }
                // target code must NOT already be present in the batch
                If tDrift.%Get("code_stats").%IsDefined(tTo) { Do tReasons.%Push("duplicate_canonical_code_collision:" _ tFrom _ "->" _ tTo) Quit }
                Set tDStat = tDrift.%Get("code_stats").%Get(tFrom)
                If '$ISOBJECT(tDStat) { Do tReasons.%Push("no_op_map_code_not_in_drift:" _ tFrom) Quit }
                Set tExpUnit = tLookup.%Get(tTo).%Get("expected_unit")
                // every message of the batch must send the mapped code in the expected unit, not just one of them
                If ..OtherUnits(tDStat.%Get("units"), tExpUnit) '= "" { Do tReasons.%Push("unit_mismatch_on_mapped_code:" _ tFrom _ "!=" _ tExpUnit) Quit }
                Set tHMed = ..HistMedian(tHist, tTo)
                Set tDMed = +tDStat.%Get("median")
                Set tChecks = {"code": (tFrom), "description": (tDStat.%Get("description")), "results": (tDStat.%Get("count")), "messages": (##class(InteropOps.Rules.Data).BatchCount(pCaseId)),
                    "history_results": (..HistCount(tHist, tFrom)), "target_local": (tTo), "target_loinc": (tLookup.%Get(tTo).%Get("canonical_code")), "target_name": (tLookup.%Get(tTo).%Get("canonical_name")),
                    "units": (tDStat.%Get("units")), "expected_unit": (tExpUnit), "batch_median": (tDMed), "history_median": (tHMed), "median_limit": (..#MEDIANTOLERANCE), "target_absent_in_batch": 1}
                If (tHMed > 0) && (($ZABS(tDMed - tHMed) / tHMed) > ..#MEDIANTOLERANCE) { Do tReasons.%Push("distribution_mismatch_on_mapped_code:" _ tFrom _ "->" _ tTo) Quit }
                Do tMappedUnknownCodes.%Set(tFrom, tTo)
                Set tChangedSomething = 1
            } While 0
        } ElseIf (tType = "dtl") && (tAction = "convert_unit") {
            Set tCode = $ZCONVERT($ZSTRIP(cObj.%Get("code"), "<>W"), "U")
            Set tFactor = +cObj.%Get("factor")
            Set tFromU = cObj.%Get("from_unit")
            Set tConvFrom = tFromU
            Do {
                If 'tLookup.%IsDefined(tCode) || (tFactor <= 0) { Do tReasons.%Push("invalid_convert_unit:" _ tCode) Quit }
                If $ZCONVERT(tFromU, "L") = $ZCONVERT(tLookup.%Get(tCode).%Get("expected_unit"), "L") {
                    Set tHistoryBroken = 100
                    Do tReasons.%Push("history_regression:convert_unit_alters_expected_unit:" _ tCode)
                    Quit
                }
                Set tDStat = tDrift.%Get("code_stats").%Get(tCode)
                If '$ISOBJECT(tDStat) { Do tReasons.%Push("no_op_convert_unit:" _ tCode) Quit }
                Set tHMed = ..HistMedian(tHist, tCode)
                Set tDMed = +tDStat.%Get("median") * tFactor
                Set tChecks = {"code": (tCode), "results": (tDStat.%Get("count")), "messages": (##class(InteropOps.Rules.Data).BatchCount(pCaseId)), "history_results": (..HistCount(tHist, tCode)),
                    "units": (tDStat.%Get("units")), "from_unit": (tFromU), "expected_unit": (tLookup.%Get(tCode).%Get("expected_unit")), "factor": (tFactor),
                    "batch_median_before": (+tDStat.%Get("median")), "batch_median_after": (tDMed), "history_median": (tHMed), "median_limit": (..#MEDIANTOLERANCE)}
                If (tHMed > 0) && (($ZABS(tDMed - tHMed) / tHMed) > ..#MEDIANTOLERANCE) { Do tReasons.%Push("distribution_mismatch_after_convert_unit:" _ tCode) Quit }
                Do tConvertedCodes.%Set(tCode, tFactor)
                Set tChangedSomething = 1
            } While 0
        }
    }

    If (tType '= "no_action") && (tType '= "none") && ('tChangedSomething) Do tReasons.%Push("no_op_patch")

    // No unresolved anomaly may remain in ANY message of the batch
    Set tTotal = ##class(InteropOps.Rules.Data).BatchCount(pCaseId)
    Set tReqIter = tDrift.%Get("required_field_stats").%GetIterator()
    While tReqIter.%GetNext(.rName, .rInfo) {
        If +rInfo.%Get("source_non_empty") < tTotal Do tReasons.%Push("unresolved_required_field:" _ rName _ ":" _ (tTotal - rInfo.%Get("source_non_empty")) _ "/" _ tTotal)
    }
    Set tZIter = tDrift.%Get("non_standard_segments").%GetIterator()
    While tZIter.%GetNext(.zName, .zInfo) { Do tReasons.%Push("unresolved_segment:" _ zName) }
    Set tCIter = tDrift.%Get("code_stats").%GetIterator()
    While tCIter.%GetNext(.cName, .cInfo) {
        If 'tLookup.%IsDefined(cName) {
            If 'tMappedUnknownCodes.%IsDefined(cName) Do tReasons.%Push("unresolved_unmapped_code:" _ cName)
        } ElseIf tConvertedCodes.%IsDefined(cName) {
            // a converted code may arrive only in the converted unit or already in the expected unit
            Set tOther = ..OtherUnits(cInfo.%Get("units"), tLookup.%Get(cName).%Get("expected_unit"), $GET(tConvFrom))
            If tOther '= "" Do tReasons.%Push("unresolved_unit_mismatch:" _ cName _ ":" _ tOther)
        } Else {
            Set tExp = tLookup.%Get(cName).%Get("expected_unit"), tOther = ..OtherUnits(cInfo.%Get("units"), tExp)
            // a unit that differs from the expected unit only in letter case (mg/dl for mg/dL) is reported apart,
            // so that "pass" may accept it (Gate.Replay) when the value distribution is unchanged
            If tOther '= "" Do tReasons.%Push($SELECT(..OtherUnits(cInfo.%Get("units"), $ZCONVERT(tExp, "L"), "", 1) = "": "unit_spelling_variant:", 1: "unresolved_unit_mismatch:") _ cName _ ":" _ tOther)
            Set tHMed = ..HistMedian(tHist, cName)
            Set tDMed = +cInfo.%Get("median")
            If (tHMed > 0) && (($ZABS(tDMed - tHMed) / tHMed) > ..#MEDIANTOLERANCE) Do tReasons.%Push("unresolved_distribution_shift:" _ cName)
        }
    }

    Set tPassed = (tReasons.%Size() = 0)
    Return {
        "gate_status": ($SELECT(tPassed: "GATE_PASSED", 1: "GATE_REJECTED")),
        "workflow_action": ($SELECT('tPassed: "REJECTED_BY_REFERENCE_FREE_GATE", (tType = "no_action") || (tType = "none"): "APPROVED_NO_ACTION", 1: "APPROVED_FOR_WORKFLOW")),
        "history_broken": (tHistoryBroken),
        "drift_valid": (tPassed),
        "distribution_match": (tPassed),
        "gate_reasons": (tReasons),
        "checks": ($SELECT($ISOBJECT(tChecks): tChecks, 1: {}))
    }
}


/// Units in pUnits (unit -> count) other than pExpected and pAlso, comma-separated ("" if none). pNoCase: compare lower case.
ClassMethod OtherUnits(pUnits As %DynamicObject, pExpected As %String, pAlso As %String = "", pNoCase As %Boolean = 0) As %String
{
    Set tOut = "", tIt = pUnits.%GetIterator()
    While tIt.%GetNext(.tU) {
        Set tCmp = $SELECT(pNoCase: $ZCONVERT(tU, "L"), 1: tU)
        Continue:(tCmp=pExpected)||((pAlso'="")&&(tCmp=pAlso))
        Set tOut = tOut _ $SELECT(tOut = "": "", 1: ",") _ tU
    }
    Return tOut
}

/// Results of a code in the history summary (0 for a code that never occurs there)
ClassMethod HistCount(pHist As %DynamicObject, pCode As %String) As %Integer
{
    Set tCS = pHist.%Get("code_stats")
    Quit:'$ISOBJECT(tCS) 0
    Set tS = tCS.%Get(pCode)
    Quit:'$ISOBJECT(tS) 0
    Quit +tS.%Get("count")
}

/// Median of a code in the history summary; 0 when the code has no history (new local codes such as SOD/HB)
ClassMethod HistMedian(pHist As %DynamicObject, pCode As %String) As %Numeric
{
    Set tCS = pHist.%Get("code_stats")
    Quit:'$ISOBJECT(tCS) 0
    Set tS = tCS.%Get(pCode)
    Quit:'$ISOBJECT(tS) 0
    Quit +tS.%Get("median")
}

}
