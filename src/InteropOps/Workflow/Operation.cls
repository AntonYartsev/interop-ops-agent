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

/// Task fields from the case decision: Subject, Message (proposal, evidence, gate), Command = case id
ClassMethod BuildTask(pCaseId As %String, pDecisionJSON As %String, pGate As %String, pSessionId As %String = "") As EnsLib.Workflow.TaskRequest
{
    Set tD = {}.%FromJSON(pDecisionJSON), tT = tD.target, tReq = ##class(EnsLib.Workflow.TaskRequest).%New()
    Set tProposal = tD.action _ " " _ $SELECT(tD.action = "patch_mapping": tT.code _ " -> " _ tT.loinc, 1: tT.code _ " " _ tT."from_unit" _ " -> " _ tT."to_unit" _ " x " _ ##class(InteropOps.Gate.Replay).Multiplier(tT))
    Set tReq.%Subject = "Case " _ pCaseId _ ": " _ tProposal
    Set tReq.%Message = $EXTRACT("Case " _ pCaseId _ " | Proposal: " _ tProposal _ " | Reason: " _ tD.reason _ " | Gate: " _ pGate _ " | Evidence: " _ tD.evidence.%ToJSON(), 1, 2000)
    Set tReq.%Actions = "Approve,Reject", tReq.%Command = pCaseId
    Do tReq.%FormValues.SetAt(pSessionId, "SessionId")
    Quit tReq
}

}
