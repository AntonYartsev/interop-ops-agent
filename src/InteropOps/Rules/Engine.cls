/// Rules, run on the summary of the received batch. In this order:
/// 0. no anomaly in the ticket -> pass (the gate rejects pass if any unresolved reason remains)
/// 1. an MSH-10 seen more than once AND all its copies byte-identical -> quarantine that MSH-10
///    (copies that differ, e.g. a correction resend, are not quarantined by rules; the gate would reject it)
/// 2. exactly one anomaly in the ticket, and it is
///    a. unmapped_code with an OBX-3.4-6 LOINC alt code that exists in the lookup -> patch_mapping to that LOINC
///    b. unmapped_code whose description equals a lookup short_name or canonical_name -> patch_mapping
///    c. unit_or_value_shift with unit_changed=1 and a UCUM table factor -> convert_unit
/// 3. else escalate = unresolved by rules (the BPL sends it to the agent)
Class InteropOps.Rules.Engine
{

/// pTicket (out): triage ticket. Returns {action, target, reason, evidence}
ClassMethod Decide(pCaseId As %String, Output pTicket As %DynamicObject) As %DynamicObject
{
    Set tScen = ##class(InteropOps.Rules.Data).BatchSummary(pCaseId)
    Set tLookup = ##class(InteropOps.Rules.Data).Lookup()
    Set pTicket = ##class(InteropOps.Rules.Triage).Inspect(pCaseId, tScen, ##class(InteropOps.Rules.Data).HistorySummary(), tLookup, ##class(InteropOps.Rules.Data).BaselineDTL())
    Set tEvidence = ..TicketEvidence(pTicket)

    // 1. duplicate MSH-10
    Set tIter = tScen."msh10_stats".duplicates.%GetIterator()
    While tIter.%GetNext(.tMsh10, .tCount) {
        Set tMsh10 = ##class(InteropOps.Util.Ids).NormMSH10(tMsh10)
        Set tQ = ##class(InteropOps.Gate.Replay).CheckQuarantine(pCaseId, tMsh10)
        If tQ.ok {
            Do tEvidence.%Push("MSH-10 " _ tMsh10 _ " appears " _ tCount _ " times in " _ tScen."total_messages" _ " messages, all copies identical")
            Return {"action": "quarantine", "target": {"msh10": (tMsh10)}, "reason": "Rule A1: duplicate MSH-10 with identical copies", "evidence": (tEvidence)}
        }
        Do tEvidence.%Push("MSH-10 " _ tMsh10 _ " appears " _ tCount _ " times in " _ tScen."total_messages" _ " messages, copies differ (" _ tQ.reason _ ")")
    }

    Set tAnoms = pTicket.anomalies
    // 0. no anomaly after the DTL (e.g. the same change again after an approved fix): pass, the gate re-checks it
    If tAnoms.%Size() = 0 Return {"action": "pass", "target": null, "reason": "Rule A0: no anomaly in the batch", "evidence": (tEvidence)}
    If tAnoms.%Size() = 1 {
        Set tA = tAnoms.%Get(0)
        If tA.category = "unmapped_code" {
            Set tCode = tA.code
            // 2a. alt code in OBX-3.4-6
            Set tAltIter = tScen."code_stats".%Get(tCode)."alt_codes".%GetIterator()
            While tAltIter.%GetNext(.tAlt, .tN) {
                Set tLoinc = $PIECE(tAlt, "^", 1)
                If ..LocalForLoinc(tLookup, tLoinc) '= "" {
                    Do tEvidence.%Push("OBX-3.4-6 alt code " _ tAlt _ " in " _ tN _ " messages")
                    Return {"action": "patch_mapping", "target": {"code": (tCode), "loinc": (tLoinc)}, "reason": "Rule A2a: LOINC alt code in OBX-3.4", "evidence": (tEvidence)}
                }
            }
            // 2b. exact name
            Set tDesc = $ZCONVERT($ZSTRIP(tA.description, "<>W"), "L")
            Set tLIter = tLookup.%GetIterator()
            While (tDesc '= "") && tLIter.%GetNext(.tLocal, .tMeta) {
                If (tDesc = $ZCONVERT(tMeta."short_name", "L")) || (tDesc = $ZCONVERT(tMeta."canonical_name", "L")) {
                    Do tEvidence.%Push("description '" _ tA.description _ "' equals lookup name of " _ tLocal)
                    Return {"action": "patch_mapping", "target": {"code": (tCode), "loinc": (tMeta."canonical_code")}, "reason": "Rule A2b: exact name match", "evidence": (tEvidence)}
                }
            }
        }
        // 2c. known unit pair
        If (tA.category = "unit_or_value_shift") && (+tA."unit_changed") && (+tA."ucum_factor" > 0) {
            Return {"action": "convert_unit", "target": {"code": (tA.code), "from_unit": (tA."drift_unit"), "to_unit": (tA."expected_unit"), "factor": (+tA."ucum_factor"), "operation": "multiply"}, "reason": "Rule A2c: UCUM table unit pair", "evidence": (tEvidence)}
        }
    }
    Return {"action": "escalate", "target": null, "reason": "Rule A3: no rule matched", "evidence": (tEvidence)}
}

/// Ticket facts as evidence strings (category, field/code, counts)
ClassMethod TicketEvidence(pTicket As %DynamicObject) As %DynamicArray
{
    Set tOut = []
    Set tIter = pTicket.anomalies.%GetIterator()
    While tIter.%GetNext(.i, .tA) {
        If tA.category = "empty_required_field" {
            Do tOut.%Push("triage: required field " _ tA.field _ " (" _ tA."target_field" _ ") empty in all " _ tA."total_messages" _ " messages; sibling " _ tA."candidate_sibling" _ " matches format in " _ tA."affected_count" _ "/" _ tA."total_messages")
        } Else {
            Do tOut.%Push("triage: " _ tA.details)
        }
    }
    Return tOut
}

ClassMethod LocalForLoinc(pLookup As %DynamicObject, pLoinc As %String) As %String
{
    Set tIter = pLookup.%GetIterator()
    While tIter.%GetNext(.tLocal, .tMeta) {
        If tMeta."canonical_code" = pLoinc Return tLocal
    }
    Return ""
}

}
