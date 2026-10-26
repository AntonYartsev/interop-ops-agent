/// Provider for IOA.Agent. Decision: KindFor(Mode(), REPLAY env, ^IOA.Dev("mock_base_url")), first match wins:
/// 1. REPLAY : env REPLAY=1 (kill switch) -> InteropOps.Agent.ReplayProvider (cassettes, no network); beats MOCK.
/// 2. MOCK   : DEV override ^IOA.Dev("mock_base_url") explicitly set AND MockUrlAllowed (host localhost, 127.0.0.1 or
///             host.docker.internal) -> %AI.Provider "openai" at that URL with the dummy key "mock-not-a-key".
///             No real key needed; the real key never goes to the mock and the dummy key only to an allowed host.
///             Any other mock URL is ignored with KindWarning() and the decision falls through to 3/4.
/// 3. LIVE   : Mode()="LIVE" (real key in the IRIS process AND live=1) -> real provider of Profile() with APIKeyRef()
/// 4. REPLAY : otherwise.
/// Budget: the ^IOA.Budget call cap lives in InteropOps.Agent.Operation (Reserve/Settle, applied when kind = LIVE).
Class InteropOps.Agent.ProviderFactory
{

/// Hosts a MOCK base URL may point at (exact match, lower case)
Parameter MOCKHOSTS = ",localhost,127.0.0.1,host.docker.internal,";

ClassMethod Kind() As %String
{
    Set tKind = ..KindFor(##class(InteropOps.Config.LLMConfig).Mode(), ..ReplayEnv(), ..MockUrl(), .tWarn)
    If (tWarn '= "") && '$DATA(^||IOA.KindWarned(tWarn)) {
        // once per process and text: Kind() is called for every agent message
        Set ^||IOA.KindWarned(tWarn) = 1
        Try { Do ##class(Ens.Util.Log).LogWarning($CLASSNAME(), "Kind", tWarn) } Catch { }
    }
    Return tKind
}

/// Pure kind decision (no globals, env or I/O): pMode = LLMConfig.Mode() (LIVE|REPLAY), pReplayEnv = REPLAY=1 set,
/// pMockUrl = mock base URL ("" = none). pWarn = why a mock URL was ignored ("" = not ignored or none).
ClassMethod KindFor(pMode As %String, pReplayEnv As %Boolean, pMockUrl As %String, Output pWarn As %String) As %String
{
    Set pWarn = "", tMock = $ZSTRIP(pMockUrl, "<>W")
    Set tMode = $SELECT($ZCONVERT(pMode, "U") = "LIVE": "LIVE", 1: "REPLAY")
    If +pReplayEnv {
        Set:tMock'="" pWarn = "mock_base_url ignored: REPLAY=1 beats MOCK -> REPLAY"
        Return "REPLAY"
    }
    If tMock '= "" {
        If ..MockUrlAllowed(tMock) Return "MOCK"
        Set pWarn = "mock_base_url ignored: host not localhost/127.0.0.1/host.docker.internal -> " _ tMode
    }
    Return tMode
}

/// Pure: 1 if pUrl is http(s)://HOST[:PORT][/path] with HOST in MOCKHOSTS. Rejects userinfo (user@host),
/// look-alike hosts (localhost.evil.com), other schemes, bad ports, whitespace and backslashes.
ClassMethod MockUrlAllowed(pUrl As %String) As %Boolean
{
    Set tUrl = $ZSTRIP(pUrl, "<>W")
    Quit:tUrl="" 0
    Quit:(tUrl [ " ")||(tUrl [ "\")||(tUrl [ $CHAR(9))||(tUrl [ $CHAR(10))||(tUrl [ $CHAR(13)) 0
    Set tScheme = $ZCONVERT($PIECE(tUrl, "://", 1), "L")
    Quit:(tScheme '= "http")&&(tScheme '= "https") 0
    Quit:$LENGTH(tUrl, "://")<2 0
    Set tRest = $PIECE(tUrl, "://", 2, *)
    // authority ends at the first "/", "?" or "#"
    Set tAuth = tRest
    For tSep = "/", "?", "#" { Set tAuth = $PIECE(tAuth, tSep, 1) }
    Quit:(tAuth = "")||(tAuth [ "@")||(tAuth [ "[")||(tAuth [ "]")||(tAuth [ "%") 0
    Quit:$LENGTH(tAuth, ":")>2 0
    Set tHost = $ZCONVERT($PIECE(tAuth, ":", 1), "L"), tPort = $PIECE(tAuth, ":", 2)
    If $LENGTH(tAuth, ":") = 2 {
        Quit:(tPort = "")||(tPort '? 1.5N)||(+tPort < 1)||(+tPort > 65535) 0
    }
    Quit:(tHost = "")||(tHost [ ",") 0
    Quit (..#MOCKHOSTS [ ("," _ tHost _ ","))
}

/// Why the current mock URL is ignored ("" = not ignored or not set). Text only, no secrets.
ClassMethod KindWarning() As %String
{
    Do ..KindFor(##class(InteropOps.Config.LLMConfig).Mode(), ..ReplayEnv(), ..MockUrl(), .tWarn)
    Return tWarn
}

/// DEV override ^IOA.Dev("mock_base_url") ("" = not set)
ClassMethod MockUrl() As %String [ Private ]
{
    Return $ZSTRIP($GET(^IOA.Dev("mock_base_url")), "<>W")
}

/// env REPLAY=1/true (the documented kill switch)
ClassMethod ReplayEnv() As %Boolean [ Private ]
{
    Return ##class(InteropOps.Config.LLMConfig).Truthy(##class(InteropOps.Config.LLMConfig).GetVar("REPLAY"))
}

/// Returns a %AI.Provider (MOCK, LIVE) or an InteropOps.Agent.ReplayProvider (REPLAY)
ClassMethod Get(Output pKind As %String, Output pProfile As %String, Output pModel As %String) As %RegisteredObject
{
    Set pKind = ..Kind(), pModel = ##class(InteropOps.Config.LLMConfig).Model()
    If pKind = "MOCK" {
        // dummy key only to an allowed local host (re-checked here); never the real key
        Set tUrl = ..MockUrl()
        If ..MockUrlAllowed(tUrl) {
            Set pProfile = "openai"
            Return ##class(%AI.Provider).Create("openai", {"api_key": "mock-not-a-key", "base_url": (tUrl)})
        }
        Set pKind = "REPLAY"
    }
    If pKind = "LIVE" {
        Set pProfile = ##class(InteropOps.Config.LLMConfig).Profile()
        Return ##class(%AI.Provider).Create(pProfile, {"api_key": (##class(InteropOps.Config.LLMConfig).APIKeyRef())})
    }
    Set pProfile = "replay"
    Return ##class(InteropOps.Agent.ReplayProvider).%New()
}

}
