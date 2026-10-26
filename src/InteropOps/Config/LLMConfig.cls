Class InteropOps.Config.LLMConfig Extends %RegisteredObject
{

/// Default OpenAI model is gpt-5.4-mini (documented fallback: gpt-4.1-mini)
Parameter DEFAULTMODELOPENAI = "gpt-5.4-mini";

/// Documented fallback OpenAI model if gpt-5.4-mini is unavailable
Parameter FALLBACKMODELOPENAI = "gpt-4.1-mini";

/// Default OpenRouter model
Parameter DEFAULTMODELOPENROUTER = "google/gemini-2.5-flash";

/// Default replay directory inside the container
Parameter DEFAULTREPLAYDIR = "/irisdev/app/replay";

/// Default cases input directory inside the container
Parameter DEFAULTCASESIN = "/irisdev/app/cases/in/";

/// Read an environment variable or test override, with fallback to ^IOA.Config for non-secret values.
/// Never logs or persists secret values.
ClassMethod GetVar(pName As %String, ByRef pOverrides) As %String
{
    if $isobject($get(pOverrides)) {
        if pOverrides.%IsDefined(pName) {
            quit $zstrip(pOverrides.%Get(pName), "<>W")
        }
    }
    if $data(pOverrides(pName))#2 {
        quit $zstrip(pOverrides(pName), "<>W")
    }
    set val = $zstrip($SYSTEM.Util.GetEnviron(pName), "<>W")
    if (val = "") && (pName '= "OPENAI_API_KEY") && (pName '= "OPENROUTER_API_KEY") && (pName '= "IOA_REVIEWER_PASSWORD") {
        set val = $zstrip($get(^IOA.Config(pName)), "<>W")
    }
    quit val
}

/// Check whether the API key for pKeyVar is present (via override, process env, ^IOA.Config("key_present", pKeyVar), or .env fallback).
/// Never stores or returns the secret key itself.
ClassMethod IsKeyPresent(pKeyVar As %String, ByRef pOverrides) As %Boolean
{
    if (pKeyVar = "") {
        quit 0
    }
    if $isobject($get(pOverrides)) {
        if pOverrides.%IsDefined(pKeyVar) {
            quit ($zstrip(pOverrides.%Get(pKeyVar), "<>W") '= "")
        }
    }
    if $data(pOverrides(pKeyVar))#2 {
        quit ($zstrip(pOverrides(pKeyVar), "<>W") '= "")
    }
    if ($zstrip($SYSTEM.Util.GetEnviron(pKeyVar), "<>W") '= "") {
        quit 1
    }
    if +$get(^IOA.Config("key_present", pKeyVar)) {
        quit 1
    }
    do ##class(InteropOps.Setup).ReadDotEnv(.dotenv)
    if ($zstrip($get(dotenv(pKeyVar)), "<>W") '= "") {
        quit 1
    }
    quit 0
}

/// Whether the API key for the active profile is present (1 or 0).
/// Never returns or logs the secret key itself.
ClassMethod KeyPresent(ByRef pOverrides) As %Boolean
{
    do ..Resolve(.cfg, .pOverrides)
    quit +$get(cfg("keyPresent"), 0)
}

/// Enable or disable runtime LIVE mode opt-in via ^IOA.Config("live").
/// SetLive(1) sets ^IOA.Config("live")=1; SetLive(0) kills ^IOA.Config("live").
ClassMethod SetLive(pOn As %Boolean = 0) As %Status
{
    if +pOn {
        set ^IOA.Config("live") = 1
    } else {
        kill ^IOA.Config("live")
    }
    set ^IOA.Config("mode") = ..Mode()
    quit $$$OK
}

/// Check whether LIVE mode is explicitly enabled by env IOA_LIVE=1 or global ^IOA.Config("live")=1.
ClassMethod IsLiveEnabled(ByRef pOverrides) As %Boolean
{
    if $isobject($get(pOverrides)) && pOverrides.%IsDefined("IOA_LIVE") {
        set ioaLive = $zstrip(pOverrides.%Get("IOA_LIVE"), "<>W")
        if (ioaLive = "1") || ($zconvert(ioaLive, "L") = "true") {
            quit 1
        }
    } elseif $data(pOverrides("IOA_LIVE"))#2 {
        set ioaLive = $zstrip(pOverrides("IOA_LIVE"), "<>W")
        if (ioaLive = "1") || ($zconvert(ioaLive, "L") = "true") {
            quit 1
        }
    } else {
        set ioaLive = ..GetVar("IOA_LIVE")
        if (ioaLive = "1") || ($zconvert(ioaLive, "L") = "true") {
            quit 1
        }
    }

    if $isobject($get(pOverrides)) && pOverrides.%IsDefined("live") {
        quit (+pOverrides.%Get("live") = 1)
    }
    if $data(pOverrides("live"))#2 {
        quit (+pOverrides("live") = 1)
    }
    quit (+$get(^IOA.Config("live")) = 1)
}

