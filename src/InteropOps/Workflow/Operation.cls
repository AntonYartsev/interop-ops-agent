/// IOA.Workflow: human review task in the Inbox (EnsPortal.WFWorklist.zen) for role IOA-Reviewers.
/// The standard operation takes the role from the config name; this one fixes it, so the item can be called IOA.Workflow.
/// Actions: Approve, Reject. The deferred TaskResponse goes back to IOA.Process.Message.
/// If LLMConfig.AutoApprove(), the task is created (visible in the Inbox history) and completed with Approve at once.
Class InteropOps.Workflow.Operation Extends EnsLib.Workflow.Operation
{

Parameter ROLE = "IOA-Reviewers";

Method TaskHandler(pTask As EnsLib.Workflow.TaskRequest, Output pResponse As EnsLib.Workflow.TaskResponse) As %Status
{
    Set tSC = ..DeferResponse(.tToken)
    Quit:$$$ISERR(tSC) tSC
    Set tSC = ##class(EnsLib.Workflow.Engine).%DistributeTask(..#ROLE, pTask, tToken)
    Quit:$$$ISERR(tSC) tSC
    Set tId = ..TaskIdForToken(tToken)
    Do ..SetDecisionTask(pTask.%Command, tId, pTask.%FormValues.GetAt("SessionId"))
    // reviewer channel (webhook), fire and forget: a failed notify must not block the review
    Do ..SendRequestAsync("IOA.Notify.Reviewer", ##class(Ens.StringRequest).%New(pTask.%Subject _ " | task " _ tId _ " | Inbox: /csp/irisapp/EnsPortal.WFWorklist.zen"), 0)
    If ##class(InteropOps.Config.LLMConfig).AutoApprove() {
        // mark the task itself as auto-approved (Decision Source human:auto is read from here, not from config)
        Set tTask = ##class(EnsLib.Workflow.TaskResponse).%OpenId(tId)
        If $ISOBJECT(tTask) Do tTask.%FormValues.SetAt(1, "AutoApproved") Set tSC = tTask.%Save() Quit:$$$ISERR(tSC) tSC
        Set tSC = ..Complete(tId, "Approve")
    }
    Quit tSC
}

/// Task id of the task created for a deferred-response token
ClassMethod TaskIdForToken(pToken As %String) As %String
{
    &sql(SELECT ID INTO :tId FROM EnsLib_Workflow.TaskResponse WHERE TaskStatus_ResponseToken = :pToken)
    Quit $GET(tId)
}

/// Put the task id on the latest Decision row of the case and session (pCaseId = the TaskRequest %Command, pSessionId = %FormValues("SessionId"))
/// If pSessionId is empty, the latest row of the case.
ClassMethod SetDecisionTask(pCaseId As %String, pTaskId As %String, pSessionId As %String = "")
{
    If pSessionId '= "" {
        &sql(SELECT MAX(ID) INTO :tRow FROM InteropOps_Data.Decision WHERE CaseId = :pCaseId AND SessionId = :pSessionId)
    } Else {
        &sql(SELECT MAX(ID) INTO :tRow FROM InteropOps_Data.Decision WHERE CaseId = :pCaseId)
    }
    Quit:$GET(tRow)=""
    &sql(UPDATE InteropOps_Data.Decision SET TaskId = :pTaskId WHERE ID = :tRow)
}

/// Complete a task like the Inbox form does (also a dev/test entry): Approve or Reject
ClassMethod Complete(pTaskId As %String, pAction As %String = "Approve", pUser As %String = "reviewer") As %Status
{
    Set tTask = ##class(EnsLib.Workflow.TaskResponse).%OpenId(pTaskId)
    Quit:'$ISOBJECT(tTask) $$$ERROR($$$GeneralError, "no task " _ pTaskId)
    If tTask.%TaskStatus.AssignedTo = "" {
        Set tSC = ##class(EnsLib.Workflow.Engine).AssignTask(tTask, pUser)
        Quit:$$$ISERR(tSC) tSC
    }
    Quit ##class(EnsLib.Workflow.Engine).CompleteTask(tTask, pAction)
}

