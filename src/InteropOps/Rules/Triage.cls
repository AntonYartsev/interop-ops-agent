/// Deterministic anomaly ticket. The batch / history summaries, lookup and baseline DTL are parameters (computed from the received batch).
/// Contains no hardcoded test codes, segment names or field numbers.
Class InteropOps.Rules.Triage
{

/// Structured anomaly ticket for one batch
ClassMethod Inspect(pCaseId As %String, tDrift As %DynamicObject, tHist As %DynamicObject, tLookup As %DynamicObject, tDTL As %DynamicObject) As %DynamicObject
{
    Set tAnomalies = []
    Set tFocusList = []
    Set tTotalMsgs = +tDrift.%Get("total_messages")

    // 1. Required field empty in all messages, with the best sibling candidate
    Set tReqIter = tDrift.%Get("required_field_stats").%GetIterator()
    While tReqIter.%GetNext(.tReqName, .tReqInfo) {
        Set tSrcField = tReqInfo.%Get("source_field")
        Continue:+tReqInfo.%Get("source_non_empty")'=0
        Set tBestSibling = "", tBestCount = 0
        Set tSibIter = tReqInfo.%Get("candidate_siblings").%GetIterator()
        While tSibIter.%GetNext(.tSibField, .tSibInfo) {
            If +tSibInfo.%Get("regex_matches") > tBestCount Set tBestCount = +tSibInfo.%Get("regex_matches"), tBestSibling = tSibField
        }
        Do tAnomalies.%Push({
            "category": "empty_required_field",
            "target_field": (tReqName),
            "field": (tSrcField),
            "candidate_sibling": (tBestSibling),
            "affected_count": (tBestCount),
            "total_messages": (tTotalMsgs),
            "details": ("Required field " _ tSrcField _ " (" _ tReqName _ ") is empty in all drift messages" _ $SELECT(tBestSibling '= "": "; valid format matches found in sibling field " _ tBestSibling, 1: ""))
        })
        Do tFocusList.%Push("empty_required_field:" _ tSrcField)
    }

    // 2. Unmapped (non-standard) segments
    Set tSegIter = tDrift.%Get("non_standard_segments").%GetIterator()
    While tSegIter.%GetNext(.tSegName, .tSegInfo) {
        Do tAnomalies.%Push({
            "category": "unmapped_segment",
            "segment": (tSegName),
            "count": (tSegInfo.%Get("count")),
            "field_examples": (tSegInfo.%Get("field_examples")),
            "available_target_fields": (tDTL.%Get("optional_target_fields")),
            "details": ("Unknown segment " _ tSegName _ " present in drift messages and not mapped in baseline DTL")
        })
        Do tFocusList.%Push("unmapped_segment:" _ tSegName)
    }

    // 3. Unmapped codes and unit / value distribution shifts
    Set tDriftCodes = tDrift.%Get("code_stats")
    Set tHistCodes = tHist.%Get("code_stats")
    Set tShiftedCodes = []
    Set tCodeIter = tDriftCodes.%GetIterator()
    While tCodeIter.%GetNext(.tCodeName, .tCodeStats) {
        If 'tLookup.%IsDefined(tCodeName) {
            // Unknown code: is a historical panel counterpart missing from this batch?
            Set tMissingPanelCodes = []
            Set tDriftCoCodes = tCodeStats.%Get("co_occurring_codes")
            If $ISOBJECT(tDriftCoCodes) && (tDriftCoCodes.%Size() > 0) {
                Set tHistIter = tHistCodes.%GetIterator()
                While tHistIter.%GetNext(.hCode, .hStats) {
                    Continue:tDriftCodes.%IsDefined(hCode)
                    If ..ArraysOverlap(tDriftCoCodes, hStats.%Get("co_occurring_codes")) {
                        Set tHMeta = tLookup.%Get(hCode)
                        Do tMissingPanelCodes.%Push({
                            "code": (hCode),
                            "canonical_code": ($SELECT($ISOBJECT(tHMeta): tHMeta.%Get("canonical_code"), 1: "")),
                            "name": (hStats.%Get("description")),
                            "expected_unit": ($SELECT($ISOBJECT(tHMeta): tHMeta.%Get("expected_unit"), 1: "")),
                            "history_median": (hStats.%Get("median"))
                        })
                    }
                }
            }
            Do tAnomalies.%Push({
                "category": "unmapped_code",
                "code": (tCodeName),
                "count": (tCodeStats.%Get("count")),
                "description": (tCodeStats.%Get("description")),
                "drift_units": (tCodeStats.%Get("units")),
                "drift_median": (tCodeStats.%Get("median")),
                "co_occurring_codes": (tDriftCoCodes),
                "missing_panel_codes": (tMissingPanelCodes),
                "details": ($SELECT(tMissingPanelCodes.%Size() > 0: "Unknown code " _ tCodeName _ " appears in panel where historical code " _ tMissingPanelCodes.%Get(0).%Get("code") _ " is absent", 1: "Unknown code " _ tCodeName _ " is a brand-new test code added to panel while all existing panel codes remain present"))
            })
            Do tFocusList.%Push("unmapped_code:" _ tCodeName)
        } Else {
            // Known code: unit mismatch or median shift (>15%)
            Set tMeta = tLookup.%Get(tCodeName)
            Set tExpUnit = tMeta.%Get("expected_unit")
            Set tCanonCode = tMeta.%Get("canonical_code")
            Set tHistCode = tHistCodes.%Get(tCodeName)
            Set tUnitMismatch = 0, tDriftUnit = tExpUnit
            Set tDriftUnitsIter = tCodeStats.%Get("units").%GetIterator()
            While tDriftUnitsIter.%GetNext(.uName, .uCount) {
                If uName '= tExpUnit Set tUnitMismatch = 1, tDriftUnit = uName
            }
            Set tHMed = +$SELECT($ISOBJECT(tHistCode): tHistCode.%Get("median"), 1: 0)
            Set tDMed = +tCodeStats.%Get("median")
            Set tRatio = 0
            If (tDMed > 0) && (tHMed > 0) Set tRatio = +$FNUMBER(tHMed / tDMed, "", 4)
            Set tRelShift = 0
            If tHMed > 0 Set tRelShift = +$FNUMBER($ZABS(tDMed - tHMed) / tHMed, "", 4)
            If tUnitMismatch || (tRelShift > 0.15) {
                Do tShiftedCodes.%Push({
                    "code": (tCodeName),
                    "canonical_code": (tCanonCode),
                    "drift_unit": (tDriftUnit),
                    "expected_unit": (tExpUnit),
                    "unit_changed": (tUnitMismatch),
                    "history_median": (tHMed),
                    "drift_median": (tDMed),
                    "ratio_hist_over_drift": (tRatio),
                    "rel_shift": (tRelShift),
                    "ucum_factor": (..LookupUCUMFactor(tDTL, tCanonCode, tDriftUnit, tExpUnit))
                })
            }
        }
    }

    If tShiftedCodes.%Size() = 1 {
        Set tItem = tShiftedCodes.%Get(0)
        Do tAnomalies.%Push({
            "category": "unit_or_value_shift",
            "code": (tItem.%Get("code")),
            "canonical_code": (tItem.%Get("canonical_code")),
            "drift_unit": (tItem.%Get("drift_unit")),
            "expected_unit": (tItem.%Get("expected_unit")),
            "unit_changed": (tItem.%Get("unit_changed")),
            "history_median": (tItem.%Get("history_median")),
            "drift_median": (tItem.%Get("drift_median")),
            "ratio_hist_over_drift": (tItem.%Get("ratio_hist_over_drift")),
            "ucum_factor": (tItem.%Get("ucum_factor")),
            "details": ("Code " _ tItem.%Get("code") _ " shifted median from " _ tItem.%Get("history_median") _ " (" _ tItem.%Get("expected_unit") _ ") to " _ tItem.%Get("drift_median") _ " (" _ tItem.%Get("drift_unit") _ ")")
        })
        Do tFocusList.%Push("unit_or_value_shift:" _ tItem.%Get("code"))
    } ElseIf tShiftedCodes.%Size() > 1 {
        Set tCodesArr = []
        For i = 0:1:tShiftedCodes.%Size()-1 Do tCodesArr.%Push(tShiftedCodes.%Get(i).%Get("code"))
        Do tAnomalies.%Push({
            "category": "multi_code_value_shift",
            "codes": (tCodesArr),
            "shifted_details": (tShiftedCodes),
            "details": "Simultaneous distribution shifts across multiple panel codes"
        })
        Do tFocusList.%Push("multi_code_value_shift:" _ tCodesArr.%ToJSON())
    }

    Set tFocusStr = "none"
    For i = 0:1:tFocusList.%Size()-1 Set tFocusStr = $SELECT(i = 0: "", 1: tFocusStr _ "; ") _ tFocusList.%Get(i)
    Return {"scenario_id": (pCaseId), "focus": (tFocusStr), "anomaly_count": (tAnomalies.%Size()), "anomalies": (tAnomalies)}
}

/// Conversion factor from baseline_dtl.ucum_conversions (canonical code or "*"), 0 if none
ClassMethod LookupUCUMFactor(pDTL As %DynamicObject, pCanonCode As %String, pFromUnit As %String, pToUnit As %String) As %Numeric
{
    If pFromUnit = pToUnit Return 0
    Set tIter = pDTL.%Get("ucum_conversions").%GetIterator()
    While tIter.%GetNext(.idx, .tEntry) {
        Set tC = tEntry.%Get("canonical_code")
        If ((tC = pCanonCode) || (tC = "*")) && ($ZCONVERT(tEntry.%Get("from_unit"), "L") = $ZCONVERT(pFromUnit, "L")) && ($ZCONVERT(tEntry.%Get("to_unit"), "L") = $ZCONVERT(pToUnit, "L")) {
            Return +tEntry.%Get("factor")
        }
    }
    Return 0
}

/// At least 2 common elements
ClassMethod ArraysOverlap(arr1 As %DynamicArray, arr2 As %DynamicArray) As %Boolean
{
    If '$ISOBJECT(arr1) || '$ISOBJECT(arr2) Return 0
    Set count = 0
    For i = 0:1:arr1.%Size()-1 {
        For j = 0:1:arr2.%Size()-1 {
            If arr2.%Get(j) = arr1.%Get(i) Set count = count + 1
        }
    }
    Return (count >= 2)
}

}
