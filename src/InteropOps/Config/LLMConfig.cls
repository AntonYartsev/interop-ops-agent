Class InteropOps.Config.LLMConfig Extends %RegisteredObject
{

/// Default OpenAI model is gpt-5.4-mini (documented fallback: gpt-4.1-mini)
Parameter DEFAULTMODELOPENAI = "gpt-5.4-mini";

/// Documented fallback OpenAI model if gpt-5.4-mini is unavailable
Parameter FALLBACKMODELOPENAI = "gpt-4.1-mini";

/// Default OpenRouter model
Parameter DEFAULTMODELOPENROUTER = "google/gemini-2.5-flash";

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

/// Whether the IRIS process itself sees a non-empty pKeyVar ($SYSTEM.Util.GetEnviron), or a test override.
/// This is what "@{env:VAR}" resolves from, so it is the only key check that may enable LIVE.
/// No ^IOA.Config("key_present") flag, no .env fallback (both can say "present" while the process has no key).
/// Never stores or returns the secret key itself.
ClassMethod ProcessKeyPresent(pKeyVar As %String, ByRef pOverrides) As %Boolean
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
    quit ($zstrip($SYSTEM.Util.GetEnviron(pKeyVar), "<>W") '= "")
}

/// Whether the IRIS process sees the API key of the active profile (1 or 0), see ProcessKeyPresent.
/// Never returns or logs the secret key itself.
ClassMethod KeyPresent(ByRef pOverrides) As %Boolean
{
    do ..Resolve(.cfg, .pOverrides)
    quit +$get(cfg("keyPresent"), 0)
}

/// Enable or disable runtime LIVE mode via ^IOA.Config("live").
/// SetLive(1) sets ^IOA.Config("live")=1; SetLive(0) sets ^IOA.Config("live")=0, which turns LIVE off
/// even when env IOA_LIVE=1 (the global wins over env, see Precedence below).
ClassMethod SetLive(pOn As %Boolean = 0) As %Status
{
    set ^IOA.Config("live") = $select(+pOn:1, 1:0)
    set ^IOA.Config("mode") = ..Mode()
    quit $$$OK
}

/// Precedence for runtime flags (live, record):
///   1. test override (pOverrides(name)), "" = not set
///   2. ^IOA.Config(name) when defined and non-empty. Setup.ResetDemo, Setup.Reload and
///      Setup.InitAndStartProduction seed it from env (SeedFlagsFromEnv: env value, 0 when unset);
///      in a run SetLive / SetRecord change it (demo.sh --live / --replay, tools/record/live_record.sh).
///   3. env (IOA_LIVE / IOA_RECORD; GetVar also falls back to the synced copy ^IOA.Config("IOA_...")),
///      only reached when the global was killed.
/// AutoApprove has no env path at runtime: ^IOA.Config("autoapprove") only (SyncEnvToGlobal seeds it from IOA_AUTOAPPROVE).
/// REPLAY=1 (env) is a documented kill switch: it forces REPLAY whatever live says.
/// Returns 1 if a value was found at levels 1-2 (pVal = 0|1), 0 if the env level decides.
ClassMethod FlagFromConfig(pName As %String, ByRef pOverrides, Output pVal As %Boolean) As %Boolean [ Private ]
{
    set pVal = 0, raw = "", found = 0
    if $isobject($get(pOverrides)) && pOverrides.%IsDefined(pName) {
        set raw = $zstrip(pOverrides.%Get(pName), "<>W"), found = 1
    } elseif $data(pOverrides(pName))#2 {
        set raw = $zstrip(pOverrides(pName), "<>W"), found = 1
    } elseif ($data(^IOA.Config(pName))#2) {
        set raw = $zstrip(^IOA.Config(pName), "<>W")
    }
    if (raw = "") { quit 0 }
    set pVal = ..Truthy(raw)
    quit 1
}

