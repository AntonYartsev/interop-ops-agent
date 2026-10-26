/// IOA.Agent.Tools: receives one message per agent tool call (sent by the audit policy), so tool calls show in Visual Trace.
/// The tool itself already ran inside IOA.Agent; this host only records it.
Class InteropOps.Agent.ToolTrace Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As InteropOps.Msg.ToolCallRequest, Output pResponse As Ens.Response) As %Status
{
    $$$LOGINFO("[" _ pRequest.ProviderKind _ "] case=" _ pRequest.CaseId _ " tool=" _ pRequest.ToolName _ " args=" _ $EXTRACT(pRequest.ArgumentsJSON, 1, 300) _ " ms=" _ pRequest.DurationMs)
    Return $$$OK
}

}
