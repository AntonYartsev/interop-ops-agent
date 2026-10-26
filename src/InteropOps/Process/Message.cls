/// IOA.Process.Message: one case batch (InteropOps.Msg.CaseRequest from IOA.In.CaseFile) through
/// ingest -> DTL (InteropOps.Rules.LabToCanonical) -> triage + rules -> [IOA.Agent if rules did not resolve] -> IOA.Gate.Replay -> Decision row.
/// FinalStatus: pass -> passed, quarantine -> quarantined, escalate (or gate rejected) -> escalated,
/// gate-passed patch_mapping / convert_unit -> pending_review row, Inbox task (IOA.Workflow), then on Approve IOA.Lookup.Apply + a final row
/// (applied, Source human / human:auto); on Reject a final row (rejected).
Class InteropOps.Process.Message Extends Ens.BusinessProcessBPL
{

XData BPL [ XMLNamespace = "http://www.intersystems.com/bpl" ]
{
<process language='objectscript' request='InteropOps.Msg.CaseRequest' response='Ens.Response' height='2000' width='2000' >
<context>
<property name='CaseId' type='%String' />
<property name='DTLSummaryJSON' type='%String' >
<parameters><parameter name='MAXLEN' value='' /></parameters>
</property>
<property name='TicketJSON' type='%String' >
<parameters><parameter name='MAXLEN' value='' /></parameters>
</property>
<property name='RulesAction' type='%String' />
<property name='DecisionJSON' type='%String' >
<parameters><parameter name='MAXLEN' value='' /></parameters>
</property>
<property name='Source' type='%String' />
<property name='AgentJSON' type='%String' >
<parameters><parameter name='MAXLEN' value='' /></parameters>
</property>
<property name='GateStatus' type='%String' />
<property name='FinalAction' type='%String' />
<property name='GateSummary' type='%String' >
<parameters><parameter name='MAXLEN' value='2000' /></parameters>
</property>
<property name='GateJSON' type='%String' >
<parameters><parameter name='MAXLEN' value='' /></parameters>
</property>
<property name='TaskId' type='%String' />
<property name='TaskAction' type='%String' />
<property name='ApplyJSON' type='%String' >
<parameters><parameter name='MAXLEN' value='' /></parameters>
</property>
</context>
<sequence>
<code name='Ingest batch' >
<![CDATA[ set context.CaseId=request.CaseId
 do ##class(InteropOps.Process.Message).Ingest(request) ]]>
</code>
<code name='DTL LabToCanonical' >
<![CDATA[ set context.DTLSummaryJSON=##class(InteropOps.Rules.LabToCanonical).RunBatch(request.CaseId).%ToJSON()
 $$$LOGINFO("DTL "_request.CaseId_": "_context.DTLSummaryJSON) ]]>
</code>
<code name='Triage and rules' >
<![CDATA[ set tDecision=##class(InteropOps.Rules.Engine).Decide(request.CaseId,.tTicket)
 set context.TicketJSON=tTicket.%ToJSON(), context.DecisionJSON=tDecision.%ToJSON(), context.RulesAction=tDecision.action, context.Source="rules"
 $$$LOGINFO("rules "_request.CaseId_": "_tDecision.action_" ("_tDecision.reason_") focus="_tTicket.focus) ]]>
</code>
<if name='Unresolved by rules?' condition='context.RulesAction="escalate"' >
<true>
<call name='Agent' target='IOA.Agent' async='0' >
<request type='InteropOps.Msg.AgentRequest' >
<assign property="callrequest.CaseId" value='request.CaseId' action="set" />
<assign property="callrequest.FirstMSH10" value='request.FirstMSH10' action="set" />
<assign property="callrequest.MessageCount" value='request.MessageCount' action="set" />
<assign property="callrequest.TicketJSON" value='context.TicketJSON' action="set" />
</request>
<response type='InteropOps.Msg.AgentResponse' >
<assign property="context.DecisionJSON" value='callresponse.DecisionJSON' action="set" />
<assign property="context.AgentJSON" value='##class(InteropOps.Process.Message).AgentSummary(callresponse)' action="set" />
<assign property="context.Source" value='"agent"' action="set" />
</response>
</call>
</true>
</if>
<call name='Gate' target='IOA.Gate.Replay' async='0' >
<request type='InteropOps.Msg.GateRequest' >
<assign property="callrequest.CaseId" value='request.CaseId' action="set" />
<assign property="callrequest.DecisionJSON" value='context.DecisionJSON' action="set" />
</request>
<response type='InteropOps.Msg.GateResponse' >
<assign property="context.GateStatus" value='callresponse.GateStatus' action="set" />
<assign property="context.FinalAction" value='callresponse.FinalAction' action="set" />
<assign property="context.GateSummary" value='callresponse.Summary' action="set" />
<assign property="context.GateJSON" value='callresponse.GateJSON' action="set" />
</response>
</call>
<code name='Decision row' >
<![CDATA[ $$$ThrowOnError(##class(InteropOps.Process.Message).RecordDecision(context, request, process.%SessionId, .tRow))
 $$$LOGINFO("decision "_request.CaseId_": "_tRow.Action_" -> "_tRow.FinalStatus_" ("_context.Source_") gate="_context.GateSummary) ]]>
</code>
<if name='Needs human review?' condition='(context.FinalAction="patch_mapping")||(context.FinalAction="convert_unit")' >
<true>
<call name='Review task' target='IOA.Workflow' async='0' >
<request type='EnsLib.Workflow.TaskRequest' >
<assign property="callrequest" value='##class(InteropOps.Workflow.Operation).BuildTask(request.CaseId,context.DecisionJSON,context.GateSummary)' action="set" />
</request>
<response type='EnsLib.Workflow.TaskResponse' >
<assign property="context.TaskId" value='callresponse.%Id()' action="set" />
<assign property="context.TaskAction" value='callresponse.%Action' action="set" />
</response>
</call>
<if name='Approved?' condition='context.TaskAction="Approve"' >
<true>
<call name='Apply and reprocess' target='IOA.Lookup.Apply' async='0' >
<request type='InteropOps.Msg.ApplyRequest' >
<assign property="callrequest.CaseId" value='request.CaseId' action="set" />
<assign property="callrequest.DecisionJSON" value='context.DecisionJSON' action="set" />
</request>
<response type='InteropOps.Msg.ApplyResponse' >
<assign property="context.ApplyJSON" value='callresponse.ResultJSON' action="set" />
</response>
</call>
</true>
</if>
<code name='Final decision row' >
<![CDATA[ $$$ThrowOnError(##class(InteropOps.Process.Message).RecordHuman(context, request, process.%SessionId, .tRow))
 $$$LOGINFO("human " _ request.CaseId _ ": " _ tRow.Action _ " -> " _ tRow.FinalStatus _ " (" _ tRow.Source _ ") task=" _ context.TaskId) ]]>
</code>
</true>
</if>
</sequence>
</process>
}

/// Store the raw messages of the case in ^IOA.Batch(caseId, n) for rules, gate and tools
ClassMethod Ingest(pRequest As InteropOps.Msg.CaseRequest)
{
    Kill ^IOA.Batch(pRequest.CaseId)
    For i = 1:1:pRequest.Messages.Count() {
        Set ^IOA.Batch(pRequest.CaseId, i) = $TRANSLATE(pRequest.Messages.GetAt(i).OutputToString(), $CHAR(10), "")
    }
}

/// Agent response fields kept for the Decision row (GateDetail.agent)
ClassMethod AgentSummary(pR As InteropOps.Msg.AgentResponse) As %String
{
    Return {"provider_kind": (pR.ProviderKind), "provider": (pR.Provider), "model": (pR.Model), "valid": (pR.Valid), "invalid_reason": (pR.InvalidReason),
        "error_kind": (pR.ErrorKind), "error": ($EXTRACT(pR.Error, 1, 500)), "max_iterations": (pR.MaxIterations), "llm_calls": (pR.LLMCalls),
        "prompt_tokens": (pR.PromptTokens), "completion_tokens": (pR.CompletionTokens),
        "tool_calls": ({}.%FromJSON($SELECT(pR.ToolCallsJSON = "": "[]", 1: pR.ToolCallsJSON))),
        "critical_check": ({}.%FromJSON($SELECT(pR.CriticalCheckJSON = "": "{}", 1: pR.CriticalCheckJSON))),
        "cassette": ({}.%FromJSON($SELECT(pR.CassetteJSON = "": "{}", 1: pR.CassetteJSON)))}.%ToJSON()
}

/// Write the case's Decision row (one row per case; the last row counts)
ClassMethod RecordDecision(pContext As Ens.BP.Context, pRequest As InteropOps.Msg.CaseRequest, pSessionId As %Integer, Output pRow As %DynamicObject) As %Status
{
    Set pRow = ..BuildRow(pContext, pRequest, pSessionId)
    // recording on: a rules-decided case gets a cassette without turns (agent cases are recorded by IOA.Agent)
    If (pContext.Source = "rules") && ##class(InteropOps.Agent.Cassette).RecordOn() {
        Do ##class(InteropOps.Agent.Cassette).Write(##class(InteropOps.Agent.Cassette).FromRules(pRequest.CaseId, pRequest.FirstMSH10, {}.%FromJSON(pContext.DecisionJSON)))
    }
    Return ##class(InteropOps.Data.Decision).Record(pRow)
}

/// Final row after the human review (last row wins): Approve -> applied, Reject -> rejected.
/// Source human:auto if LLMConfig.AutoApprove() (the Inbox task still exists and is completed).
ClassMethod RecordHuman(pContext As Ens.BP.Context, pRequest As InteropOps.Msg.CaseRequest, pSessionId As %Integer, Output pRow As %DynamicObject) As %Status
{
    Set pRow = ..BuildRow(pContext, pRequest, pSessionId), tApproved = (pContext.TaskAction = "Approve")
    Set tAuto = ##class(InteropOps.Config.LLMConfig).AutoApprove()
    Set tBase = $PIECE(pRow.Reason, " | gate passed; awaiting", 1)
    Set pRow.Source = $SELECT(tAuto: "human:auto", 1: "human"), pRow.TaskId = pContext.TaskId
    Set pRow.FinalStatus = $SELECT(tApproved: "applied", 1: "rejected")
    Set pRow.Reason = $SELECT(tAuto: "auto-approved (IOA_AUTOAPPROVE) ", 1: "") _ $SELECT(tApproved: "approved by reviewer, applied and case reprocessed", 1: "rejected by reviewer, nothing applied") _ " | " _ tBase
    If tApproved Do pRow.gateDetail.%Set("apply", {}.%FromJSON(pContext.ApplyJSON))
    Return ##class(InteropOps.Data.Decision).Record(pRow)
}

ClassMethod BuildRow(pContext As Ens.BP.Context, pRequest As InteropOps.Msg.CaseRequest, pSessionId As %Integer) As %DynamicObject
{
    Set tD = {}.%FromJSON(pContext.DecisionJSON), tT = tD.target, tAction = tD.action
    Set tAgent = {}.%FromJSON($SELECT(pContext.AgentJSON = "": "{}", 1: pContext.AgentJSON))
    Set tStatus = $CASE(pContext.FinalAction, "pass": "passed", "quarantine": "quarantined", "patch_mapping": "pending_review", "convert_unit": "pending_review", : "escalated")
    Set (tTarget, tFactor) = "", tMsh10 = pRequest.FirstMSH10
    If $ISOBJECT(tT) {
        If tAction = "patch_mapping" Set tTarget = $ZCONVERT(tT.code, "U") _ "->" _ tT.loinc
        If tAction = "convert_unit" Set tTarget = $ZCONVERT(tT.code, "U"), tFactor = ##class(InteropOps.Gate.Replay).Multiplier(tT)
        If tAction = "quarantine" Set (tTarget, tMsh10) = ##class(InteropOps.Util.Ids).NormMSH10(tT.msh10)
    }
    // triage facts go into evidence and, for escalations, into the reason (e.g. "PID-2 ... 30/30" for a moved MRN)
    Set tTriage = ##class(InteropOps.Rules.Engine).TicketEvidence({}.%FromJSON(pContext.TicketJSON))
    Set tEvidence = $SELECT($ISOBJECT(tD.evidence): tD.evidence, 1: []), tHave = tEvidence.%ToJSON()
    Set tIt = tTriage.%GetIterator()
    While tIt.%GetNext(, .tLine) { Do:tHave'[tLine tEvidence.%Push(tLine) }
    Set tReason = tD.reason
    If pContext.GateStatus = "GATE_REJECTED" Set tReason = tReason _ " | gate rejected " _ tAction _ ": " _ {}.%FromJSON(pContext.GateJSON)."gate_reasons".%ToJSON()
    If tStatus = "escalated" {
        Set tIt = tTriage.%GetIterator()
        While tIt.%GetNext(, .tLine) { Set tReason = tReason _ " | " _ tLine }
    }
    If tStatus = "pending_review" Set tReason = tReason _ " | gate passed; awaiting human review (Inbox task, role IOA-Reviewers)"
    Set tRow = {"CaseId": (pRequest.CaseId), "MSH10": (tMsh10), "SessionId": (pSessionId), "Mode": (##class(InteropOps.Config.LLMConfig).Mode()),
        "Source": (pContext.Source), "Action": (tAction), "Target": (tTarget), "Factor": (tFactor), "Reason": (tReason),
        "GateResult": (pContext.GateSummary), "FinalStatus": (tStatus), "evidence": (tEvidence),
        "gateDetail": ({"provider_kind": ($SELECT(pContext.Source = "agent": tAgent."provider_kind", 1: "none (rules)")), "dtl": ({}.%FromJSON(pContext.DTLSummaryJSON)),
            "gate": ({}.%FromJSON(pContext.GateJSON)), "agent": (tAgent)}),
        "LLMCalls": (+tAgent."llm_calls"), "TokensIn": (+tAgent."prompt_tokens"), "TokensOut": (+tAgent."completion_tokens")}
    Return tRow
}

}