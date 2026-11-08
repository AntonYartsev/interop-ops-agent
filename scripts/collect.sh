#!/usr/bin/env bash
# Dump every Decision row of the current run (plus the Workflow card text) as one JSON array. Read-only.
C="${CONTAINER:-interop-ops-agent-iris-1}"
printf '%s\n' \
 'set a=[],rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID,CaseId,SessionId,Mode,Source,Action,Target,Reason,GateResult,FinalStatus,LLMCalls,GateDetail,TaskId,TokensIn,TokensOut,CreatedAt FROM InteropOps_Data.Decision ORDER BY ID")' \
 'while rs.%Next() { set o={"id":(rs.ID),"caseId":(rs.CaseId),"sessionId":(rs.SessionId),"mode":(rs.Mode),"source":(rs.Source),"action":(rs.Action),"target":(rs.Target),"reason":(rs.Reason),"gateResult":(rs.GateResult),"finalStatus":(rs.FinalStatus),"llmCalls":(rs.LLMCalls),"gateDetail":(rs.GateDetail),"taskId":(rs.TaskId),"tokensIn":(rs.TokensIn),"tokensOut":(rs.TokensOut),"createdAt":(rs.CreatedAt)} if rs.TaskId]"" { set t=##class(EnsLib.Workflow.TaskResponse).%OpenId(rs.TaskId) if $isobject(t) { set o.card=t.%Subject_$c(10)_t.%Message } } do a.%Push(o) }' \
 'write "__JSON_BEGIN__",! do a.%ToJSON() write !,"__JSON_END__",!' \
 'halt' \
 | docker exec -i "$C" iris session IRIS -U IRISAPP 2>/dev/null | tr -d '\r' \
 | awk '/^__JSON_BEGIN__/{f=1;next} /^__JSON_END__/{f=0} f'
