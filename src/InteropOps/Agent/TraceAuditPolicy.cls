Include Ensemble

/// Audit policy: every agent tool call is sent to IOA.Agent.Tools, so it shows in
/// Visual Trace, and is kept in ^||IOAToolCalls(n) = {tool, arguments, duration_ms} / ^||IOAToolCalls(n, "result") for the
/// cassette recorder. Build 154: in the Chat() path "arguments" is a JSON string; in a direct ToolMgr.ExecuteTool call it is
/// missing, so InteropOps.Agent.ReplayProvider passes them in %IOAToolArgs.
Class InteropOps.Agent.TraceAuditPolicy Extends %AI.Policy.Audit
{

Property CurrentBO As Ens.BusinessOperation;

Property ProviderKind As %String;

Method %LogExecution(call As %DynamicObject, metadata As %DynamicObject, result As %DynamicObject, duration As %Integer, status As %Status) As %Status
{
    Try {
        Set tTool = $SELECT($ISOBJECT(call): call.name, 1: "")
        Set:tTool="" tTool = "UnknownTool"
        Set tArgs = $SELECT($ISOBJECT(call): call.arguments, 1: "")
        If '$ISOBJECT(tArgs) && (tArgs '= "") { Try { Set tArgs = {}.%FromJSON(tArgs) } Catch { Set tArgs = {"raw": (tArgs)} } }
        If '$ISOBJECT(tArgs) Set tArgs = $GET(%IOAToolArgs)
        If '$ISOBJECT(tArgs) Set tArgs = {}
        Set tResult = ..ResultText(result)

        Set tReq = ##class(InteropOps.Msg.ToolCallRequest).%New()
        Set tReq.CaseId = $GET(%IOACaseId), tReq.ToolName = tTool, tReq.ArgumentsJSON = tArgs.%ToJSON()
        Set tReq.ResultJSON = $EXTRACT(tResult, 1, 3000), tReq.DurationMs = +duration, tReq.ProviderKind = ..ProviderKind
        If $ISOBJECT(..CurrentBO) Do ..CurrentBO.SendRequestSync("IOA.Agent.Tools", tReq, .tResp)

        Set n = $INCREMENT(^||IOAToolCalls)
        Set ^||IOAToolCalls(n) = {"tool": (tTool), "arguments": (tArgs), "duration_ms": (+duration)}.%ToJSON()
        Set ^||IOAToolCalls(n, "result") = tResult
    } Catch ex {
        $$$LOGERROR("[IOA.TraceAuditPolicy] " _ ##class(InteropOps.Util.Redact).Text($SYSTEM.Status.GetErrorText(ex.AsStatus())))
    }
    Return $$$OK
}

Method %LogDenial(call As %DynamicObject, metadata As %DynamicObject, status As %Status) As %Status
{
    Return $$$OK
}

/// Tool result as text. Build 154 audit result is {"tool_name","result_json"}; older shapes {"result":...} are accepted too.
ClassMethod ResultText(pResult) As %String
{
    If '$ISOBJECT(pResult) Return $GET(pResult)
    For tKey = "result_json", "result", "value" {
        Continue:'pResult.%IsDefined(tKey)
        Set tV = pResult.%Get(tKey)
        Return $SELECT($ISOBJECT(tV): tV.%ToJSON(), 1: tV)
    }
    Return pResult.%ToJSON()
}

}
