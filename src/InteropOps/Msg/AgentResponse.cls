/// Agent step result (fields from SpikeV2.Msg.AgentResponse + V21 + provider kind / replay info)
Class InteropOps.Msg.AgentResponse Extends Ens.Response
{

Property CaseId As %String;

/// LIVE | MOCK | REPLAY
Property ProviderKind As %String;

Property Provider As %String;

Property Model As %String(MAXLEN = 200);

Property DecisionJSON As %String(MAXLEN = "");

Property RawAnswer As %String(MAXLEN = "");

Property Valid As %Boolean;

Property InvalidReason As %String(MAXLEN = "");

/// "" | max_iterations | timeout | loop_detected | budget_cap | budget_lock | replay_miss | error
Property ErrorKind As %String;

Property Error As %String(MAXLEN = "");

Property MaxIterations As %Integer;

Property LLMCalls As %Integer;

Property PromptTokens As %Integer;

Property CompletionTokens As %Integer;

Property ToolCallsJSON As %String(MAXLEN = "");

Property StatsJSON As %String(MAXLEN = "");

/// CheckCriticalValues() result + whether the decision cites every critical result
Property CriticalCheckJSON As %String(MAXLEN = "");

/// REPLAY: cassette file and replay check details; recording: cassette written
Property CassetteJSON As %String(MAXLEN = "");

}
