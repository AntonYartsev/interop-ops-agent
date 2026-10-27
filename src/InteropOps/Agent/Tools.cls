/// Read-only agent tools (SpikeV2.AgentTools + SpikeV2.V21.AgentTools in one class). Every tool is scoped to the current
/// case (%IOACaseId) or the current Interoperability session (%IOASessionId). No tool returns the full history or ground truth.
/// No tracing code here: InteropOps.Agent.TraceAuditPolicy records each call.
Class InteropOps.Agent.Tools Extends %AI.Tool
{

Property Name As %String [ InitialExpression = "Lab feed inspection tools" ];

Property Description As %String(MAXLEN = "") [ InitialExpression = "Read-only tools for one batch of HL7 v2.5.1 ORU^R01 messages from REGIONAL_LAB: page through the batch, search the code lookup table, read the UCUM conversion table, check unit spelling equivalence, check critical values, read this session's event log, read the deterministic validation evidence (.NET NHapi + UCUM)." ];

/// Return raw HL7 messages of the current batch, at most 10 per call. Segments are separated by newlines.
ClassMethod GetBatchMessages(offset As %Integer(DESCRIPTION = "0-based index of the first message"), limit As %Integer(DESCRIPTION = "number of messages, 1 to 10")) As %DynamicObject
{
    Set tCase = $GET(%IOACaseId)
    Set tTotal = ##class(InteropOps.Rules.Data).BatchCount(tCase)
    Set tFrom = $SELECT(+offset < 0: 0, 1: +offset)
    Set tLimit = $SELECT(+limit < 1: 1, +limit > 10: 10, 1: +limit)
    Set tMsgs = []
    For i = tFrom + 1:1:tFrom + tLimit {
        Quit:i>tTotal
        Do tMsgs.%Push({"index": (i - 1), "raw": ($TRANSLATE(##class(InteropOps.Rules.Data).BatchRaw(tCase, i), $CHAR(13), $CHAR(10)))})
    }
    Return {"case_id": (tCase), "total_messages": (tTotal), "offset": (tFrom), "messages": (tMsgs)}
}

/// Search the receiving-side lookup table by local code, LOINC, or name fragment (case-insensitive). At most 10 entries,
/// each with expected unit, reference range and the historical median/units of that local code.
ClassMethod SearchLookup(query As %String(DESCRIPTION = "local code, LOINC code, or part of an analyte name")) As %DynamicObject
{
    Set tHist = ##class(InteropOps.Rules.Data).HistorySummary()."code_stats"
    Set tQ = $ZCONVERT($ZSTRIP(query, "<>W"), "L")
    Set tOut = []
    Set tIter = ##class(InteropOps.Rules.Data).Lookup().%GetIterator()
    While tIter.%GetNext(.tLocal, .tMeta) && (tOut.%Size() < 10) {
        Set tHay = $ZCONVERT(tLocal _ "|" _ tMeta."canonical_code" _ "|" _ tMeta."short_name" _ "|" _ tMeta."canonical_name", "L")
        Continue:(tQ'="")&&(tHay'[tQ)
        Set tH = tHist.%Get(tLocal)
        Do tOut.%Push({"local_code": (tLocal), "loinc": (tMeta."canonical_code"), "short_name": (tMeta."short_name"), "canonical_name": (tMeta."canonical_name"),
            "expected_unit": (tMeta."expected_unit"), "ref_range": (tMeta."ref_range"), "panel": (tMeta.panel),
            "history_median": ($SELECT($ISOBJECT(tH): tH.median, 1: "")), "history_units": ($SELECT($ISOBJECT(tH): tH.units, 1: {}))})
    }
    Return {"query": (query), "matches": (tOut)}
}

/// Return the UCUM unit conversion table of the receiving DTL. factor = value to multiply results in from_unit by to get to_unit.
ClassMethod GetUCUMTable() As %DynamicObject
{
    Return {"ucum_conversions": (##class(InteropOps.Rules.Data).BaselineDTL()."ucum_conversions")}
}

/// Check if two unit strings are only different spellings (letter case) of the SAME UCUM unit. Equivalent -> factor 1.
/// Only units in the table below match. Different units (for example mg/dL and mmol/L) are never equivalent: use GetUCUMTable for those.
/// If the code is correct and the only anomaly is an equivalent unit spelling, the value is unchanged: decide pass and mention the spelling in reason.
ClassMethod CheckUnitEquivalence(fromUnit As %String(DESCRIPTION = "unit found in the incoming OBX-6"), toUnit As %String(DESCRIPTION = "expected unit from the lookup table")) As %DynamicObject
{
    Set tF = $ZSTRIP(fromUnit, "<>W"), tT = $ZSTRIP(toUnit, "<>W")
    Set tCF = ..CanonicalUnit(tF), tCT = ..CanonicalUnit(tT)
    Set tEq = (tF '= "") && ((tF = tT) || ((tCF '= "") && (tCF = tCT)))
    Return {"from_unit": (tF), "to_unit": (tT), "equivalent": (tEq), "factor": ($SELECT(tEq: 1, 1: "")),
        "basis": ($SELECT(tEq && (tF = tT): "identical strings", tEq: "same UCUM unit, different letter case (" _ tCF _ ")", 1: "not the same unit spelling; if the units differ, the factor must come from GetUCUMTable"))}
}

/// lower-case unit -> UCUM spelling. A unit that is not in the table has no canonical form.
ClassMethod CanonicalUnit(pUnit As %String) As %String [ Internal, Private ]
{
    Return $CASE($ZCONVERT(pUnit, "L"), "mg/dl": "mg/dL", "g/dl": "g/dL", "ug/dl": "ug/dL", "mmol/l": "mmol/L", "umol/l": "umol/L", "meq/l": "meq/L",
        "mg/l": "mg/L", "g/l": "g/L", "u/l": "U/L", "iu/l": "IU/L", "ng/ml": "ng/mL", "ml/min": "mL/min", "10*3/ul": "10*3/uL", "10*6/ul": "10*6/uL", "%": "%", : "")
}

/// Return up to 20 Interoperability event log entries of the current session (newest last), text cut to 300 characters.
ClassMethod GetEventLogExcerpt() As %DynamicObject
{
    Set tSession = +$GET(%IOASessionId)
    Set tOut = []
    Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 20 ID, TimeLogged, Type, ConfigName, Text FROM Ens_Util.Log WHERE SessionId = ? ORDER BY ID", tSession)
    While tRS.%Next() {
        Do tOut.%Push({"time": (tRS.TimeLogged), "type": (tRS.Type), "config": (tRS.ConfigName), "text": ($EXTRACT(tRS.Text, 1, 300))})
    }
    Return {"session_id": (tSession), "entries": (tOut)}
}

/// Return the deterministic validation evidence of the current batch, computed before you were called:
/// hl7check = HL7 v2.5.1 structure check by a .NET NHapi second opinion diffed with IRIS EnsLib.HL7 validation
/// (aggregated findings: severity, code, path, source both|dotnet|iris, count of messages, example MSH-10s);
/// ucum = per OBX the unit (OBX-6) compared with the lookup's expected unit by UCUM (same_unit, spelling_variant,
/// convertible with factor, unit_missing, code_not_in_lookup) with counts and OBX-8 flags. status unavailable = that check could not run.
ClassMethod GetValidationEvidence() As %DynamicObject
{
    Return ##class(InteropOps.Evidence.Builder).ForCase($GET(%IOACaseId))
}

/// Check every OBX result of the current batch against the critical low/high table of the receiver.
/// Returns the critical results (message index, MSH-10, code, value, unit, OBX-8 flag, limit) and the table used.
/// A result is checked only if its unit equals the table unit.
/// A critical or abnormal value with a correct code and a correct unit is a clinical finding, not an interface problem.
ClassMethod CheckCriticalValues() As %DynamicObject
{
    Set tCase = $GET(%IOACaseId)
    Set tTotal = ##class(InteropOps.Rules.Data).BatchCount(tCase)
    Set tCrit = [], (tChecked, tSkipped) = 0
    For i = 1:1:tTotal {
        Set tMsg = ##class(InteropOps.Rules.Data).BatchRaw(tCase, i), tMsh10 = ""
        For s = 1:1:$LENGTH(tMsg, $CHAR(13)) {
            Set tSeg = $PIECE(tMsg, $CHAR(13), s)
            If $EXTRACT(tSeg, 1, 4) = "MSH|" Set tMsh10 = $PIECE(tSeg, "|", 10)
            Continue:$EXTRACT(tSeg, 1, 4)'="OBX|"
            Set tCode = $PIECE($PIECE(tSeg, "|", 4), "^"), tVal = $PIECE(tSeg, "|", 6), tUnit = $PIECE(tSeg, "|", 7)
            Set tLim = ..Limits(tCode)
            If (tLim = "") || (tUnit '= $LIST(tLim, 3)) || '$ISVALIDNUM(tVal) { Set tSkipped = tSkipped + 1 Continue }
            Set tChecked = tChecked + 1, tWhy = ""
            If ($LIST(tLim, 1) '= "") && (tVal < $LIST(tLim, 1)) Set tWhy = "below critical low " _ $LIST(tLim, 1)
            If ($LIST(tLim, 2) '= "") && (tVal > $LIST(tLim, 2)) Set tWhy = "above critical high " _ $LIST(tLim, 2)
            Continue:tWhy=""
            Do tCrit.%Push({"index": (i - 1), "msh10": (tMsh10), "code": (tCode), "value": (tVal), "unit": (tUnit), "flag": ($PIECE(tSeg, "|", 9)), "limit": (tWhy)})
        }
    }
    Set tTable = {}
    For tC = "GLU", "NA", "K", "WBC", "HGB", "HCT", "PLT" {
        Set tL = ..Limits(tC)
        Do tTable.%Set(tC, {"low": ($LIST(tL, 1)), "high": ($LIST(tL, 2)), "unit": ($LIST(tL, 3))})
    }
    Return {"case_id": (tCase), "total_messages": (tTotal), "results_checked": (tChecked), "results_not_checked": (tSkipped),
        "critical_count": (tCrit.%Size()), "critical": (tCrit), "critical_table": (tTable),
        "note": "Critical or abnormal values with a correct code and a correct unit are clinical findings, not interface problems: decide pass and mention them in reason."}
}

/// local code -> $LB(low, high, unit). Illustrative limits for this SYNTHETIC data set, not a clinical reference.
ClassMethod Limits(pCode As %String) As %List [ Internal, Private ]
{
    Return $CASE(pCode, "GLU": $LB(2.5, 25.0, "mmol/L"), "NA": $LB(120, 160, "mmol/L"), "K": $LB(2.8, 6.2, "mmol/L"),
        "WBC": $LB(2.0, 30.0, "10*3/uL"), "HGB": $LB(7.0, 20.0, "g/dL"), "HCT": $LB(20, 60, "%"), "PLT": $LB(20, 1000, "10*3/uL"), : "")
}

}