/// Task fields from the case decision: Subject, Message, Command = case id.
/// The message keeps apart what the deterministic gate measured (pGateJSON) and what the proposer wrote (reason, evidence).
ClassMethod BuildTask(pCaseId As %String, pDecisionJSON As %String, pGate As %String, pSessionId As %String = "", pGateJSON As %String = "", pSource As %String = "") As EnsLib.Workflow.TaskRequest
{
    Set tD = {}.%FromJSON(pDecisionJSON), tT = tD.target, tReq = ##class(EnsLib.Workflow.TaskRequest).%New(), nl = $CHAR(10)
    Set tProposal = tD.action _ " " _ $SELECT(tD.action = "patch_mapping": tT.code _ " -> " _ tT.loinc, 1: tT.code _ " " _ tT."from_unit" _ " -> " _ tT."to_unit" _ " x " _ ..N(##class(InteropOps.Gate.Replay).Multiplier(tT)))
    Set tReq.%Subject = "Case " _ pCaseId _ ": " _ tProposal
    Set tMode = ##class(InteropOps.Config.LLMConfig).Mode()
    Set tBy = $SELECT(pSource = "rules": "deterministic rules (no LLM)", tMode = "REPLAY": "agent, answer replayed from a recorded LIVE run", tMode = "MOCK": "agent, local mock LLM", 1: "agent, LIVE LLM call")
    Set tM = "Proposal: " _ tProposal _ nl _ "Proposed by: " _ tBy _ nl _ ..GateLines(pGateJSON, tD.action)
    Set tM = tM _ nl _ "PROPOSER SAYS (not verified by the gate):" _ nl _ " reason: " _ tD.reason
    Set tIt = $SELECT($ISOBJECT(tD.evidence): tD.evidence.%GetIterator(), 1: [].%GetIterator())
    While tIt.%GetNext(, .tE) { Set tM = tM _ nl _ " - " _ tE }
    Set tReq.%Message = $EXTRACT(tM, 1, 2000)
    Set tReq.%Actions = "Approve,Reject", tReq.%Command = pCaseId
    Do tReq.%FormValues.SetAt(pSessionId, "SessionId")
    Quit tReq
}

/// Number for display, with a leading zero (.93 -> 0.93)
ClassMethod N(pX As %Numeric) As %String
{
    Quit $SELECT($EXTRACT(pX) = ".": "0" _ pX, $EXTRACT(pX, 1, 2) = "-.": "-0" _ $EXTRACT(pX, 2, *), 1: pX)
}

/// Scope and the measured gate checks as text lines, plus what the gate does not check
ClassMethod GateLines(pGateJSON As %String, pAction As %String) As %String
{
    Set nl = $CHAR(10)
    Quit:pGateJSON="" "GATE: no detail"
    Set tG = {}.%FromJSON(pGateJSON), tC = tG.reference.checks, tH = tG.checks."history_replay"
    Quit:'$ISOBJECT(tC)||(tC.code="") "GATE: " _ tG."gate_status"
    Set tUnits = "", tIt = tC.units.%GetIterator()
    While tIt.%GetNext(.tU, .tN) { Set tUnits = tUnits _ $SELECT(tUnits = "": "", 1: ", ") _ tN _ "x " _ tU }
    Set tDiff = $SELECT(+tC."history_median" > 0: $FNUMBER($ZABS($SELECT(pAction = "convert_unit": tC."batch_median_after", 1: tC."batch_median") - tC."history_median") / tC."history_median" * 100, "", 1) _ "%", 1: "n/a")
    Set tS = "Scope: " _ tC.code _ " in " _ tC.results _ " results of " _ tC.messages _ " messages in this batch, " _ tC."history_results" _ " results in the 200 historical messages."
    If pAction = "patch_mapping" {
        Set tS = tS _ " After approval every new " _ tC.code _ " result is sent as " _ tC."target_loinc" _ " (" _ tC."target_name" _ ")."
        Set tS = tS _ nl _ "GATE CHECKED (" _ tG."gate_status" _ ", deterministic):"
        Set tS = tS _ nl _ " - unit: " _ tUnits _ "; expected unit of " _ tC."target_local" _ ": " _ tC."expected_unit"
        Set tS = tS _ nl _ " - values: batch median " _ ..N(tC."batch_median") _ " vs history median of " _ tC."target_local" _ " " _ ..N(tC."history_median") _ " (diff " _ tDiff _ ", limit " _ (tC."median_limit" * 100) _ "%)"
        Set tS = tS _ nl _ " - collision: " _ tC."target_local" _ " is absent in this batch"
    } Else {
        Set tS = tS _ nl _ "GATE CHECKED (" _ tG."gate_status" _ ", deterministic):"
        Set tS = tS _ nl _ " - unit: " _ tUnits _ "; " _ tC."from_unit" _ " x " _ ..N(tC.factor) _ " -> " _ tC."expected_unit" _ " (UCUM table: " _ $SELECT(tG.checks."strict_ucum".ok: "factor matches", 1: "no match") _ ")"
        Set tS = tS _ nl _ " - values: batch median " _ ..N(tC."batch_median_before") _ " -> " _ ..N(tC."batch_median_after") _ " vs history median " _ ..N(tC."history_median") _ " (diff " _ tDiff _ ", limit " _ (tC."median_limit" * 100) _ "%)"
    }
    Set tS = tS _ nl _ " - batch after the fix: " _ $SELECT(tG."gate_reasons".%Size() = 0: "no unresolved anomaly", 1: tG."gate_reasons".%ToJSON())
    If $ISOBJECT(tH) Set tS = tS _ nl _ " - history replay: " _ tH.changed _ "/" _ tH.total _ " DTL outputs change" _ $SELECT(+tC."history_results" = 0: " (" _ tC.code _ " never occurs in history, so this only shows that nothing else changes)", 1: "")
    If pAction = "patch_mapping" Set tS = tS _ nl _ "NOT CHECKED: the meaning of the sender text '" _ tC.description _ "' (specimen, method, analyte). Read it before you approve."
    Quit tS
}

}
