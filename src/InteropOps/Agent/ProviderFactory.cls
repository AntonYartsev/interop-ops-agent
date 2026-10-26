/// Provider for IOA.Agent, in this order:
/// 1. MOCK   : DEV override ^IOA.Dev("mock_base_url") set -> %AI.Provider "openai" at that loopback URL, api_key "mock-not-a-key"
///             (never "@{env:...}", never needs Mode()="LIVE")
/// 2. LIVE   : InteropOps.Config.LLMConfig.Mode()="LIVE" -> real provider of Profile() with APIKeyRef() ("@{env:...}")
/// 3. REPLAY : otherwise -> InteropOps.Agent.ReplayProvider (cassettes, no network)
Class InteropOps.Agent.ProviderFactory
{

ClassMethod Kind() As %String
{
    If $GET(^IOA.Dev("mock_base_url")) '= "" Return "MOCK"
    Return $SELECT(##class(InteropOps.Config.LLMConfig).Mode() = "LIVE": "LIVE", 1: "REPLAY")
}

/// Returns a %AI.Provider (MOCK, LIVE) or an InteropOps.Agent.ReplayProvider (REPLAY)
ClassMethod Get(Output pKind As %String, Output pProfile As %String, Output pModel As %String) As %RegisteredObject
{
    Set pKind = ..Kind(), pModel = ##class(InteropOps.Config.LLMConfig).Model()
    If pKind = "MOCK" {
        Set pProfile = "openai"
        Return ##class(%AI.Provider).Create("openai", {"api_key": "mock-not-a-key", "base_url": (^IOA.Dev("mock_base_url"))})
    }
    If pKind = "LIVE" {
        Set pProfile = ##class(InteropOps.Config.LLMConfig).Profile()
        Return ##class(%AI.Provider).Create(pProfile, {"api_key": (##class(InteropOps.Config.LLMConfig).APIKeyRef())})
    }
    Set pProfile = "replay"
    Return ##class(InteropOps.Agent.ReplayProvider).%New()
}

}
