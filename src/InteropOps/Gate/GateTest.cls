/// Self-test for the gate, Apply and the DTL on modified copies of case C01 / C03 / C04 (no LLM, no production call).
/// Run after demo.sh (needs ^IOA.Batch of C01, C03, C04): do ##class(InteropOps.Gate.GateTest).Run() -> GATE_TEST=PASS|FAIL.
/// Uses case id ZT1 and removes it afterwards; the lookup entry SOD and the unit factor GLU mg/dL are restored to their state before the test.
Class InteropOps.Gate.GateTest
{

ClassMethod Run() As %Boolean
{
    Set tFail = "", tMap = {"action": "patch_mapping", "target": {"code": "SOD", "loinc": "2951-2"}}
    Set G = "InteropOps.Gate.Replay", tTable = ##class(InteropOps.Rules.Data).#LOOKUPTABLE
    Set tOldSod = $GET(^Ens.LookupTable(tTable, "SOD")), tOldGlu = $GET(^IOA.UnitFactor("GLU", "mg/dL"))
    Try {
        // start without an applied SOD mapping (a demo run applies it), else the gate rejects for another reason
        Do ##class(Ens.Util.LookupTable).%RemoveValue(tTable, "SOD")
        // 1. C01 with PID-3 removed in 29 of 30 messages: patch_mapping is rejected
        Do ..Copy("C01", "ZT1", 29, "")
        If $CLASSMETHOD(G, "Evaluate", "ZT1", tMap)."gate_status" '= "GATE_REJECTED" Set tFail = tFail _ " partial_mrn_passed"
        // 2. C01 with the SOD unit changed in 10 of 30 messages: patch_mapping is rejected
        Do ..Copy("C01", "ZT1", 0, "10:SOD:mEq/L")
        If $CLASSMETHOD(G, "Evaluate", "ZT1", tMap)."gate_status" '= "GATE_REJECTED" Set tFail = tFail _ " partial_unit_passed"
        // 3. pass on C03 (creatinine in mg/dL): rejected, final escalate
        If $CLASSMETHOD(G, "Evaluate", "C03", {"action": "pass"})."final_action" '= "escalate" Set tFail = tFail _ " pass_on_unit_mismatch"
        // 4. history replay of a safe new mapping changes no historical message
        Set tH = $CLASSMETHOD(G, "HistoryReplay", tMap)
        If (tH.total '= 200) || (tH.changed '= 0) Set tFail = tFail _ " history_replay=" _ tH.%ToJSON()
        // 5. Apply on a batch with 29 messages without MRN: reprocess fails, the mapping is rolled back
        Do ..Copy("C01", "ZT1", 29, "")
        Set tR = ##class(InteropOps.Lookup.Apply).Run("ZT1", tMap)
        If (tR.applied '= "") || (tR.error '[ "reprocess_failed") || $DATA(^Ens.LookupTable(tTable, "SOD")) Set tFail = tFail _ " no_rollback=" _ tR.%ToJSON()
        // 6. Apply with the SHA of another batch: nothing applied
        Do ..Copy("C01", "ZT1", 0, "")
        Set tR = ##class(InteropOps.Lookup.Apply).Run("ZT1", tMap, "", "not-the-reviewed-batch")
        If (tR.error '[ "batch_changed") || $DATA(^Ens.LookupTable(tTable, "SOD")) Set tFail = tFail _ " batch_changed_applied"
        // 7. Apply on the clean copy: all 30 valid, mapping stays
        Set tR = ##class(InteropOps.Lookup.Apply).Run("ZT1", tMap, "", ##class(InteropOps.Rules.Data).BatchSHA("ZT1"))
        If (tR.applied '= "SOD->2951-2") || (tR.reprocess.valid '= 30) Set tFail = tFail _ " clean_apply=" _ tR.%ToJSON()
        // 8. DTL of C04 after the GLU factor: LOINC, unit and OBX-7 range all molar, message valid
        Set ^IOA.UnitFactor("GLU", "mg/dL") = 0.0555556
        Set tIn = ##class(EnsLib.HL7.Message).ImportFromString(##class(InteropOps.Rules.Data).BatchRaw("C04", 1))
        $$$ThrowOnError(##class(InteropOps.Rules.LabToCanonical).Transform(tIn, .tOut))
        Set tObx = ""
        For s = 1:1:tOut.SegCount { Set tSeg = tOut.GetSegmentAt(s) If (tSeg.Name = "OBX") && (tSeg.GetValueAt("3.1") = "14749-6") Set tObx = tSeg.OutputToString() Quit }
        If ($PIECE(tObx, "|", 7) '= "mmol/L") || ($PIECE(tObx, "|", 8) '= "3.89-5.83") Set tFail = tFail _ " c04_obx=" _ tObx
        If '##class(InteropOps.Rules.LabToCanonical).CheckMessage(tIn).valid Set tFail = tFail _ " c04_invalid"
        // 9. the same message with its range left in mg/dL is not valid
        Kill ^IOA.UnitFactor("GLU", "mg/dL")
        If ##class(InteropOps.Rules.LabToCanonical).RangeAgrees("70-105", "3.9-5.8") Set tFail = tFail _ " range_mgdl_accepted"
    } Catch tEx {
        Set tFail = tFail _ " error:" _ tEx.DisplayString()
    }
    Kill ^IOA.Batch("ZT1"), ^IOA.UnitFactor("GLU", "mg/dL")
    Do ##class(Ens.Util.LookupTable).%RemoveValue(tTable, "SOD")
    Do:tOldSod'="" ##class(Ens.Util.LookupTable).%UpdateValue(tTable, "SOD", tOldSod)
    Set:tOldGlu'="" ^IOA.UnitFactor("GLU", "mg/dL") = tOldGlu
    Write "GATE_TEST=", $SELECT(tFail = "": "PASS", 1: "FAIL" _ tFail), !
    Return tFail = ""
}

/// ^IOA.Batch(pTo) = copy of pFrom; PID-3 emptied in the first pNoMrn messages; pUnit "n:CODE:unit" sets OBX-6 of CODE in the first n
ClassMethod Copy(pFrom As %String, pTo As %String, pNoMrn As %Integer, pUnit As %String) [ Private ]
{
    Kill ^IOA.Batch(pTo)
    Set tAll = ""
    For i = 1:1:##class(InteropOps.Rules.Data).BatchCount(pFrom) {
        Set tRaw = ##class(InteropOps.Rules.Data).BatchRaw(pFrom, i), tNew = ""
        For s = 1:1:$LENGTH(tRaw, $CHAR(13)) {
            Set tSeg = $PIECE(tRaw, $CHAR(13), s)
            If (i <= pNoMrn) && ($PIECE(tSeg, "|") = "PID") Set $PIECE(tSeg, "|", 4) = ""
            If (pUnit '= "") && (i <= +pUnit) && ($PIECE(tSeg, "|") = "OBX") && ($PIECE($PIECE(tSeg, "|", 4), "^") = $PIECE(pUnit, ":", 2)) Set $PIECE(tSeg, "|", 7) = $PIECE(pUnit, ":", 3)
            Set $PIECE(tNew, $CHAR(13), s) = tSeg
        }
        Set ^IOA.Batch(pTo, i) = tNew, tAll = $SYSTEM.Encryption.SHAHash(256, tAll _ tNew)
    }
    Set ^IOA.Batch(pTo) = ##class(%xsd.hexBinary).LogicalToXSD(tAll)
}

}
