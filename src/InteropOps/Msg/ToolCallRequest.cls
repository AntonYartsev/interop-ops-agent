/// One agent tool call, sent by InteropOps.Agent.TraceAuditPolicy so it shows in Visual Trace
Class InteropOps.Msg.ToolCallRequest Extends Ens.Request
{

Property CaseId As %String;

Property ToolName As %String(MAXLEN = 200);

Property ArgumentsJSON As %String(MAXLEN = "");

Property ResultJSON As %String(MAXLEN = "");

Property DurationMs As %Numeric;

/// LIVE | MOCK | REPLAY
Property ProviderKind As %String;

}
