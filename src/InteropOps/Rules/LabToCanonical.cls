/// Baseline DTL for the synthetic REGIONAL_LAB feed: OBX-3 local code -> LOINC^name^LN
/// from IOA.LabCodeMap. Unmapped codes keep their local coding (OBX-3.3 = L). The BPL counts what the DTL could not handle.
Class InteropOps.Rules.LabToCanonical Extends Ens.DataTransform
{

ClassMethod Transform(source As EnsLib.HL7.Message, ByRef target As EnsLib.HL7.Message, ByRef aux) As %Status
{
    Set target = source.%ConstructClone(1)
    Set tLookup = $GET(aux("lookup"))
    Set:'$ISOBJECT(tLookup) tLookup = ##class(InteropOps.Rules.Data).Lookup()
    For i = 1:1:target.SegCount {
        Set tSeg = target.GetSegmentAt(i)
        Continue:tSeg.Name'="OBX"
        Set tMeta = tLookup.%Get($ZCONVERT(tSeg.GetValueAt("3.1"), "U"))
        Continue:'$ISOBJECT(tMeta)
        Set tSeg = target.GetMutableSegmentAt(i)
        Set tCode = $ZCONVERT(tSeg.GetValueAt("3.1"), "U")
        Do tSeg.SetValueAt(tMeta."canonical_code" _ "^" _ tMeta."canonical_name" _ "^LN", 3)
        // unit conversion approved by IOA.Lookup.Apply: ^IOA.UnitFactor(CODE, fromUnit) = multiplier
        // (aux("factor", CODE, fromUnit) overrides it: the gate replays a proposed factor over history without applying it)
        Set tFrom = tSeg.GetValueAt(6)
        // a unit that differs from the expected unit only in letter case (mg/dl for mg/dL) is the same UCUM unit: write the expected spelling
        If (tFrom '= tMeta."expected_unit") && ($ZCONVERT(tFrom, "L") = $ZCONVERT(tMeta."expected_unit", "L")) {
            Do tSeg.SetValueAt(tMeta."expected_unit", 6)
            Set tFrom = tMeta."expected_unit"
        }
        Set tF = $GET(aux("factor", tCode, tFrom), $GET(^IOA.UnitFactor(tCode, tFrom)))
        If (tFrom '= tMeta."expected_unit") && (tF '= "") && $ISVALIDNUM(tSeg.GetValueAt(5)) {
            Do tSeg.SetValueAt(+$FNUMBER(tSeg.GetValueAt(5) * tF, "", 6), 5), tSeg.SetValueAt(tMeta."expected_unit", 6)
            // OBX-7 reference range "low-high" is converted with the same factor, so value, unit and range agree
            Set tRange = tSeg.GetValueAt(7)
            If ($LENGTH(tRange, "-") = 2) && $ISVALIDNUM($PIECE(tRange, "-")) && $ISVALIDNUM($PIECE(tRange, "-", 2)) {
                Do tSeg.SetValueAt(+$FNUMBER($PIECE(tRange, "-") * tF, "", 2) _ "-" _ +$FNUMBER($PIECE(tRange, "-", 2) * tF, "", 2), 7)
            }
        }
        Do target.SetSegmentAt(tSeg, i)
    }
    Return $$$OK
}

/// DTL + validity check of ONE message: {bad_code, bad_unit, bad_range, no_mrn, valid}.
/// bad_range: OBX-7 "low-high" differs from the lookup ref_range by more than RANGETOLERANCE (relative) on a bound,
/// for example a range left in mg/dL after the value was converted to mmol/L.
ClassMethod CheckMessage(pIn As EnsLib.HL7.Message, ByRef pAux) As %DynamicObject
{
    Set tLookup = $GET(pAux("lookup"))
    Set:'$ISOBJECT(tLookup) tLookup = ##class(InteropOps.Rules.Data).Lookup(), pAux("lookup") = tLookup
    $$$ThrowOnError(..Transform(pIn, .tOut, .pAux))
    Set (tBadCode, tBadUnit, tBadRange) = 0, tPid3 = ""
    For s = 1:1:tOut.SegCount {
        Set tSeg = tOut.GetSegmentAt(s)
        If tSeg.Name = "PID" Set tPid3 = tSeg.GetValueAt(3)
        Continue:tSeg.Name'="OBX"
        If tSeg.GetValueAt("3.3") '= "LN" { Set tBadCode = 1 Continue }
        Set tMeta = tLookup.%Get($ZCONVERT(pIn.GetSegmentAt(s).GetValueAt("3.1"), "U"))
        If $ISOBJECT(tMeta) && (tSeg.GetValueAt(6) '= tMeta."expected_unit") Set tBadUnit = 1
        If $ISOBJECT(tMeta) && '..RangeAgrees(tSeg.GetValueAt(7), tMeta."ref_range") Set tBadRange = 1
    }
    Return {"bad_code": (tBadCode), "bad_unit": (tBadUnit), "bad_range": (tBadRange), "no_mrn": (tPid3 = ""),
        "valid": ('tBadCode && 'tBadUnit && 'tBadRange && (tPid3 '= ""))}
}

Parameter RANGETOLERANCE = 0.5;

/// True if the OBX-7 range is empty or not "low-high", or both bounds are within RANGETOLERANCE of the lookup range.
ClassMethod RangeAgrees(pRange As %String, pRef As %String) As %Boolean
{
    Return:($LENGTH(pRange, "-") '= 2)||($LENGTH(pRef, "-") '= 2) 1
    For i = 1, 2 {
        Set tGot = $PIECE(pRange, "-", i), tWant = $PIECE(pRef, "-", i)
        Return:'$ISVALIDNUM(tGot)||'$ISVALIDNUM(tWant)||(tWant = 0) 1
        Return:(($ZABS(tGot - tWant) / tWant) > ..#RANGETOLERANCE) 0
    }
    Return 1
}

/// Run the DTL over the case batch and summarize what it could not handle.
ClassMethod RunBatch(pCaseId As %String) As %DynamicObject
{
    Set tAux("lookup") = ##class(InteropOps.Rules.Data).Lookup()
    Set (tTotal, tOk, tUnmapped, tUnit, tRange, tNoMrn) = 0
    For i = 1:1:##class(InteropOps.Rules.Data).BatchCount(pCaseId) {
        Set tTotal = tTotal + 1
        Set tIn = ##class(EnsLib.HL7.Message).ImportFromString(##class(InteropOps.Rules.Data).BatchRaw(pCaseId, i), .tSC)
        $$$ThrowOnError(tSC)
        Set tR = ..CheckMessage(tIn, .tAux)
        Set tUnmapped = tUnmapped + tR."bad_code", tUnit = tUnit + tR."bad_unit", tRange = tRange + tR."bad_range", tNoMrn = tNoMrn + tR."no_mrn", tOk = tOk + tR.valid
    }
    Return {"total": (tTotal), "valid": (tOk), "with_unmapped_code": (tUnmapped), "with_unit_mismatch": (tUnit), "with_range_mismatch": (tRange), "missing_mrn_pid3": (tNoMrn)}
}

}