/// Raw env value of a flag variable: test override, else process env, else .env (Setup.ReadDotEnv).
/// "" = not set. The synced copy ^IOA.Config("IOA_...") is not used here (it can be stale).
ClassMethod EnvFlagRaw(pVar As %String, ByRef pOverrides) As %String
{
    if $data(pOverrides(pVar))#2 { quit $zstrip(pOverrides(pVar), "<>W") }
    set val = $zstrip($SYSTEM.Util.GetEnviron(pVar), "<>W")
    if val = "" {
        do ##class(InteropOps.Setup).ReadDotEnv(.env)
        set val = $zstrip($get(env(pVar)), "<>W")
    }
    quit val
}

/// Copy the env flags into ^IOA.Config: live from IOA_LIVE, record from IOA_RECORD (1/true/yes = 1),
/// 0 when the env variable is not set. Called by Setup.ResetDemo, Setup.Reload, Setup.InitAndStartProduction.
/// Returns e.g. "live=0(IOA_LIVE unset) record=0(IOA_RECORD unset)"; values are flags only, never secrets.
/// pApply=0 (tests): computes pFlags("live"/"record") without writing ^IOA.Config.
ClassMethod SeedFlagsFromEnv(ByRef pOverrides, pApply As %Boolean = 1, Output pFlags) As %String
{
    kill pFlags
    set out = ""
    for pair = "live:IOA_LIVE", "record:IOA_RECORD" {
        set flag = $piece(pair, ":", 1), var = $piece(pair, ":", 2)
        set raw = ..EnvFlagRaw(var, .pOverrides)
        set val = $select(raw = "":0, 1:..Truthy(raw))
        set pFlags(flag) = val
        set:pApply ^IOA.Config(flag) = val
        set out = out _ $select(out = "":"", 1:" ") _ flag _ "=" _ val _ "(" _ var _ $select(raw = "":" unset", 1:" set") _ ")"
    }
    set:pApply ^IOA.Config("mode") = ..Mode()
    quit out
}

/// "1" / "true" / "yes" (any case) -> 1, anything else -> 0
ClassMethod Truthy(pVal As %String) As %Boolean
{
    set v = $zconvert($zstrip(pVal, "<>W"), "L")
    quit ((v = "1") || (v = "true") || (v = "yes"))
}

/// Whether LIVE is enabled: ^IOA.Config("live") when set (0 or 1), else env IOA_LIVE=1.
/// LIVE still needs the key and no REPLAY=1 (see Resolve).
ClassMethod IsLiveEnabled(ByRef pOverrides) As %Boolean
{
    if ..FlagFromConfig("live", .pOverrides, .val) { quit val }
    quit ..Truthy(..GetVar("IOA_LIVE", .pOverrides))
}