/// Active mode: "LIVE" only if active profile key is non-empty AND live is explicitly enabled
/// (env IOA_LIVE=1 OR global ^IOA.Config("live")=1) AND REPLAY'=1; otherwise "REPLAY".
ClassMethod Mode() As %String
{
    do ..Resolve(.cfg)
    quit $get(cfg("mode"), "REPLAY")
}

/// Active LLM profile: "openai" or "openrouter" (default "openai")
ClassMethod Profile() As %String
{
    do ..Resolve(.cfg)
    quit $get(cfg("profile"), "openai")
}

/// Active model name (openai default: gpt-5.4-mini, fallback documented: gpt-4.1-mini;
/// openrouter default: google/gemini-2.5-flash; LLM_MODEL overrides)
ClassMethod Model() As %String
{
    do ..Resolve(.cfg)
    quit $get(cfg("model"), ..#DEFAULTMODELOPENAI)
}

/// Environment variable name holding the API key for the active profile
ClassMethod KeyVar() As %String
{
    do ..Resolve(.cfg)
    quit $get(cfg("keyVar"), "OPENAI_API_KEY")
}

/// AI Hub build 154 environment variable reference syntax: "@{env:OPENAI_API_KEY}" or "@{env:OPENROUTER_API_KEY}"
ClassMethod APIKeyRef() As %String
{
    quit "@{env:" _ ..KeyVar() _ "}"
}

/// Directory containing deterministic replay fixtures (env IOA_REPLAY_DIR, default /irisdev/app/replay)
ClassMethod ReplayDir() As %String
{
    set val = ..GetVar("IOA_REPLAY_DIR")
    quit $select(val="":..#DEFAULTREPLAYDIR, 1:val)
}

/// Whether pending_review decisions are auto-approved (^IOA.Config("autoapprove")=1, from IOA_AUTOAPPROVE or demo.sh).
/// Auto-approved decisions are recorded with Source="human:auto".
ClassMethod AutoApprove() As %Boolean
{
    quit (+$get(^IOA.Config("autoapprove")) = 1)
}

/// Set ^IOA.Config("autoapprove") to 1 or 0.
ClassMethod SetAutoApprove(pOn As %Boolean = 1) As %Status
{
    set ^IOA.Config("autoapprove") = $select(+pOn:1, 1:0)
    quit $$$OK
}

/// Whether recording live responses into replay fixtures is enabled (env IOA_RECORD=1)
ClassMethod RecordEnabled() As %Boolean
{
    set val = ..GetVar("IOA_RECORD")
    quit $select((val="1")||($zconvert(val,"L")="true"):1, 1:0)
}

/// Directory monitored for incoming HL7 case files (env IOA_CASES_IN, default /irisdev/app/cases/in/)
ClassMethod CasesIn() As %String
{
    set val = ..GetVar("IOA_CASES_IN")
    quit $select(val="":..#DEFAULTCASESIN, 1:val)
}

/// Resolve active LLM profile, provider, model, key variable name, API key reference, paths, and mode (LIVE|REPLAY).
/// Default profile is "openai" (provider=openai, keyVar=OPENAI_API_KEY, default model=gpt-5.4-mini, fallback=gpt-4.1-mini).
/// Alternate profile is "openrouter" (provider=openrouter, keyVar=OPENROUTER_API_KEY, default model=google/gemini-2.5-flash).
/// LLM_MODEL overrides the profile default model when non-empty.
/// LIVE mode is strictly opt-in: requires active profile key AND (IOA_LIVE=1 or ^IOA.Config("live")=1) AND REPLAY'=1.
/// REPLAY=1 forces REPLAY mode even when the active profile key and IOA_LIVE=1 are present.
/// Never includes the raw API key in pConfig or the returned %DynamicObject.
ClassMethod Resolve(Output pConfig, ByRef pOverrides) As %DynamicObject
{
    kill pConfig
    set rawProfile = ..GetVar("LLM_PROFILE", .pOverrides)
    set normProfile = $zconvert($select(rawProfile="":"openai", 1:rawProfile), "L")
    set profile = $select(normProfile="openrouter":"openrouter", 1:"openai")
    set rawModel = ..GetVar("LLM_MODEL", .pOverrides)

    if (profile = "openrouter") {
        set provider = "openrouter"
        set model = $select(rawModel="":..#DEFAULTMODELOPENROUTER, 1:rawModel)
        set keyVar = "OPENROUTER_API_KEY"
        set configComplete = (model '= "")
    } else {
        set provider = "openai"
        // Default: gpt-5.4-mini (documented fallback: gpt-4.1-mini)
        set model = $select(rawModel="":..#DEFAULTMODELOPENAI, 1:rawModel)
        set keyVar = "OPENAI_API_KEY"
        set configComplete = (model '= "")
    }

    set apiKeyRef = "@{env:" _ keyVar _ "}"
    set keyPresent = ..IsKeyPresent(keyVar, .pOverrides)
    set liveEnabled = ..IsLiveEnabled(.pOverrides)
    set replayVar = ..GetVar("REPLAY", .pOverrides)
    set forceReplay = ((replayVar = "1") || ($zconvert(replayVar, "L") = "true"))

    set mode = $select((configComplete && keyPresent && liveEnabled && 'forceReplay):"LIVE", 1:"REPLAY")

    set rawReplayDir = ..GetVar("IOA_REPLAY_DIR", .pOverrides)
    set replayDir = $select(rawReplayDir="":..#DEFAULTREPLAYDIR, 1:rawReplayDir)

    set rawRecord = ..GetVar("IOA_RECORD", .pOverrides)
    set recordEnabled = $select((rawRecord="1")||($zconvert(rawRecord,"L")="true"):1, 1:0)

    set rawCasesIn = ..GetVar("IOA_CASES_IN", .pOverrides)
    set casesIn = $select(rawCasesIn="":..#DEFAULTCASESIN, 1:rawCasesIn)

    set pConfig("profile") = profile
    set pConfig("provider") = provider
    set pConfig("model") = model
    set pConfig("keyVar") = keyVar
    set pConfig("apiKeyRef") = apiKeyRef
    set pConfig("keyPresent") = keyPresent
    set pConfig("liveEnabled") = liveEnabled
    set pConfig("forceReplay") = forceReplay
    set pConfig("configComplete") = configComplete
    set pConfig("mode") = mode
    set pConfig("replayDir") = replayDir
    set pConfig("recordEnabled") = recordEnabled
    set pConfig("casesIn") = casesIn

    set result = {}
    set result.profile = profile
    set result.provider = provider
    set result.model = model
    set result.keyVar = keyVar
    set result.apiKeyRef = apiKeyRef
    set result.keyPresent = $select(keyPresent:1, 1:0)
    set result.liveEnabled = $select(liveEnabled:1, 1:0)
    set result.forceReplay = $select(forceReplay:1, 1:0)
    set result.configComplete = $select(configComplete:1, 1:0)
    set result.mode = mode
    set result.replayDir = replayDir
    set result.recordEnabled = recordEnabled
    set result.casesIn = casesIn
    quit result
}

/// Print current resolved profile status without exposing secret values
ClassMethod PrintStatus() As %Status
{
    do ..Resolve(.cfg)
    write "LLM_PROFILE=", $get(cfg("profile")), !
    write "PROVIDER=", $get(cfg("provider")), !
    write "LLM_MODEL=", $get(cfg("model")), !
    write "KEY_VAR=", $get(cfg("keyVar")), !
    write "API_KEY_REF=", $get(cfg("apiKeyRef")), !
    write "KEY_PRESENT=", $select(+$get(cfg("keyPresent")):"YES", 1:"NO"), !
    write "LIVE_ENABLED=", $select(+$get(cfg("liveEnabled")):"YES", 1:"NO"), !
    write "LLM_MODE=", $get(cfg("mode")), !
    write "REPLAY_DIR=", $get(cfg("replayDir")), !
    write "RECORD_ENABLED=", $get(cfg("recordEnabled")), !
    write "CASES_IN=", $get(cfg("casesIn")), !
    quit $$$OK
}

/// Verify profile/mode transitions using in-memory test overrides (no real keys or real env):
/// 1. openai (no key) -> REPLAY (default model gpt-5.4-mini)
/// 2. openai (with key, IOA_LIVE=0, live=0) -> REPLAY (LIVE is opt-in)
/// 3. openai (with key + IOA_LIVE=1) -> LIVE
/// 4. openai (with key + SetLive(1)) -> LIVE, SetLive(0) -> REPLAY
/// 5. openrouter (no key) -> REPLAY (default model google/gemini-2.5-flash)
/// 6. openrouter (with key, IOA_LIVE=0, live=0) -> REPLAY
/// 7. openrouter (with key + IOA_LIVE=1) -> LIVE
/// 8. openai (with key + IOA_LIVE=1 + REPLAY=1) -> REPLAY
/// 9. openrouter (with key + IOA_LIVE=1 + REPLAY=1) -> REPLAY
ClassMethod CheckSwitching() As %Boolean
{
    set allPass = 1
    set hadLiveGlobal = $data(^IOA.Config("live"))#2
    set savedLiveGlobal = $get(^IOA.Config("live"))

    // 1. openai without key -> REPLAY
    kill ov
    set ov("LLM_PROFILE") = "openai"
    set ov("LLM_MODEL") = ""
    set ov("OPENAI_API_KEY") = ""
    set ov("IOA_LIVE") = "0"
    set ov("live") = 0
    set ov("REPLAY") = ""
    do ..Resolve(.cfg1, .ov)
    set pass1 = (($get(cfg1("profile"))="openai") && ($get(cfg1("provider"))="openai") && ($get(cfg1("model"))="gpt-5.4-mini") && ($get(cfg1("keyVar"))="OPENAI_API_KEY") && ($get(cfg1("apiKeyRef"))="@{env:OPENAI_API_KEY}") && ('..KeyPresent(.ov)) && ($get(cfg1("mode"))="REPLAY"))
    write "TRANSITION_1_OPENAI_NO_KEY=", $select(pass1:"PASS", 1:"FAIL"), !
    if 'pass1 { set allPass = 0 }

    // 2. openai with key but IOA_LIVE=0 and live=0 -> REPLAY (safety: key alone never enables LIVE)
    kill ov
    set ov("LLM_PROFILE") = "openai"
    set ov("LLM_MODEL") = ""
    set ov("OPENAI_API_KEY") = "test-override-dummy-key"
    set ov("IOA_LIVE") = "0"
    set ov("live") = 0
    set ov("REPLAY") = ""
    do ..Resolve(.cfg2, .ov)
    set pass2 = (($get(cfg2("profile"))="openai") && (..KeyPresent(.ov)=1) && ($get(cfg2("mode"))="REPLAY"))
    write "TRANSITION_2_OPENAI_KEY_DEFAULT_REPLAY=", $select(pass2:"PASS", 1:"FAIL"), !
    if 'pass2 { set allPass = 0 }

    // 3. openai with test override key + IOA_LIVE=1 -> LIVE
    kill ov
    set ov("LLM_PROFILE") = "openai"
    set ov("LLM_MODEL") = ""
    set ov("OPENAI_API_KEY") = "test-override-dummy-key"
    set ov("IOA_LIVE") = "1"
    set ov("live") = 0
    set ov("REPLAY") = ""
    do ..Resolve(.cfg3, .ov)
    set pass3 = (($get(cfg3("profile"))="openai") && ($get(cfg3("provider"))="openai") && ($get(cfg3("model"))="gpt-5.4-mini") && ($get(cfg3("keyVar"))="OPENAI_API_KEY") && ($get(cfg3("apiKeyRef"))="@{env:OPENAI_API_KEY}") && ($get(cfg3("mode"))="LIVE"))
    write "TRANSITION_3_OPENAI_KEY_IOA_LIVE=", $select(pass3:"PASS", 1:"FAIL"), !
    if 'pass3 { set allPass = 0 }

    // 4. openai with test override key + SetLive(1) -> LIVE, SetLive(0) -> REPLAY
    kill ov
    set ov("LLM_PROFILE") = "openai"
    set ov("LLM_MODEL") = ""
    set ov("OPENAI_API_KEY") = "test-override-dummy-key"
    set ov("IOA_LIVE") = "0"
    set ov("REPLAY") = ""
    do ..SetLive(1)
    do ..Resolve(.cfg4a, .ov)
    do ..SetLive(0)
    do ..Resolve(.cfg4b, .ov)
    set pass4 = (($get(cfg4a("mode"))="LIVE") && ($get(cfg4b("mode"))="REPLAY") && ('$data(^IOA.Config("live"))))
    write "TRANSITION_4_OPENAI_SETLIVE_TOGGLE=", $select(pass4:"PASS", 1:"FAIL"), !
    if 'pass4 { set allPass = 0 }

    // 5. openrouter without key -> REPLAY
    kill ov
    set ov("LLM_PROFILE") = "openrouter"
    set ov("LLM_MODEL") = ""
    set ov("OPENROUTER_API_KEY") = ""
    set ov("IOA_LIVE") = "0"
    set ov("live") = 0
    set ov("REPLAY") = ""
    do ..Resolve(.cfg5, .ov)
    set pass5 = (($get(cfg5("profile"))="openrouter") && ($get(cfg5("provider"))="openrouter") && ($get(cfg5("model"))="google/gemini-2.5-flash") && ($get(cfg5("keyVar"))="OPENROUTER_API_KEY") && ($get(cfg5("apiKeyRef"))="@{env:OPENROUTER_API_KEY}") && ('..KeyPresent(.ov)) && ($get(cfg5("mode"))="REPLAY"))
    write "TRANSITION_5_OPENROUTER_NO_KEY=", $select(pass5:"PASS", 1:"FAIL"), !
    if 'pass5 { set allPass = 0 }

    // 6. openrouter with key but IOA_LIVE=0 and live=0 -> REPLAY
    kill ov
    set ov("LLM_PROFILE") = "openrouter"
    set ov("LLM_MODEL") = ""
    set ov("OPENROUTER_API_KEY") = "test-override-dummy-key"
    set ov("IOA_LIVE") = "0"
    set ov("live") = 0
    set ov("REPLAY") = ""
    do ..Resolve(.cfg6, .ov)
    set pass6 = (($get(cfg6("profile"))="openrouter") && (..KeyPresent(.ov)=1) && ($get(cfg6("mode"))="REPLAY"))
    write "TRANSITION_6_OPENROUTER_KEY_DEFAULT_REPLAY=", $select(pass6:"PASS", 1:"FAIL"), !
    if 'pass6 { set allPass = 0 }

    // 7. openrouter with test override key + IOA_LIVE=1 -> LIVE
    kill ov
    set ov("LLM_PROFILE") = "openrouter"
    set ov("LLM_MODEL") = ""
    set ov("OPENROUTER_API_KEY") = "test-override-dummy-key"
    set ov("IOA_LIVE") = "1"
    set ov("live") = 0
    set ov("REPLAY") = ""
    do ..Resolve(.cfg7, .ov)
    set pass7 = (($get(cfg7("profile"))="openrouter") && ($get(cfg7("provider"))="openrouter") && ($get(cfg7("model"))="google/gemini-2.5-flash") && ($get(cfg7("keyVar"))="OPENROUTER_API_KEY") && ($get(cfg7("apiKeyRef"))="@{env:OPENROUTER_API_KEY}") && ($get(cfg7("mode"))="LIVE"))
    write "TRANSITION_7_OPENROUTER_KEY_IOA_LIVE=", $select(pass7:"PASS", 1:"FAIL"), !
    if 'pass7 { set allPass = 0 }

    // 8. openai with key + IOA_LIVE=1 + REPLAY=1 -> REPLAY
    kill ov
    set ov("LLM_PROFILE") = "openai"
    set ov("LLM_MODEL") = ""
    set ov("OPENAI_API_KEY") = "test-override-dummy-key"
    set ov("IOA_LIVE") = "1"
    set ov("live") = 1
    set ov("REPLAY") = "1"
    do ..Resolve(.cfg8, .ov)
    set pass8 = (($get(cfg8("profile"))="openai") && ($get(cfg8("mode"))="REPLAY"))
    write "TRANSITION_8_OPENAI_REPLAY_OVERRIDE=", $select(pass8:"PASS", 1:"FAIL"), !
    if 'pass8 { set allPass = 0 }

    // 9. openrouter with key + IOA_LIVE=1 + REPLAY=1 -> REPLAY
    kill ov
    set ov("LLM_PROFILE") = "openrouter"
    set ov("LLM_MODEL") = ""
    set ov("OPENROUTER_API_KEY") = "test-override-dummy-key"
    set ov("IOA_LIVE") = "1"
    set ov("live") = 1
    set ov("REPLAY") = "1"
    do ..Resolve(.cfg9, .ov)
    set pass9 = (($get(cfg9("profile"))="openrouter") && ($get(cfg9("mode"))="REPLAY"))
    write "TRANSITION_9_OPENROUTER_REPLAY_OVERRIDE=", $select(pass9:"PASS", 1:"FAIL"), !
    if 'pass9 { set allPass = 0 }

    if hadLiveGlobal {
        set ^IOA.Config("live") = savedLiveGlobal
    } else {
        kill ^IOA.Config("live")
    }
    set ^IOA.Config("mode") = ..Mode()

    write "CHECK_SWITCHING=", $select(allPass:"PASS", 1:"FAIL"), !
    write $select(allPass:"PASS", 1:"FAIL"), !
    quit allPass
}

}
