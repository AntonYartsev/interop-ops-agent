/// IOA.Process.Message: one case batch (InteropOps.Msg.CaseRequest from IOA.In.CaseFile) through
/// ingest -> DTL (InteropOps.Rules.LabToCanonical) -> triage + rules -> evidence (PexHl7CheckBP .NET + IOA.Evidence.Ucum, soft) -> [IOA.Agent if rules did not resolve] -> IOA.Gate.Replay -> Decision row.
/// FinalStatus: pass -> passed, quarantine -> quarantined, escalate (or gate rejected) -> escalated,
/// gate-passed patch_mapping / convert_unit -> pending_review row, Inbox task (IOA.Workflow), then on Approve IOA.Lookup.Apply + a final row
/// (applied, Source human / human:auto); on Reject a final row (rejected).
/// After the final row IOA.Deliver writes delivered messages to cases/out/ and held messages to cases/held/.
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
<property name='BatchSHA' type='%String' >
<parameters><parameter name='MAXLEN' value='64' /></parameters>
</property>
<property name='FinalStatus' type='%String' />
<property name='DeliveryJSON' type='%String' >
<parameters><parameter name='MAXLEN' value='' /></parameters>
</property>
<property name='TaskAction' type='%String' />
<property name='Stage' type='%String' />
<property name='ApplyJSON' type='%String' >
<parameters><parameter name='MAXLEN' value='' /></parameters>
</property>
<property name='Hl7CheckJSON' type='%String' >
<parameters><parameter name='MAXLEN' value='' /></parameters>
</property>
<property name='UcumJSON' type='%String' >
<parameters><parameter name='MAXLEN' value='' /></parameters>
</property>
<property name='EvidenceJSON' type='%String' >
<parameters><parameter name='MAXLEN' value='' /></parameters>
</property>
</context>
<sequence>
<scope name='Case' >
<sequence>
<code name='Ingest batch' >
<![CDATA[ set context.CaseId=request.CaseId
 set context.BatchSHA=##class(InteropOps.Process.Message).Ingest(request) ]]>
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
<assign name='Stage Evidence' property="context.Stage" value='"evidence"' action="set" />
<scope name='HL7 structure evidence (soft)' >
<call name='HL7 structure check (.NET PEX)' target='PexHl7CheckBP' async='0' >
<request type='PexHl7.BatchCheckRequest' >
<assign property="callrequest" value='##class(InteropOps.Evidence.Builder).Hl7BatchRequest(request.CaseId)' action="set" />
</request>
<response type='PexHl7.BatchCheckResponse' >
<assign property="context.Hl7CheckJSON" value='##class(InteropOps.Evidence.Builder).Hl7Summary(callresponse)' action="set" />
</response>
</call>
<faulthandlers>
<catchall name='HL7 check unavailable' >
<code name='Degrade HL7 check' >
<![CDATA[ set context.Hl7CheckJSON=##class(InteropOps.Evidence.Builder).Unavailable("hl7check",$system.Status.GetErrorText(context.%LastError))
 $$$LOGWARNING("evidence "_request.CaseId_": HL7 .NET check unavailable, continuing without it") ]]>
</code>
</catchall>
</faulthandlers>
</scope>
<scope name='UCUM evidence (soft)' >
<call name='UCUM unit check' target='IOA.Evidence.Ucum' async='0' >
<request type='InteropOps.Msg.EvidenceRequest' >
<assign property="callrequest.CaseId" value='request.CaseId' action="set" />
</request>
<response type='InteropOps.Msg.EvidenceResponse' >
<assign property="context.UcumJSON" value='##class(InteropOps.Evidence.Builder).UcumSummary(callresponse)' action="set" />
</response>
</call>
<faulthandlers>
<catchall name='UCUM check unavailable' >
<code name='Degrade UCUM check' >
<![CDATA[ set context.UcumJSON=##class(InteropOps.Evidence.Builder).Unavailable("ucum",$system.Status.GetErrorText(context.%LastError))
 $$$LOGWARNING("evidence "_request.CaseId_": UCUM check unavailable, continuing without it") ]]>
</code>
</catchall>
</faulthandlers>
</scope>
<code name='Evidence for agent' >
<![CDATA[ set context.EvidenceJSON=##class(InteropOps.Evidence.Builder).Combine(request.CaseId,context.Hl7CheckJSON,context.UcumJSON,context.TicketJSON)
 $$$LOGINFO("evidence "_request.CaseId_": "_$extract(context.EvidenceJSON,1,500)) ]]>
</code>
<if name='Unresolved by rules?' condition='context.RulesAction="escalate"' >
<true>
<assign name='Stage Agent' property="context.Stage" value='"agent"' action="set" />
<call name='Agent' target='IOA.Agent' async='0' >
<request type='InteropOps.Msg.AgentRequest' >
<assign property="callrequest.CaseId" value='request.CaseId' action="set" />
<assign property="callrequest.FirstMSH10" value='request.FirstMSH10' action="set" />
<assign property="callrequest.MessageCount" value='request.MessageCount' action="set" />
<assign property="callrequest.TicketJSON" value='context.TicketJSON' action="set" />
<assign property="callrequest.EvidenceJSON" value='context.EvidenceJSON' action="set" />
</request>
<response type='InteropOps.Msg.AgentResponse' >
<assign property="context.DecisionJSON" value='callresponse.DecisionJSON' action="set" />
<assign property="context.AgentJSON" value='##class(InteropOps.Process.Message).AgentSummary(callresponse)' action="set" />
<assign property="context.Source" value='"agent"' action="set" />
</response>
</call>
</true>
</if>
<assign name='Stage Gate' property="context.Stage" value='"gate"' action="set" />
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
<assign name='Stage decision' property="context.Stage" value='"decision"' action="set" />
<code name='Decision row' >
<![CDATA[ $$$ThrowOnError(##class(InteropOps.Process.Message).RecordDecision(context, request, process.%SessionId, .tRow))
 set context.FinalStatus=tRow.FinalStatus
 $$$LOGINFO("decision "_request.CaseId_": "_tRow.Action_" -> "_tRow.FinalStatus_" ("_context.Source_") gate="_context.GateSummary) ]]>
</code>
<if name='Needs human review?' condition='(context.FinalAction="patch_mapping")||(context.FinalAction="convert_unit")' >
<true>
<assign name='Stage Review task' property="context.Stage" value='"workflow"' action="set" />
<call name='Review task' target='IOA.Workflow' async='0' >
<request type='EnsLib.Workflow.TaskRequest' >
<assign property="callrequest" value='##class(InteropOps.Workflow.Operation).BuildTask(request.CaseId,context.DecisionJSON,context.GateSummary,process.%SessionId)' action="set" />
</request>
<response type='EnsLib.Workflow.TaskResponse' >
<assign property="context.TaskId" value='callresponse.%Id()' action="set" />
<assign property="context.TaskAction" value='callresponse.%Action' action="set" />
</response>
</call>
<if name='Approved?' condition='context.TaskAction="Approve"' >
<true>
<assign name='Stage Apply and reprocess' property="context.Stage" value='"apply"' action="set" />
<call name='Apply and reprocess' target='IOA.Lookup.Apply' async='0' >
<request type='InteropOps.Msg.ApplyRequest' >
<assign property="callrequest.CaseId" value='request.CaseId' action="set" />
<assign property="callrequest.DecisionJSON" value='context.DecisionJSON' action="set" />
<assign property="callrequest.TaskId" value='context.TaskId' action="set" />
<assign property="callrequest.BatchSHA" value='context.BatchSHA' action="set" />
</request>
<response type='InteropOps.Msg.ApplyResponse' >
<assign property="context.ApplyJSON" value='callresponse.ResultJSON' action="set" />
</response>
</call>
</true>
</if>
<code name='Final decision row' >
<![CDATA[ $$$ThrowOnError(##class(InteropOps.Process.Message).RecordHuman(context, request, process.%SessionId, .tRow))
 set context.FinalStatus=tRow.FinalStatus
 if tRow.FinalStatus="none" { $$$LOGWARNING("task "_context.TaskId_" cancelled (action '"_context.TaskAction_"'): no final row, nothing applied") } else {
 $$$LOGINFO("human " _ request.CaseId _ ": " _ tRow.Action _ " -> " _ tRow.FinalStatus _ " (" _ tRow.Source _ ") task=" _ context.TaskId) } ]]>
</code>
</true>
</if>
<if name='Final decision?' condition='$case(context.FinalStatus,"passed":1,"applied":1,"quarantined":1,"escalated":1,"rejected":1,:0)' >
<true>
<assign name='Stage Deliver' property="context.Stage" value='"deliver"' action="set" />
<call name='Deliver or hold' target='IOA.Deliver' async='0' >
<request type='InteropOps.Msg.DeliverRequest' >
<assign property="callrequest.CaseId" value='request.CaseId' action="set" />
<assign property="callrequest.FinalStatus" value='context.FinalStatus' action="set" />
<assign property="callrequest.HoldMSH10" value='$select(context.FinalStatus="quarantined":{}.%FromJSON(context.DecisionJSON).target.msh10,1:"")' action="set" />
</request>
<response type='Ens.StringResponse' >
<assign property="context.DeliveryJSON" value='callresponse.StringValue' action="set" />
</response>
</call>
</true>
</if>
</sequence>
<faulthandlers>
<catchall name='Catch-all' >
<code name='Escalated row on error' >
<![CDATA[ do ##class(InteropOps.Process.Message).RecordError(context, request, process.%SessionId, $system.Status.GetErrorText(context.%LastError)) ]]>
</code>
</catchall>
</faulthandlers>
</scope>
</sequence>
</process>
}

/// Store the raw messages of the case in ^IOA.Batch(caseId, n) for rules, gate and tools; return the batch SHA-256
ClassMethod Ingest(pRequest As InteropOps.Msg.CaseRequest) As %String
{
    Quit:pRequest.CaseId="" ""
    Kill ^IOA.Batch(pRequest.CaseId)
    Set tAll = ""
    For i = 1:1:pRequest.Messages.Count() {
        Set (tRaw, ^IOA.Batch(pRequest.CaseId, i)) = $TRANSLATE(pRequest.Messages.GetAt(i).OutputToString(), $CHAR(10), "")
        Set tAll = $SYSTEM.Encryption.SHAHash(256, tAll _ tRaw)
    }
    // batch identity: Apply checks it, so an approval never applies to a batch that was replaced while the task waited
    Set ^IOA.Batch(pRequest.CaseId) = ##class(%xsd.hexBinary).LogicalToXSD(tAll)
    Return ^IOA.Batch(pRequest.CaseId)
}

/// Agent response fields kept for the Decision row (GateDetail.agent)
ClassMethod AgentSummary(pR As InteropOps.Msg.AgentResponse) As %String
{
    Return {"provider_kind": (pR.ProviderKind), "provider": (pR.Provider), "model": (pR.Model), "valid": (pR.Valid), "invalid_reason": (pR.InvalidReason),
        "error_kind": (pR.ErrorKind), "error": (##class(InteropOps.Util.Redact).Text(pR.Error)), "max_iterations": (pR.MaxIterations), "llm_calls": (pR.LLMCalls),
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
        Try {
            Do ##class(InteropOps.Agent.Cassette).Write(##class(InteropOps.Agent.Cassette).FromRules(pRequest.CaseId, pRequest.FirstMSH10, {}.%FromJSON(pContext.DecisionJSON)))
        } Catch tEx {
            Do pRow.gateDetail.%Set("error_kind", "cassette_error"), pRow.gateDetail.%Set("error", ##class(InteropOps.Util.Redact).Text(tEx.DisplayString()))
        }
    }
    Return ##class(InteropOps.Data.Decision).Record(pRow)
}

/// Final row after the human review (last row wins): Approve -> applied, Reject -> rejected.
/// Any other task action (Cancelled, or "" from CompleteTask(task,"") in ResetDemo): no row, Decision has no "cancelled" status.
/// Source human:auto if the task itself is marked AutoApproved (%FormValues, set by Workflow.Operation.TaskHandler).
ClassMethod RecordHuman(pContext As Ens.BP.Context, pRequest As InteropOps.Msg.CaseRequest, pSessionId As %Integer, Output pRow As %DynamicObject) As %Status
{
    Set pRow = ..BuildRow(pContext, pRequest, pSessionId), tApproved = (pContext.TaskAction = "Approve")
    If 'tApproved && (pContext.TaskAction '= "Reject") {
        Set pRow = {"Action": (pRow.Action), "FinalStatus": "none", "Source": "human"}
        Quit $$$OK
    }
    Set tTask = ##class(EnsLib.Workflow.TaskResponse).%OpenId(pContext.TaskId)
    Set tAuto = $ISOBJECT(tTask) && +tTask.%FormValues.GetAt("AutoApproved")
    Set tApply = {}.%FromJSON($SELECT(pContext.ApplyJSON = "": "{}", 1: pContext.ApplyJSON))
    Set tApplyFail = $SELECT('tApproved: "", tApply.error '= "": "apply error: " _ $EXTRACT(##class(InteropOps.Util.Redact).Text(tApply.error), 1, 200), tApply.applied = "": "apply skipped: " _ $SELECT(tApply.skipped '= "": tApply.skipped, 1: "no apply result"), 1: "")
    Set tBase = $PIECE(pRow.Reason, " | gate passed; awaiting", 1)
    Set pRow.Source = $SELECT(tAuto: "human:auto", 1: "human"), pRow.TaskId = pContext.TaskId
    Set pRow.FinalStatus = $SELECT(tApplyFail '= "": "escalated", tApproved: "applied", 1: "rejected")
    Set tHuman = $SELECT('tApproved: "rejected by reviewer, nothing applied", tApplyFail = "": "approved by reviewer, applied and case reprocessed",
        tApply.error '= "": "approved by reviewer, apply error: " _ $EXTRACT(##class(InteropOps.Util.Redact).Text(tApply.error), 1, 200),
        1: "approved by reviewer, apply skipped: " _ $SELECT(tApply.skipped '= "": tApply.skipped, 1: "no apply result") _ ", not reprocessed")
    Set pRow.Reason = $SELECT(tAuto: "auto-approved (IOA_AUTOAPPROVE) ", 1: "") _ tHuman _ " | " _ tBase
    If tApplyFail '= "" Set pRow.Action = "escalate", pRow.Reason = tApplyFail _ " | " _ pRow.Reason, pRow.Target = "", pRow.Factor = ""
    If tApproved Do pRow.gateDetail.%Set("apply", tApply)
    If tApplyFail '= "" Do pRow.gateDetail.%Set("error_kind", "apply_error")
    Return ##class(InteropOps.Data.Decision).Record(pRow)
}

/// Catch-all: no case ends without a final row. Escalated row, gateDetail.error_kind from the failed stage.
ClassMethod RecordError(pContext As Ens.BP.Context, pRequest As InteropOps.Msg.CaseRequest, pSessionId As %Integer, pError As %String)
{
    Set tKind = $CASE(pContext.Stage, "agent": "agent_error", "gate": "gate_error", "workflow": "workflow_error", "apply": "apply_error", "decision": "decision_error", "deliver": "deliver_error", : "process_error")
    Set pError = ##class(InteropOps.Util.Redact).Text(pError)
    $$$LOGERROR("catch-all " _ pRequest.CaseId _ " " _ tKind _ ": " _ pError)
    Set tRow = {"CaseId": (pRequest.CaseId), "MSH10": (pRequest.FirstMSH10), "SessionId": (pSessionId), "Mode": (##class(InteropOps.Config.LLMConfig).Mode()),
        "Source": ($SELECT(pContext.Source '= "": pContext.Source, 1: "rules")), "Action": "escalate", "Target": "", "Factor": "",
        "Reason": (tKind _ ": " _ pError), "GateResult": (pContext.GateSummary), "FinalStatus": "escalated", "evidence": [],
        "gateDetail": {"error_kind": (tKind), "error": (pError), "stage": (pContext.Stage)}}
    Set tSC = ##class(InteropOps.Data.Decision).Record(tRow)
    If $$$ISERR(tSC) $$$LOGERROR("catch-all row failed: " _ $system.Status.GetErrorText(tSC))
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
    // deterministic validation evidence (.NET NHapi second opinion + UCUM), appended after the triage facts
    Set tIt = ##class(InteropOps.Evidence.Builder).RowLines(pContext.EvidenceJSON).%GetIterator()
    While tIt.%GetNext(, .tLine) { Do tEvidence.%Push(tLine) }
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
            "gate": ({}.%FromJSON(pContext.GateJSON)), "agent": (tAgent),
            "evidence": ({}.%FromJSON($SELECT(pContext.EvidenceJSON = "": "{}", 1: pContext.EvidenceJSON)))}),
        "LLMCalls": (+tAgent."llm_calls"), "TokensIn": (+tAgent."prompt_tokens"), "TokensOut": (+tAgent."completion_tokens")}
    Return tRow
}

}