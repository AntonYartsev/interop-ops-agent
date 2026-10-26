/// REPLAY: answers from a cassette (InteropOps.Agent.Cassette), no provider is created, no network call is made.
/// Why not a %AI.Provider subclass: %AI.Agent.Chat() hands only the provider token to the Rust agent loop ($ZF(-6) ordinal 41),
/// so no ObjectScript method of a provider subclass is called. Replay therefore runs its own loop:
/// 1. find the cassette by case id, then by MSH-10; none -> escalate, ErrorKind replay_miss
/// 2. run every recorded tool call again through %AI.ToolMgr.ExecuteTool with the same audit policy (same Visual Trace tool
///    messages) and compare each result with the recorded one (same / changed counts; a change is reported, not fatal)
/// 3. the recorded final answer goes through the same Validate() as a live answer; a recorded stop (error) -> escalate
Class InteropOps.Agent.ReplayProvider Extends %RegisteredObject
{

Method Replay(pBO As Ens.BusinessOperation, pRequest As InteropOps.Msg.AgentRequest, pResponse As InteropOps.Msg.AgentResponse)
{
    Set tC = ##class(InteropOps.Agent.Cassette).Find(pRequest.CaseId, pRequest.FirstMSH10, .tFile)
    If '$ISOBJECT(tC) {
        Do ##class(InteropOps.Agent.Operation).Fail(pResponse, "replay_miss", "no cassette for case " _ pRequest.CaseId _ " / MSH-10 " _ pRequest.FirstMSH10 _ " in " _ ##class(InteropOps.Agent.Cassette).Dir())
        Set pResponse.CassetteJSON = {"replay": "miss", "dir": (##class(InteropOps.Agent.Cassette).Dir())}.%ToJSON()
        Return
    }
    Set pResponse.Provider = "replay", pResponse.Model = tC.recorded.model
    Set tSHA = ##class(InteropOps.Agent.Cassette).PromptSHA(##class(InteropOps.Agent.Operation).SystemPrompt(), ##class(InteropOps.Agent.Operation).UserPrompt(pRequest))
    Set tMgr = ##class(%AI.ToolMgr).%New()
    $$$ThrowOnError(tMgr.AddTool(##class(InteropOps.Agent.Tools).%New()))
    Set tPolicy = ##class(InteropOps.Agent.TraceAuditPolicy).%New()
    Set tPolicy.CurrentBO = pBO, tPolicy.ProviderKind = "REPLAY"
    $$$ThrowOnError(tMgr.SetAuditPolicy(tPolicy))
    Set (tCalls, tSame, tChanged) = 0, tFinal = ""
    Set tIt = tC.turns.%GetIterator()
    While tIt.%GetNext(, .tTurn) {
        If $ISOBJECT(tTurn."tool_calls") {
            For i = 0:1:tTurn."tool_calls".%Size() - 1 {
                Set tCall = tTurn."tool_calls".%Get(i), tCalls = tCalls + 1
                // build 154: a direct ExecuteTool call gives the audit policy no arguments, so pass them in %IOAToolArgs
                Set %IOAToolArgs = $SELECT($ISOBJECT(tCall.arguments): tCall.arguments, 1: {})
                Set tRes = tMgr.ExecuteTool(tCall.name, %IOAToolArgs)
                Kill %IOAToolArgs
                Set tNow = $SELECT($ISOBJECT(tRes) && tRes.%IsDefined("value"): tRes.value, 1: tRes)
                Set tWas = $SELECT($ISOBJECT(tTurn."tool_results"): tTurn."tool_results".%Get(i), 1: "")
                If ..SameResult(tNow, $SELECT($ISOBJECT(tWas): tWas.content, 1: "")) { Set tSame = tSame + 1 } Else { Set tChanged = tChanged + 1 }
            }
        } ElseIf tTurn.content '= "" {
            Set tFinal = tTurn.content
        }
    }
    Set pResponse.CassetteJSON = {"replay": "hit", "file": (tFile), "source": (tC.recorded.source), "recorded_at": (tC.recorded.at),
        "prompt_match": (tC.match."prompt_sha256" = tSHA), "tool_calls": (tCalls), "tool_results_same": (tSame), "tool_results_changed": (tChanged),
        "recorded_llm_calls": (tC."llm_calls"), "recorded_usage": (tC.usage)}.%ToJSON()
    If tFinal = "" {
        Set tKind = $SELECT($ISOBJECT(tC.error): tC.error.kind, 1: "replay_no_answer")
        Do ##class(InteropOps.Agent.Operation).Fail(pResponse, tKind, "replayed: " _ $SELECT($ISOBJECT(tC.error): tC.error.text, 1: "cassette has no final answer"))
        Return
    }
    Set pResponse.RawAnswer = tFinal
    Set tDecision = ##class(InteropOps.Agent.Operation).Validate(##class(InteropOps.Agent.Operation).ExtractJSONObject($ZSTRIP(tFinal, "<>W")), .tWhy)
    Set pResponse.Valid = (tWhy = ""), pResponse.InvalidReason = tWhy, pResponse.DecisionJSON = tDecision.%ToJSON()
}

/// Same JSON content (key order ignored); text compared as is
ClassMethod SameResult(pNow, pWas As %String) As %Boolean
{
    Set tNow = $SELECT($ISOBJECT(pNow): pNow.%ToJSON(), 1: pNow)
    Try {
        Return ##class(InteropOps.Rules.BatchStats).Diff({}.%FromJSON(tNow), {}.%FromJSON(pWas), "") = ""
    } Catch {
        Return tNow = pWas
    }
}

}
