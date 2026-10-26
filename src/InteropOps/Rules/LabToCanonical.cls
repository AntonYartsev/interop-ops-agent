/// Baseline DTL for the synthetic REGIONAL_LAB feed (copy of SpikeV2.LabToCanonical): OBX-3 local code -> LOINC^name^LN
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
        Set tFrom = tSeg.GetValueAt(6)
        If (tFrom '= tMeta."expected_unit") && $DATA(^IOA.UnitFactor(tCode, tFrom), tF) && $ISVALIDNUM(tSeg.GetValueAt(5)) {
            Do tSeg.SetValueAt(+$FNUMBER(tSeg.GetValueAt(5) * tF, "", 6), 5), tSeg.SetValueAt(tMeta."expected_unit", 6)
        }
        Do target.SetSegmentAt(tSeg, i)
    }
    Return $$$OK
}

/// DTL + validity check of ONE message: {bad_code, bad_unit, no_mrn, valid}
ClassMethod CheckMessage(pIn As EnsLib.HL7.Message, ByRef pAux) As %DynamicObject
{
    Set tLookup = $GET(pAux("lookup"))
    Set:'$ISOBJECT(tLookup) tLookup = ##class(InteropOps.Rules.Data).Lookup(), pAux("lookup") = tLookup
    $$$ThrowOnError(..Transform(pIn, .tOut, .pAux))
    Set (tBadCode, tBadUnit) = 0, tPid3 = ""
    For s = 1:1:tOut.SegCount {
        Set tSeg = tOut.GetSegmentAt(s)
        If tSeg.Name = "PID" Set tPid3 = tSeg.GetValueAt(3)
        Continue:tSeg.Name'="OBX"
        If tSeg.GetValueAt("3.3") '= "LN" { Set tBadCode = 1 Continue }
        Set tMeta = tLookup.%Get($ZCONVERT(pIn.GetSegmentAt(s).GetValueAt("3.1"), "U"))
        If $ISOBJECT(tMeta) && (tSeg.GetValueAt(6) '= tMeta."expected_unit") Set tBadUnit = 1
    }
    Return {"bad_code": (tBadCode), "bad_unit": (tBadUnit), "no_mrn": (tPid3 = ""), "valid": ('tBadCode && 'tBadUnit && (tPid3 '= ""))}
}

/// Run the DTL over the case batch and summarize what it could not handle.
ClassMethod RunBatch(pCaseId As %String) As %DynamicObject
{
    Set tAux("lookup") = ##class(InteropOps.Rules.Data).Lookup()
    Set (tTotal, tOk, tUnmapped, tUnit, tNoMrn) = 0
    For i = 1:1:##class(InteropOps.Rules.Data).BatchCount(pCaseId) {
        Set tTotal = tTotal + 1
        Set tIn = ##class(EnsLib.HL7.Message).ImportFromString(##class(InteropOps.Rules.Data).BatchRaw(pCaseId, i), .tSC)
        $$$ThrowOnError(tSC)
        Set tR = ..CheckMessage(tIn, .tAux)
        Set tUnmapped = tUnmapped + tR."bad_code", tUnit = tUnit + tR."bad_unit", tNoMrn = tNoMrn + tR."no_mrn", tOk = tOk + tR.valid
    }
    Return {"total": (tTotal), "valid": (tOk), "with_unmapped_code": (tUnmapped), "with_unit_mismatch": (tUnit), "missing_mrn_pid3": (tNoMrn)}
}

}
