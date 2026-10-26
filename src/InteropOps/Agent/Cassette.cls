/// Cassettes, schema ioa-replay/1, one file per case: <dir>/<CaseId>.json
/// {"schema":"ioa-replay/1","case_id":"C01","match":{"msh10","prompt_sha256"},"recorded":{"profile","model","build","at","source"},
///  "turns":[{"role":"assistant","tool_calls":[{"name","arguments"}],"tool_results":[{"name","content"}]},{"role":"assistant","content":"<final JSON>"}],
///  "usage":{"prompt_tokens","completion_tokens"},"expected":{"decision","rationale_short"}}
/// Extensions: recorded.source = mock|live|rules; "llm_calls"; "error":{"kind","text"} when the agent stopped without an answer.
/// Rules-decided cases: turns [], profile "rules", model "none" and match.prompt_sha256 = SHA of "rules"+LF+MSH-10 (validator needs 64 hex; the agent is not called, the cassette documents the decision).
/// Directory: ^IOA.Dev("cassette_dir") (DEV override, used for mock cassettes) else LLMConfig.ReplayDir().
/// Recording on: LLMConfig.RecordEnabled() only (set it with LLMConfig.SetRecord()).
Class InteropOps.Agent.Cassette
{

Parameter SCHEMA = "ioa-replay/1";

ClassMethod RecordOn() As %Boolean
{
    Return ##class(InteropOps.Config.LLMConfig).RecordEnabled()
}

ClassMethod Dir() As %String
{
    Set tDir = $GET(^IOA.Dev("cassette_dir"))
    Return ##class(%File).NormalizeDirectory($SELECT(tDir '= "": tDir, 1: ##class(InteropOps.Config.LLMConfig).ReplayDir()))
}

ClassMethod PromptSHA(pSystem As %String, pUser As %String) As %String
{
    Return $ZCONVERT(##class(%xsd.hexBinary).LogicalToXSD($SYSTEM.Encryption.SHAHash(256, $ZCONVERT(pSystem _ $CHAR(10) _ pUser, "O", "UTF8"))), "L")
}

/// Cassette from an agent session (MOCK or LIVE). pContext = session.GetContext(), pStats = session.GetStats() or "".
ClassMethod FromSession(pRequest As InteropOps.Msg.AgentRequest, pSystem As %String, pUser As %String, pContext As %DynamicArray, pStats, pResponse As InteropOps.Msg.AgentResponse, pKind As %String, pProfile As %String, pModel As %String) As %DynamicObject
{
    Set tTurns = [], tNames = {}
    Set tIt = pContext.%GetIterator()
    While tIt.%GetNext(, .tM) {
        If (tM.role = "assistant") && $ISOBJECT(tM."tool_calls") && tM."tool_calls".%Size() {
            Set tCalls = [], tTurn = {"role": "assistant", "tool_calls": (tCalls), "tool_results": []}
            Set tCIt = tM."tool_calls".%GetIterator()
            While tCIt.%GetNext(, .tC) {
                Set tName = $SELECT(tC.name '= "": tC.name, 1: tC.function.name), tArgs = $SELECT(tC.arguments '= "": tC.arguments, 1: tC.function.arguments)
                If '$ISOBJECT(tArgs) { Try { Set tArgs = {}.%FromJSON($SELECT(tArgs = "": "{}", 1: tArgs)) } Catch { Set tArgs = {"raw": (tArgs)} } }
                Do tCalls.%Push({"name": (tName), "arguments": (tArgs)})
                Do tNames.%Set(tC.id, tName)
            }
            Do tTurns.%Push(tTurn)
        } ElseIf (tM.role = "tool") && tTurns.%Size() {
            Do tTurns.%Get(tTurns.%Size() - 1)."tool_results".%Push({"name": (tNames.%Get(tM."tool_call_id")), "content": (tM.content)})
        } ElseIf (tM.role = "assistant") && (tM.content '= "") {
            Do tTurns.%Push({"role": "assistant", "content": (tM.content)})
        }
    }
    Set tD = {}.%FromJSON(pResponse.DecisionJSON)
    Set tC = ..Base(pRequest.CaseId, pRequest.FirstMSH10, ..PromptSHA(pSystem, pUser), $ZCONVERT(pKind, "L"), pProfile, pModel, tTurns, tD)
    Set tC.usage = {"prompt_tokens": (pResponse.PromptTokens), "completion_tokens": (pResponse.CompletionTokens)}
    Set tC."llm_calls" = pResponse.LLMCalls
    Set:pResponse.ErrorKind'="" tC.error = {"kind": (pResponse.ErrorKind), "text": ($EXTRACT(pResponse.Error, 1, 500))}
    Return tC
}

/// Cassette for a case the rules decided (no turns)
ClassMethod FromRules(pCaseId As %String, pMsh10 As %String, pDecision As %DynamicObject) As %DynamicObject
{
    Set tC = ..Base(pCaseId, pMsh10, ..PromptSHA("rules", pMsh10), "rules", "rules", "none", [], pDecision)
    Set tC.usage = {"prompt_tokens": 0, "completion_tokens": 0}, tC."llm_calls" = 0
    Return tC
}

ClassMethod Base(pCaseId, pMsh10, pSHA, pSource, pProfile, pModel, pTurns, pDecision) As %DynamicObject [ Private ]
{
    Return {"schema": (..#SCHEMA), "case_id": (pCaseId), "match": {"msh10": (pMsh10), "prompt_sha256": (pSHA)},
        "recorded": {"profile": (pProfile), "model": (pModel), "build": ($SYSTEM.Version.GetNumber() _ "." _ $SYSTEM.Version.GetBuildNumber()),
            "at": ($ZDATETIME($ZTIMESTAMP, 3, 7)), "source": (pSource)},
        "turns": (pTurns), "expected": {"decision": (pDecision.action), "rationale_short": ($EXTRACT(pDecision.reason, 1, 300))}}
}

/// Write <Dir()>/<case_id>.json; returns the file name
ClassMethod Write(pCassette As %DynamicObject) As %String
{
    Set tDir = ..Dir()
    Do:'##class(%File).DirectoryExists(tDir) ##class(%File).CreateDirectoryChain(tDir)
    Set tFile = tDir _ pCassette."case_id" _ ".json"
    Do ##class(%JSON.Formatter).%New().FormatToString(pCassette, .tText)
    Set tStream = ##class(%Stream.FileCharacter).%New()
    Set tStream.TranslateTable = "UTF8"
    $$$ThrowOnError(tStream.LinkToFile(tFile))
    Do tStream.Write(tText)
    $$$ThrowOnError(tStream.%Save())
    Return tFile
}

/// Cassette for the case: <Dir()>/<CaseId>.json with that case_id, else any *.json whose match.msh10 is pMsh10. "" = miss.
ClassMethod Find(pCaseId As %String, pMsh10 As %String, Output pFile As %String) As %DynamicObject
{
    Set tDir = ..Dir(), pFile = tDir _ pCaseId _ ".json"
    Set tC = ..Read(pFile)
    Return:$ISOBJECT(tC)&&(tC."case_id"=pCaseId) tC
    Set tRS = ##class(%File).FileSetFunc(tDir, "*.json")
    While tRS.%Next() {
        Set pFile = tRS.Name, tC = ..Read(pFile)
        Return:$ISOBJECT(tC)&&(##class(InteropOps.Util.Ids).NormMSH10(tC.match.msh10)=##class(InteropOps.Util.Ids).NormMSH10(pMsh10)) tC
    }
    Set pFile = ""
    Return ""
}

ClassMethod Read(pFile As %String) As %DynamicObject [ Private ]
{
    Return:'##class(%File).Exists(pFile) ""
    Try {
        Set tStream = ##class(%Stream.FileCharacter).%New()
        Set tStream.TranslateTable = "UTF8"
        $$$ThrowOnError(tStream.LinkToFile(pFile))
        Set tC = {}.%FromJSON(tStream)
    } Catch {
        Return ""
    }
    Return $SELECT($ISOBJECT(tC) && (tC.schema = ..#SCHEMA): tC, 1: "")
}

}