/// Pure mode decision, no globals, env or I/O: "LIVE" only when the profile config is complete AND the key is
/// present AND live is enabled AND REPLAY=1 is not set; anything else is "REPLAY". Resolve() (and so Mode())
/// uses exactly this function, so CheckSwitching can test the decision with injected inputs.
ClassMethod ModeFor(pConfigComplete As %Boolean, pKeyPresent As %Boolean, pLive As %Boolean, pForceReplay As %Boolean) As %String
{
    quit $select((+pConfigComplete && +pKeyPresent && +pLive && '+pForceReplay):"LIVE", 1:"REPLAY")
}

/// Pure: warning text when LIVE was requested but cannot be used, "" otherwise. Names the variable, never a value.
ClassMethod ModeWarningFor(pConfigComplete As %Boolean, pKeyPresent As %Boolean, pLive As %Boolean, pForceReplay As %Boolean, pKeyVar As %String) As %String
{
    quit:('+pLive)||(+pForceReplay) ""
    quit:'+pConfigComplete "LIVE requested but the model of the active profile is empty -> REPLAY"
    quit:'+pKeyPresent "LIVE requested but " _ pKeyVar _ " not set in IRIS process -> REPLAY"
    quit ""
}

/// Current mode warning ("" = none), for demo.sh / check.sh / PrintStatus. Never contains a key value.
ClassMethod ModeWarning() As %String
{
    do ..Resolve(.cfg)
    quit $get(cfg("warning"))
}

/// Active mode: "LIVE" only if active profile key is non-empty AND live is explicitly enabled
/// (^IOA.Config("live")=1, or env IOA_LIVE=1 when the global is not set) AND REPLAY'=1; otherwise "REPLAY".
/// LIVE requested but key not in the IRIS process -> REPLAY plus ModeWarning(), logged once per process (Event Log).
/// MOCK is not a config mode: ProviderFactory.Kind() returns MOCK for an allowed local mock URL unless REPLAY=1 (KindFor).
ClassMethod Mode() As %String
{
    do ..Resolve(.cfg)
    set warn = $get(cfg("warning"))
    if (warn '= "") && '$data(^||IOA.ModeWarned(warn)) {
        // once per process and text: Mode() is called per message and per Decision row
        set ^||IOA.ModeWarned(warn) = 1
        try { do ##class(Ens.Util.Log).LogWarning($classname(), "Mode", warn) } catch { }
    }
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

/// Directory containing deterministic replay fixtures (env IOA_REPLAY_DIR, default Util.Paths.ReplayDir():
/// IPM install directory replay/, else /irisdev/app/replay/, else /home/irisowner/dev/replay/)
ClassMethod ReplayDir() As %String
{
    set val = ..GetVar("IOA_REPLAY_DIR")
    quit $select(val="":##class(InteropOps.Util.Paths).ReplayDir(), 1:val)
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

/// Whether recording cassettes is enabled. ^IOA.Config("record") when set (SetRecord), else the legacy
/// ^IOA.Config("record_override") (synonym, read only when "record" is not set), else env IOA_RECORD=1.
ClassMethod RecordEnabled(ByRef pOverrides) As %Boolean
{
    if ..FlagFromConfig("record", .pOverrides, .val) { quit val }
    if ..FlagFromConfig("record_override", .pOverrides, .val) { quit val }
    quit ..Truthy(..GetVar("IOA_RECORD", .pOverrides))
}

/// Set ^IOA.Config("record") to 1 or 0 (wins over env IOA_RECORD and over the legacy "record_override").
ClassMethod SetRecord(pOn As %Boolean = 0) As %Status
{
    set ^IOA.Config("record") = $select(+pOn:1, 1:0)
    quit $$$OK
}

/// Directory monitored for incoming HL7 case files (env IOA_CASES_IN, default Util.Paths.CasesDir() in/)
ClassMethod CasesIn() As %String
{
    set val = ..GetVar("IOA_CASES_IN")
    quit $select(val="":##class(InteropOps.Util.Paths).CasesDir()_"in/", 1:val)
}

/// Resolve active LLM profile, provider, model, key variable name, API key reference, paths, and mode (LIVE|REPLAY).
/// Default profile is "openai" (provider=openai, keyVar=OPENAI_API_KEY, default model=gpt-5.4-mini, fallback=gpt-4.1-mini).
/// Alternate profile is "openrouter" (provider=openrouter, keyVar=OPENROUTER_API_KEY, default model=google/gemini-2.5-flash).
/// LLM_MODEL overrides the profile default model when non-empty.
/// LIVE mode is strictly opt-in: requires the active profile key in the IRIS process env (ProcessKeyPresent) AND live enabled (^IOA.Config("live") when set, else IOA_LIVE=1) AND REPLAY'=1.
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
    // LIVE needs the key in the IRIS process env (what "@{env:VAR}" reads); the .env / key_present view is display only
    set keyPresent = ..ProcessKeyPresent(keyVar, .pOverrides)
    set keyConfigured = ..IsKeyPresent(keyVar, .pOverrides)
    set liveEnabled = ..IsLiveEnabled(.pOverrides)
    set replayVar = ..GetVar("REPLAY", .pOverrides)
    set forceReplay = ((replayVar = "1") || ($zconvert(replayVar, "L") = "true"))

    set mode = ..ModeFor(configComplete, keyPresent, liveEnabled, forceReplay)
    set warning = ..ModeWarningFor(configComplete, keyPresent, liveEnabled, forceReplay, keyVar)

    set rawReplayDir = ..GetVar("IOA_REPLAY_DIR", .pOverrides)
    set replayDir = $select(rawReplayDir="":##class(InteropOps.Util.Paths).ReplayDir(), 1:rawReplayDir)

    set recordEnabled = ..RecordEnabled(.pOverrides)

    set rawCasesIn = ..GetVar("IOA_CASES_IN", .pOverrides)
    set casesIn = $select(rawCasesIn="":##class(InteropOps.Util.Paths).CasesDir()_"in/", 1:rawCasesIn)

    set pConfig("profile") = profile
    set pConfig("provider") = provider
    set pConfig("model") = model
    set pConfig("keyVar") = keyVar
    set pConfig("apiKeyRef") = apiKeyRef
    set pConfig("keyPresent") = keyPresent
    set pConfig("keyConfigured") = keyConfigured
    set pConfig("warning") = warning
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
    set result.keyConfigured = $select(keyConfigured:1, 1:0)
    set result.warning = warning
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
    write "KEY_CONFIGURED=", $select(+$get(cfg("keyConfigured")):"YES", 1:"NO"), " (process env, key_present flag or .env; display only)", !
    write "LIVE_ENABLED=", $select(+$get(cfg("liveEnabled")):"YES", 1:"NO"), !
    write "LLM_MODE=", $get(cfg("mode")), !
    write:$get(cfg("warning"))'="" "MODE_WARNING=", cfg("warning"), !
    write "PROVIDER_KIND=", ##class(InteropOps.Agent.ProviderFactory).Kind(), !
    write:##class(InteropOps.Agent.ProviderFactory).KindWarning()'="" "KIND_WARNING=", ##class(InteropOps.Agent.ProviderFactory).KindWarning(), !
    write "REPLAY_DIR=", $get(cfg("replayDir")), !
    write "RECORD_ENABLED=", $get(cfg("recordEnabled")), !
    write "CASES_IN=", $get(cfg("casesIn")), !
    quit $$$OK
}

/// Verify profile/mode transitions using in-memory test overrides (no real keys or real env):
/// 1. openai (no key) -> REPLAY (default model gpt-5.4-mini)
/// 2. openai (with key, IOA_LIVE=0, live=0) -> REPLAY (LIVE is opt-in)
/// 3. openai (with key + IOA_LIVE=1) -> LIVE
/// 4. openai (with key + live=1 override) -> LIVE, live=0 -> REPLAY; ModeFor truth table (16 cases)
/// 10. key + IOA_LIVE=1 + live=0 -> REPLAY; 11. record precedence; 12. SeedFlagsFromEnv (dry)
/// No test writes ^IOA.Config or ^IOA.Dev, builds a provider or sends a message; the real flags are compared
/// before/after. Refuses (returns 0) while the production runs and cases/in has files.
/// 5. openrouter (no key) -> REPLAY (default model google/gemini-2.5-flash)
/// 6. openrouter (with key, IOA_LIVE=0, live=0) -> REPLAY
/// 7. openrouter (with key + IOA_LIVE=1) -> LIVE
/// 8. openai (with key + IOA_LIVE=1 + REPLAY=1) -> REPLAY
/// 9. openrouter (with key + IOA_LIVE=1 + REPLAY=1) -> REPLAY
/// 13. live + key in process -> LIVE; live + no key -> REPLAY + ModeWarning; 14. REPLAY=1 env beats MOCK, MOCK needs no key
/// 15. MOCK host allowlist (ProviderFactory.KindFor); 16. budget caps apply to every non-REPLAY kind (MOCK too):
///     source guard in Agent.Operation + Reserve / OverUSD on a saved and restored ^IOA.Budget (no provider, no call)
ClassMethod CheckSwitching() As %Boolean
{
    // Guard: refuse while the production is running and cases/in has files (a run may be in progress)
    set why = ..SwitchingTestBusy()
    if why '= "" {
        write "CHECK_SWITCHING=REFUSED (", why, ")", !
        write "FAIL", !
        quit 0
    }
    set allPass = 1
    set before = ..RealFlagsSnapshot()

    // 1-3, 5-10: Resolve with test overrides (a key alone never enables LIVE; REPLAY=1 and live=0 win)
    //     $LB(n, label, profile, key, IOA_LIVE, live, REPLAY, expected mode)
    set dk = "test-override-dummy-key", ptr = 0
    set cases = ""
    set cases = cases _ $lb($lb(1, "OPENAI_NO_KEY", "openai", "", "0", 0, "", "REPLAY"))
    set cases = cases _ $lb($lb(2, "OPENAI_KEY_DEFAULT_REPLAY", "openai", dk, "0", 0, "", "REPLAY"))
    set cases = cases _ $lb($lb(3, "OPENAI_KEY_IOA_LIVE", "openai", dk, "1", "", "", "LIVE"))
    set cases = cases _ $lb($lb(5, "OPENROUTER_NO_KEY", "openrouter", "", "0", 0, "", "REPLAY"))
    set cases = cases _ $lb($lb(6, "OPENROUTER_KEY_DEFAULT_REPLAY", "openrouter", dk, "0", 0, "", "REPLAY"))
    set cases = cases _ $lb($lb(7, "OPENROUTER_KEY_IOA_LIVE", "openrouter", dk, "1", "", "", "LIVE"))
    set cases = cases _ $lb($lb(8, "OPENAI_REPLAY_OVERRIDE", "openai", dk, "1", 1, "1", "REPLAY"))
    set cases = cases _ $lb($lb(9, "OPENROUTER_REPLAY_OVERRIDE", "openrouter", dk, "1", 1, "1", "REPLAY"))
    set cases = cases _ $lb($lb(10, "LIVE_GLOBAL_OFF_WINS", "openai", dk, "1", 0, "", "REPLAY"))
    while $listnext(cases, ptr, row) {
        set $listbuild(n, label, prof, key, envLive, live, replay, want) = row
        set kv = $zconvert(prof, "U") _ "_API_KEY"
        kill ov, cfg
        set ov("LLM_PROFILE") = prof, ov("LLM_MODEL") = "", ov(kv) = key, ov("IOA_LIVE") = envLive, ov("live") = live, ov("REPLAY") = replay
        do ..Resolve(.cfg, .ov)
        set pass = (($get(cfg("profile")) = prof) && ($get(cfg("provider")) = prof) && ($get(cfg("model")) = $select(prof = "openai": ..#DEFAULTMODELOPENAI, 1: ..#DEFAULTMODELOPENROUTER)) && ($get(cfg("keyVar")) = kv) && ($get(cfg("apiKeyRef")) = ("@{env:" _ kv _ "}")) && (..KeyPresent(.ov) = (key '= "")) && ($get(cfg("mode")) = want))
        write "TRANSITION_", n, "_", label, "=", $select(pass: "PASS", 1: "FAIL"), !
        if 'pass { set allPass = 0 }
    }

    // 4. live toggle (what SetLive(1)/SetLive(0) store) injected as an override, never written to ^IOA.Config,
    //    plus the full ModeFor truth table: only (complete, key, live, no REPLAY) gives LIVE
    kill ov
    set ov("LLM_PROFILE") = "openai"
    set ov("LLM_MODEL") = ""
    set ov("OPENAI_API_KEY") = "test-override-dummy-key"
    set ov("IOA_LIVE") = "0"
    set ov("REPLAY") = ""
    set ov("live") = 1
    do ..Resolve(.cfg4a, .ov)
    set ov("live") = 0
    do ..Resolve(.cfg4b, .ov)
    set table = 1
    for cc = 0, 1 { for kp = 0, 1 { for lv = 0, 1 { for fr = 0, 1 {
        set want = $select(cc && kp && lv && 'fr:"LIVE", 1:"REPLAY")
        if ..ModeFor(cc, kp, lv, fr) '= want { set table = 0 }
    } } } }
    set pass4 = (($get(cfg4a("mode"))="LIVE") && ($get(cfg4b("mode"))="REPLAY") && table)
    write "TRANSITION_4_OPENAI_LIVE_TOGGLE_MODEFOR=", $select(pass4:"PASS", 1:"FAIL"), !
    if 'pass4 { set allPass = 0 }

    // 11. record: global "record" wins over env; legacy "record_override" only when "record" is not set
    kill ov
    set ov("IOA_RECORD") = "1", ov("record") = 0, ov("record_override") = 1
    set r1 = ..RecordEnabled(.ov)
    kill ov
    set ov("IOA_RECORD") = "0", ov("record") = "", ov("record_override") = 1
    set r2 = ..RecordEnabled(.ov)
    kill ov
    set ov("IOA_RECORD") = "1", ov("record") = "", ov("record_override") = ""
    set r3 = ..RecordEnabled(.ov)
    set pass11 = ((r1 = 0) && (r2 = 1) && (r3 = 1))
    write "TRANSITION_11_RECORD_PRECEDENCE=", $select(pass11:"PASS", 1:"FAIL"), !
    if 'pass11 { set allPass = 0 }

    // 12. SeedFlagsFromEnv (dry, the real globals are not written): env set -> 1, env unset -> 0;
    //     Resolve with the seeded value as the global value gives LIVE / REPLAY
    kill ov
    set ov("IOA_LIVE") = "1", ov("IOA_RECORD") = "yes"
    set seedA = ..SeedFlagsFromEnv(.ov, 0, .fA)
    kill ov
    set ov("IOA_LIVE") = "", ov("IOA_RECORD") = ""
    set seedB = ..SeedFlagsFromEnv(.ov, 0, .fB)
    kill ov
    set ov("LLM_PROFILE") = "openai", ov("OPENAI_API_KEY") = "test-override-dummy-key", ov("REPLAY") = "", ov("live") = fA("live")
    do ..Resolve(.cfg12a, .ov)
    set ov("live") = fB("live"), ov("IOA_LIVE") = "1"
    do ..Resolve(.cfg12b, .ov)
    set pass12 = ((fA("live") = 1) && (fA("record") = 1) && (fB("live") = 0) && (fB("record") = 0) && ($get(cfg12a("mode")) = "LIVE") && ($get(cfg12b("mode")) = "REPLAY"))
    write "TRANSITION_12_SEED_FROM_ENV=", $select(pass12:"PASS", 1:"FAIL"), " [", seedA, " | ", seedB, "]", !
    if 'pass12 { set allPass = 0 }

    // 13. live requested + key visible to the process (test override) -> LIVE, no warning;
    //     live requested + key empty -> REPLAY + warning that names the variable (never a value)
    kill ov
    set ov("LLM_PROFILE") = "openai", ov("OPENAI_API_KEY") = "test-override-dummy-key", ov("live") = 1, ov("REPLAY") = ""
    do ..Resolve(.cfg13a, .ov)
    set ov("OPENAI_API_KEY") = ""
    do ..Resolve(.cfg13b, .ov)
    set w13 = $get(cfg13b("warning"))
    set pass13 = (($get(cfg13a("mode")) = "LIVE") && ($get(cfg13a("warning")) = "") && ($get(cfg13b("mode")) = "REPLAY") && (w13 [ "OPENAI_API_KEY") && (w13 [ "not set in IRIS process") && '(w13 [ "test-override-dummy-key") && (..ModeWarningFor(1, 0, 1, 0, "X_KEY") [ "X_KEY") && (..ModeWarningFor(1, 0, 0, 0, "X_KEY") = "") && (..ModeWarningFor(1, 0, 1, 1, "X_KEY") = ""))
    write "TRANSITION_13_LIVE_NEEDS_PROCESS_KEY=", $select(pass13:"PASS", 1:"FAIL"), " [", w13, "]", !
    if 'pass13 { set allPass = 0 }

    // 14. ProviderFactory.KindFor: REPLAY=1 env beats MOCK; MOCK needs no key (Mode()=REPLAY + local mock -> MOCK); no mock URL -> Mode()
    set pf = "InteropOps.Agent.ProviderFactory", mu = "http://127.0.0.1:18080"
    set k1 = $classmethod(pf, "KindFor", "LIVE", 1, mu, .w1)
    set k2 = $classmethod(pf, "KindFor", "REPLAY", 1, mu, .w2)
    set k3 = $classmethod(pf, "KindFor", "LIVE", 0, "", .w3)
    set k4 = $classmethod(pf, "KindFor", "REPLAY", 0, "", .w4)
    set k5 = $classmethod(pf, "KindFor", "REPLAY", 0, mu, .w5)
    set pass14 = ((k1 = "REPLAY") && (w1 '= "") && (k2 = "REPLAY") && (w2 '= "") && (k3 = "LIVE") && (w3 = "") && (k4 = "REPLAY") && (w4 = "") && (k5 = "MOCK") && (w5 = ""))
    write "TRANSITION_14_REPLAY_BEATS_MOCK=", $select(pass14:"PASS", 1:"FAIL"), !
    if 'pass14 { set allPass = 0 }

    // 15. MOCK only for localhost / 127.0.0.1 / host.docker.internal (with or without key); look-alike and userinfo
    //     hosts are ignored with a warning and fall through to Mode() (LIVE or REPLAY)
    set ok15 = 1
    for u = "http://localhost:18080", "http://127.0.0.1:18080/v1", "http://host.docker.internal:18080", "https://LOCALHOST/v1" {
        set:$classmethod(pf, "KindFor", "LIVE", 0, u, .wu)'="MOCK" ok15 = 0
        set:$classmethod(pf, "KindFor", "REPLAY", 0, u, .wu)'="MOCK" ok15 = 0
    }
    for u = "http://localhost.evil.com:18080", "http://localhost@evil.com", "http://user:pw@localhost:18080", "http://evil.com", "http://evil.com#@localhost", "http://127.0.0.1.evil.com", "ftp://localhost", "localhost:18080", "http://localhost:99999", "http://localhost:80:81", "http://[::1]:18080", "http://local host", "http://localhost\@evil.com" {
        set ku = $classmethod(pf, "KindFor", "LIVE", 0, u, .wu)
        set:(ku'="LIVE")||(wu="") ok15 = 0
        set ku = $classmethod(pf, "KindFor", "REPLAY", 0, u, .wu)
        set:(ku'="REPLAY")||(wu="") ok15 = 0
    }
    write "TRANSITION_15_MOCK_HOST_ALLOWLIST=", $select(ok15:"PASS", 1:"FAIL"), !
    if 'ok15 { set allPass = 0 }

    // 16. MOCK budget: Agent.Operation applies the call cap (RunAgent -> Reserve) and the USD cap (OnMessage -> OverUSD)
    //     to every kind except REPLAY, so MOCK is capped like LIVE. Checked without a provider or a call:
    //     a) source guards: RunAgent caps when ProviderKind '= "REPLAY"; OnMessage handles REPLAY before OverUSD
    //     b) Reserve / OverUSD on test values in ^IOA.Budget, under a lock; ^IOA.Budget is saved and restored exactly
    set op = "InteropOps.Agent.Operation", ok16 = 1, note16 = ""
    set srcR = ..MethodSource(op, "RunAgent"), srcM = ..MethodSource(op, "OnMessage")
    if '(srcR [ "ProviderKind '= ""REPLAY""") || '(srcR [ "..Reserve(") { set ok16 = 0, note16 = note16 _ " runagent_guard" }
    set posR = $find(srcM, "ProviderKind = ""REPLAY"""), posU = $find(srcM, "..OverUSD(")
    if (posR = 0) || (posU = 0) || (posU < posR) { set ok16 = 0, note16 = note16 _ " onmessage_guard" }
    set budBefore = ..BudgetSnapshot()
    lock +^IOA.Budget:5
    if '$test {
        set ok16 = 0, note16 = note16 _ " budget_locked"
    } else {
        kill saved16
        merge saved16 = ^IOA.Budget
        try {
            set callCap = +$parameter(op, "BUDGETCALLS")
            set ^IOA.Budget("calls") = callCap - 2
            set r1 = $classmethod(op, "Reserve", 3, .u1)
            set r2 = $classmethod(op, "Reserve", 2, .u2)
            set c2 = +$get(^IOA.Budget("calls"))
            if '((r1 = 0) && (u1 = (callCap - 2)) && (r2 = 1) && (c2 = callCap)) { set ok16 = 0, note16 = note16 _ " calls" }
            kill ^IOA.Budget("usd")
            set o1 = $classmethod(op, "OverUSD", .s1, .usdCap)
            set ^IOA.Budget("usd") = usdCap
            set o2 = $classmethod(op, "OverUSD", .s2, .usdCap2)
            if 'o2 || ((usdCap > 0) && o1) { set ok16 = 0, note16 = note16 _ " usd" }
        } catch ex16 {
            set ok16 = 0, note16 = note16 _ " error"
        }
        kill ^IOA.Budget
        merge ^IOA.Budget = saved16
        lock -^IOA.Budget
    }
    set budAfter = ..BudgetSnapshot()
    if budAfter '= budBefore { set ok16 = 0, note16 = note16 _ " budget_not_restored" }
    write "TRANSITION_16_MOCK_BUDGET=", $select(ok16:"PASS", 1:"FAIL"), $select(note16 = "":"", 1:" [" _ $zstrip(note16, "<>W") _ "]"), !
    if 'ok16 { set allPass = 0 }

    // Real settings must be exactly as before (no test writes ^IOA.Config)
    set after = ..RealFlagsSnapshot()
    write "REAL_FLAGS_BEFORE=", before, " AFTER=", after, !
    if after '= before {
        write "REAL_FLAGS_CHANGED=1", !
        set allPass = 0
    }

    write "CHECK_SWITCHING=", $select(allPass:"PASS", 1:"FAIL"), !
    write $select(allPass:"PASS", 1:"FAIL"), !
    quit allPass
}

/// Source of one method from the class dictionary ("" if not found); used by CheckSwitching test 16.
ClassMethod MethodSource(pClass As %String, pMethod As %String) As %String [ Private ]
{
    set out = ""
    set md = ##class(%Dictionary.MethodDefinition).%OpenId(pClass _ "||" _ pMethod)
    if '$isobject(md) { quit "" }
    do md.Implementation.Rewind()
    while 'md.Implementation.AtEnd { set out = out _ md.Implementation.Read(32000) }
    quit out
}

/// ^IOA.Budget as one string (counters only), for CheckSwitching test 16 before/after.
ClassMethod BudgetSnapshot() As %String [ Private ]
{
    set out = "", ref = "^IOA.Budget"
    if $data(@ref)#2 { set out = "=" _ @ref }
    for {
        set ref = $query(@ref)
        quit:ref=""
        quit:$qsubscript(ref, 0)'="^IOA.Budget"
        set out = out _ "|" _ ref _ "=" _ @ref
    }
    quit out
}

/// Real live/record/mode settings as one string (flags only, no secrets), for CheckSwitching before/after.
ClassMethod RealFlagsSnapshot() As %String
{
    set out = ""
    for n = "live", "record", "record_override", "mode" {
        set out = out _ $select(out = "":"", 1:",") _ n _ "=" _ $select($data(^IOA.Config(n))#2:^IOA.Config(n), 1:"UNDEF")
    }
    quit out
}

/// "" when CheckSwitching may run; otherwise the reason: production running AND files in cases/in.
/// pDir: directory to inspect instead of CasesIn() (used to test the guard itself).
ClassMethod SwitchingTestBusy(pDir As %String = "") As %String
{
    set running = 0, prod = "", state = ""
    try {
        do ##class(Ens.Director).GetProductionStatus(.prod, .state)
        set running = (state = 1)
    } catch ex {
        set running = 1
    }
    quit:'running ""
    set dir = ##class(%File).NormalizeDirectory($select(pDir '= "":pDir, 1:..CasesIn())), n = 0
    set f = $zsearch(dir _ "*")
    while f '= "" {
        set name = $piece(f, "/", *)
        // count only what IOA.In.CaseFile picks up (FileSpec *.hl7; case-insensitive to stay conservative); skip dot-files such as .gitkeep
        if ($extract(name) '= ".") && ($zconvert($extract(name, *-3, *), "L") = ".hl7") && ##class(%File).Exists(f) && '##class(%File).DirectoryExists(f) { set n = n + 1 }
        set f = $zsearch("")
    }
    quit $select(n > 0:"production " _ prod _ " running and " _ n _ " file(s) in " _ dir, 1:"")
}

}
