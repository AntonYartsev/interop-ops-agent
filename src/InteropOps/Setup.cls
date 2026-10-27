Class InteropOps.Setup Extends %RegisteredObject
{

/// Parse key=value pairs from .env file on disk as fallback when process environment is empty.
/// Never logs or prints any values.
ClassMethod ReadDotEnv(Output pEnv) As %Status
{
    kill pEnv
    set envPath = "/irisdev/app/.env"
    if '##class(%File).Exists(envPath) {
        set envPath = "/home/irisowner/dev/.env"
    }
    if '##class(%File).Exists(envPath) {
        quit $$$OK
    }
    set stream = ##class(%Stream.FileCharacter).%New()
    set sc = stream.LinkToFile(envPath)
    if $$$ISERR(sc) {
        quit $$$OK
    }
    while 'stream.AtEnd {
        set line = $zstrip(stream.ReadLine(), "<>W")
        if (line = "") || ($extract(line, 1) = "#") {
            continue
        }
        set eqPos = $find(line, "=")
        if (eqPos > 2) {
            set key = $zstrip($extract(line, 1, eqPos - 2), "<>W")
            set val = $zstrip($extract(line, eqPos, *), "<>W")
            if (($extract(val, 1) = """") && ($extract(val, *) = """")) || (($extract(val, 1) = "'") && ($extract(val, *) = "'")) {
                set val = $extract(val, 2, * - 1)
            }
            if (key '= "") {
                set pEnv(key) = val
            }
        }
    }
    quit $$$OK
}

/// Synchronize LLM and IOA configuration from process environment (with .env fallback) into ^IOA.Config.
/// Never stores secret API keys or passwords in ^IOA.Config — only stores key_present (0/1).
ClassMethod SyncEnvToGlobal(Output pEnvMap) As %Status
{
    do ..ReadDotEnv(.pEnvMap)

    set nonSecretVars = $listbuild("LLM_PROFILE", "LLM_MODEL", "REPLAY", "IOA_LIVE", "IOA_RECORD", "IOA_CASES_IN", "IOA_REPLAY_DIR", "IOA_REVIEWER_USER", "IOA_AUTOAPPROVE")
    set ptr = 0
    while $listnext(nonSecretVars, ptr, varName) {
        set val = $zstrip($SYSTEM.Util.GetEnviron(varName), "<>W")
        if (val = "") && ($data(pEnvMap(varName))#2) {
            set val = $zstrip(pEnvMap(varName), "<>W")
        }
        set ^IOA.Config(varName) = val
    }

    // IOA_AUTOAPPROVE (env/.env) -> ^IOA.Config("autoapprove"); demo.sh overrides it per run (default 1, --manual 0)
    set autoVal = $zconvert($get(^IOA.Config("IOA_AUTOAPPROVE")), "L")
    if (autoVal '= "") {
        set ^IOA.Config("autoapprove") = $select((autoVal = "1") || (autoVal = "true") || (autoVal = "yes"):1, 1:0)
    } elseif '$data(^IOA.Config("autoapprove")) {
        set ^IOA.Config("autoapprove") = 0
    }

    set secretKeyVars = $listbuild("OPENAI_API_KEY", "OPENROUTER_API_KEY")
    set ptr = 0
    while $listnext(secretKeyVars, ptr, keyVar) {
        set keyVal = $zstrip($SYSTEM.Util.GetEnviron(keyVar), "<>W")
        if (keyVal = "") && ($data(pEnvMap(keyVar))#2) {
            set keyVal = $zstrip(pEnvMap(keyVar), "<>W")
        }
        set present = $select(keyVal'="":1, 1:0)
        set ^IOA.Config("key_present", keyVar) = present
    }

    do ##class(InteropOps.Config.LLMConfig).Resolve(.resolved)
    set activeKeyVar = $get(resolved("keyVar"), "OPENAI_API_KEY")
    set ^IOA.Config("key_present") = +$get(^IOA.Config("key_present", activeKeyVar))
    set ^IOA.Config("profile") = $get(resolved("profile"))
    set ^IOA.Config("model") = $get(resolved("model"))
    set ^IOA.Config("mode") = $get(resolved("mode"))
    set ^IOA.Config("keyVar") = activeKeyVar
    set ^IOA.Config("apiKeyRef") = $get(resolved("apiKeyRef"))
    set ^IOA.Config("replayDir") = $get(resolved("replayDir"))
    set ^IOA.Config("recordEnabled") = +$get(resolved("recordEnabled"))
    set ^IOA.Config("casesIn") = $get(resolved("casesIn"))

    quit $$$OK
}

/// Ensure Interoperability is enabled for the namespace
ClassMethod EnsureInterop(pNamespace As %String = "IRISAPP") As %Boolean
{
    new $NAMESPACE
    set $NAMESPACE = "%SYS"
    set isInterop = 0
    try {
        set isInterop = ##class(%Library.EnsembleMgr).IsEnsembleNamespace(pNamespace)
        if 'isInterop {
            do ##class(%Library.EnsembleMgr).EnableNamespace(pNamespace, 0)
            set isInterop = ##class(%Library.EnsembleMgr).IsEnsembleNamespace(pNamespace)
        }
    } catch ex {
        set isInterop = 1
    }
    quit isInterop
}

/// Ensure DeepSee/Analytics is enabled on /csp/irisapp and return 1 if enabled, 0 otherwise
ClassMethod EnsureDeepSee(pAppName As %String = "/csp/irisapp") As %Boolean
{
    new $NAMESPACE
    set $NAMESPACE = "%SYS"
    set enabled = 0
    if '##class(Security.Applications).Exists(pAppName) {
        // IRIS 2026.3 build 154: CreateNamespace in merge.cpf does not create the /csp/<ns> web app
        set cp("NameSpace") = "IRISAPP"
        set cp("Path") = "/usr/irissys/csp/irisapp"
        set cp("AutheEnabled") = 32
        set cp("IsNameSpaceDefault") = 1
        set cp("CSPZENEnabled") = 1
        set cp("Enabled") = 1
        set cp("DeepSeeEnabled") = 1
        set cp("MatchRoles") = ":%DB_IRISAPP_DATA:%DB_IRISAPP_CODE"
        set csc = ##class(Security.Applications).Create(pAppName, .cp)
        if $$$ISERR(csc) { do $SYSTEM.Status.DisplayError(csc) write ! }
    }
    if ##class(Security.Applications).Exists(pAppName) {
        do ##class(Security.Applications).Get(pAppName, .props)
        if +$get(props("DeepSeeEnabled")) '= 1 {
            set props("DeepSeeEnabled") = 1
            do ##class(Security.Applications).Modify(pAppName, .props)
        }
        try {
            do ##class(%Library.EnsembleMgr).EnableDeepSee(pAppName)
        } catch ex {
        }
        kill props
        do ##class(Security.Applications).Get(pAppName, .props)
        set enabled = +$get(props("DeepSeeEnabled"))
    }
    quit enabled
}

/// Idempotently ensure role IOA-Reviewers and reviewer user exist with Workflow Inbox access
/// and EnsLib.Workflow role membership in IOA-Reviewers.
/// Password comes strictly from IOA_REVIEWER_PASSWORD (never hardcoded; skipped with warning if empty).
ClassMethod EnsureReviewer() As %Status
{
    do ..SyncEnvToGlobal(.envMap)

    set roleName = "IOA-Reviewers"
    set user = $zstrip($SYSTEM.Util.GetEnviron("IOA_REVIEWER_USER"), "<>W")
    if (user = "") {
        set user = $zstrip($get(envMap("IOA_REVIEWER_USER")), "<>W")
    }
    if (user = "") {
        set user = $zstrip($get(^IOA.Config("IOA_REVIEWER_USER")), "<>W")
    }
    if (user = "") {
        set user = "reviewer"
    }

    set pwd = $zstrip($SYSTEM.Util.GetEnviron("IOA_REVIEWER_PASSWORD"), "<>W")
    if (pwd = "") {
        set pwd = $zstrip($get(envMap("IOA_REVIEWER_PASSWORD")), "<>W")
    }

    // 1. Configure Security.Roles and Security.Users in %SYS
    new $NAMESPACE
    set $NAMESPACE = "%SYS"

    set resCandidates = $listbuild(
        "%DB_IRISAPP:RW",
        "%DB_IRISSYS:R",
        "%Service_CSP:U",
        "%Service_WebGateway:U",
        "%Ens_Portal:U",
        "%Ens_Workflow:RWU",
        "%Ens_MessageHeader:R",
        "%Ens_MessageContent:R",
        "%Ens_Jobs:R",
        "%Ens_ProductionConfig:R",
        "%Ens_Rule:R",
        "%Ens_LookupTables:RWU",
        "%DeepSee_Portal:U",
        "%DeepSee_PortalEdit:U"
    )
    set resList = ""
    set ptr = 0
    while $listnext(resCandidates, ptr, entry) {
        set resName = $piece(entry, ":", 1)
        if ##class(Security.Resources).Exists(resName) {
            set resList = $select(resList="":entry, 1:resList _ "," _ entry)
        }
    }

    if '##class(Security.Roles).Exists(roleName) {
        do ##class(Security.Roles).Create(roleName, "InteropOps Workflow Reviewers", resList)
    } else {
        kill rProps
        do ##class(Security.Roles).Get(roleName, .rProps)
        set rProps("Resources") = resList
        do ##class(Security.Roles).Modify(roleName, .rProps)
    }

    set userRoles = roleName
    set candidateRoles = $listbuild("%EnsRole_Operator", "%EnsRole_WebDeveloper", "%EnsRole_Monitor", "%DB_IRISAPP")
    set ptr = 0
    while $listnext(candidateRoles, ptr, candRole) {
        if ##class(Security.Roles).Exists(candRole) {
            set userRoles = userRoles _ "," _ candRole
        }
    }

    if (pwd = "") {
        write "REVIEWER_WARNING=IOA_REVIEWER_PASSWORD is empty; skipping Security.Users setup for ", user, !
    } else {
        if '##class(Security.Users).Exists(user) {
            do ##class(Security.Users).Create(user, userRoles, pwd)
        }
        if ##class(Security.Users).Exists(user) {
            kill uProps
            do ##class(Security.Users).Get(user, .uProps)
            set uProps("Password") = pwd
            set uProps("Roles") = userRoles
            set uProps("NameSpace") = "IRISAPP"
            set uProps("ChangePassword") = 0
            set uProps("Enabled") = 1
            do ##class(Security.Users).Modify(user, .uProps)
            do ##class(Security.Users).UnExpireUserPasswords(user)
        }
        write "REVIEWER_USER=", user, !
        write "REVIEWER_ROLE=", roleName, !
    }

    // 2. Register EnsLib.Workflow RoleDefinition, UserDefinition, and membership in IRISAPP
    set $NAMESPACE = "IRISAPP"

    if '##class(EnsLib.Workflow.RoleDefinition).%ExistsId(roleName) {
        try {
            do ##class(EnsLib.Workflow.RoleDefinition).CreateRole(roleName)
        } catch ex {
        }
        if '##class(EnsLib.Workflow.RoleDefinition).%ExistsId(roleName) {
            set wfRole = ##class(EnsLib.Workflow.RoleDefinition).%New()
            set wfRole.Name = roleName
            do wfRole.%Save()
        }
    }

    if '##class(EnsLib.Workflow.UserDefinition).%ExistsId(user) {
        try {
            do ##class(EnsLib.Workflow.UserDefinition).CreateUser(user)
        } catch ex {
        }
        if '##class(EnsLib.Workflow.UserDefinition).%ExistsId(user) {
            set wfUser = ##class(EnsLib.Workflow.UserDefinition).%New()
            set wfUser.Name = user
            set wfUser.IsActive = 1
            do wfUser.%Save()
        }
    } else {
        set wfUser = ##class(EnsLib.Workflow.UserDefinition).%OpenId(user)
        if $isobject(wfUser) {
            set wfUser.IsActive = 1
            do wfUser.%Save()
        }
    }

    try {
        do ##class(EnsLib.Workflow.RoleDefinition).AddUserToRole(roleName, user)
    } catch ex {
    }

    quit $$$OK
}

/// Idempotently ensure the judge demo web application /demo (InteropOps.Demo.REST, see README "Judge demo page").
/// Unauthenticated access with exactly one application role, IOA-DemoWeb: Read on the namespace routine and globals
/// databases, Use on %Service_EmbeddedPython (the local KB embedder), Use on IOA_DemoWrite and SQL SELECT on the four
/// tables the page reads. No %Ens_*, portal, other service or %All rights; the page itself has no SQL/exec input.
/// Writes (run a case, approve/reject its review task) only inside InteropOps.Demo.Write: the privileged routine
/// application IOA.DemoWrite (type 4, routines of that class only, resource IOA_DemoWrite:U) adds role IOA-DemoWrite
/// (Read/Write on the globals database, nothing else) for the critical section; see InteropOps.Demo.Write.
ClassMethod EnsureDemoWebApp(pNamespace As %String = "IRISAPP") As %Status
{
    set roleName = "IOA-DemoWeb", app = "/demo", sc = $$$OK
    set wRole = "IOA-DemoWrite", wApp = "IOA.DemoWrite", wRes = "IOA_DemoWrite", wClass = "InteropOps.Demo.Write"
    set tables = $listbuild("InteropOps_Data.Decision", "Ens.MessageHeader", "EnsLib_Workflow.TaskResponse", "InteropOps_KB.Entry")
    try {
        new $NAMESPACE
        set $NAMESPACE = "%SYS"
        kill res
        set codeDb = "", dataRes = ""
        if ##class(Config.Namespaces).Get(pNamespace, .ns) {
            set codeDb = $get(ns("Routines"))
            for k = "Routines", "Globals" {
                kill db
                if ##class(Config.Databases).Get($get(ns(k)), .db) {
                    set dbo = ##class(SYS.Database).%OpenId($get(db("Directory")))
                    if $isobject(dbo) && (dbo.ResourceName '= "") {
                        set res(dbo.ResourceName) = "R"
                        set:(k = "Globals") dataRes = dbo.ResourceName
                    }
                }
            }
        }
        // KB search (local embedder) runs in Embedded Python
        set:##class(Security.Resources).Exists("%Service_EmbeddedPython") res("%Service_EmbeddedPython") = "U"
        // gate of the privileged routine application: only this role may ask for the write role
        if '##class(Security.Resources).Exists(wRes) {
            set sc = ##class(Security.Resources).Create(wRes, "InteropOps demo page: may raise IOA-DemoWrite in " _ wClass, "")
            quit:$$$ISERR(sc)
        }
        set res(wRes) = "U"
        set resList = "", r = ""
        for {
            set r = $order(res(r))
            quit:(r = "")
            set resList = $select(resList = "": "", 1: resList _ ",") _ r _ ":" _ res(r)
        }
        if '##class(Security.Roles).Exists(roleName) {
            set sc = ##class(Security.Roles).Create(roleName, "InteropOps judge demo page (/demo): read-only; writes via " _ wApp, resList)
        } else {
            kill rProps
            do ##class(Security.Roles).Get(roleName, .rProps)
            set rProps("Resources") = resList, rProps("Description") = "InteropOps judge demo page (/demo): read-only; writes via " _ wApp
            set sc = ##class(Security.Roles).Modify(roleName, .rProps)
        }
        quit:$$$ISERR(sc)

        // write role: Read/Write on the globals database only (raised in InteropOps.Demo.Write, dropped after)
        set wList = $select(dataRes = "": "", 1: dataRes _ ":RW")
        if '##class(Security.Roles).Exists(wRole) {
            set sc = ##class(Security.Roles).Create(wRole, "InteropOps demo page write section (" _ wClass _ " only)", wList)
        } else {
            kill rProps
            do ##class(Security.Roles).Get(wRole, .rProps)
            set rProps("Resources") = wList
            set sc = ##class(Security.Roles).Modify(wRole, .rProps)
        }
        quit:$$$ISERR(sc)

        kill pProps
        if ##class(Security.Applications).Exists(wApp) do ##class(Security.Applications).Get(wApp, .pProps)
        set pProps("Type") = 4
        set pProps("Description") = "InteropOps demo page: write role for " _ wClass
        set pProps("Routines") = wClass _ ":" _ codeDb _ ":1"
        set pProps("MatchRoles") = ":" _ wRole
        set pProps("Resource") = wRes
        set pProps("Enabled") = 1
        if ##class(Security.Applications).Exists(wApp) {
            set sc = ##class(Security.Applications).Modify(wApp, .pProps)
        } else {
            set sc = ##class(Security.Applications).Create(wApp, .pProps)
        }
        quit:$$$ISERR(sc)

        kill aProps
        if ##class(Security.Applications).Exists(app) do ##class(Security.Applications).Get(app, .aProps)
        set aProps("NameSpace") = pNamespace
        set aProps("DispatchClass") = "InteropOps.Demo.REST"
        set aProps("Description") = "InteropOps judge demo page"
        set aProps("AutheEnabled") = 64
        set aProps("MatchRoles") = ":" _ roleName
        set aProps("Resource") = ""
        set aProps("Enabled") = 1
        set aProps("UseCookies") = 0
        set aProps("InbndWebServicesEnabled") = 0
        set aProps("DeepSeeEnabled") = 0
        set aProps("iKnowEnabled") = 0
        if ##class(Security.Applications).Exists(app) {
            set sc = ##class(Security.Applications).Modify(app, .aProps)
        } else {
            set sc = ##class(Security.Applications).Create(app, .aProps)
        }
        quit:$$$ISERR(sc)

        set $NAMESPACE = pNamespace
        set ^IOA.Demo("cfg", "dataResource") = dataRes
        set ptr = 0
        while $listnext(tables, ptr, t) {
            set gsc = $SYSTEM.SQL.Security.GrantPrivilege("SELECT", t, "TABLE", roleName)
            if $$$ISERR(gsc) write "DEMO_WEBAPP_WARNING=grant SELECT on ", t, " failed", !
        }
        write "DEMO_WEBAPP=", app, " role=", roleName, " resources=", resList, " write=", wApp, "->", wRole, ":", wList, !
    } catch ex {
        set sc = ex.AsStatus()
    }
    if $$$ISERR(sc) write "DEMO_WEBAPP_WARNING=", $SYSTEM.Status.GetErrorText(sc), !
    quit sc
}

/// Idempotently load CSV lines (key,value) from file into Ens.Util.LookupTable "IOA.LabCodeMap",
/// skipping header and comment lines. Missing file logs a warning and returns $$$OK.
ClassMethod LoadLabCodeMap(file As %String = "/irisdev/app/data/labcodemap.csv") As %Status
{
    set csvPath = $zstrip(file, "<>W")
    if (csvPath = "") {
        set csvPath = "/irisdev/app/data/labcodemap.csv"
    }
    if '##class(%File).Exists(csvPath) {
        if (csvPath = "/irisdev/app/data/labcodemap.csv") && ##class(%File).Exists("/home/irisowner/dev/data/labcodemap.csv") {
            set csvPath = "/home/irisowner/dev/data/labcodemap.csv"
        }
    }
    if '##class(%File).Exists(csvPath) {
        write "LABCODEMAP_WARNING=File not found: ", csvPath, "; skipping seed load", !
        quit $$$OK
    }

    set stream = ##class(%Stream.FileCharacter).%New()
    set sc = stream.LinkToFile(csvPath)
    if $$$ISERR(sc) {
        write "LABCODEMAP_WARNING=Unable to read file: ", csvPath, !
        quit $$$OK
    }

    set tableName = "IOA.LabCodeMap"
    // Idempotent reload: CSV is the single source of truth; agent patches applied via IOA.Lookup.Apply are reset too.
    kill ^Ens.LookupTable(tableName)
    set count = 0
    while 'stream.AtEnd {
        set line = $zstrip(stream.ReadLine(), "<>W")
        if (line = "") || ($extract(line, 1) = "#") {
            continue
        }
        set key = $zstrip($piece(line, ",", 1), "<>W")
        set val = $zstrip($piece(line, ",", 2), "<>W")
        if ($zconvert(key, "L") = "local_code") || (($zconvert(key, "L") = "local_code") && ($zconvert(val, "L") = "loinc")) || (($zconvert(key, "L") = "key") && ($zconvert(val, "L") = "value")) {
            continue
        }
        if (key = "") || (val = "") {
            continue
        }
        try {
            do ##class(Ens.Util.LookupTable).%SetValue(tableName, key, val)
        } catch ex {
            try {
                do ##class(Ens.Util.LookupTable).%UpdateValue(tableName, key, val)
            } catch ex2 {
            }
        }
        set ^Ens.LookupTable(tableName, key) = val
        set count = count + 1
    }
    write "LABCODEMAP_LOADED=", count, !
    quit $$$OK
}

/// Full demo reset, run by scripts/demo.sh before every run (demo.sh --no-reset skips it).
/// Order:
///   1. Open Workflow tasks of role IOA-Reviewers are cancelled (CancelOpenTasks) and the waiting
///      IOA.Process.Message instances are given time to finish. A cancelled task never approves, so the BPL
///      never calls IOA.Lookup.Apply for it (the BPL only applies on %Action="Approve").
///   2. InteropOps.Data.Decision rows (Purge; also removes the rows the cancelled BPLs wrote in step 1)
///   3. IOA.LabCodeMap: reloaded from data/labcodemap.csv (drops patch_mapping applied by IOA.Lookup.Apply)
///   4. ^IOA.UnitFactor: convert_unit factors written by IOA.Lookup.Apply (read by Rules.LabToCanonical)
///   5. ^IOA.Batch: raw HL7 of the last batch per case (the BPL rewrites it at ingest; Apply reprocesses from it)
///   6. live and record: seeded from env (IOA_LIVE, IOA_RECORD; process env, else .env), 0 when not set
///      (LLMConfig.SeedFlagsFromEnv). demo.sh --live / --replay then set live for the run.
///   7. ^IOA.Budget killed (LIVE/MOCK call counter and usd; Agent.Operation refuses LIVE/MOCK calls over BUDGETCALLS, so a
///      leftover count would turn a LIVE/MOCK demo into budget_cap escalations). The old count is printed.
///   8. ^IOA.Dev killed (dev overrides; a leftover mock_base_url silently makes the run MOCK, cassette_dir
///      redirects cassettes). Whether mock_base_url was set is printed before the kill.
///   9. ^IOA.Config("dataDir") / ("casesDir") killed (Util.Paths defaults apply); ^IOA.Config("autoapprove")
///      reset to its default: IOA_AUTOAPPROVE (process env, else .env), 0 when not set. demo.sh then sets
///      autoapprove for the run (default 1, --manual 0).
/// Kept on purpose: ^IOA.Cache (history statistics cache, keyed by file mtime/size), the rest of ^IOA.Config.
/// Prints RESET_* lines; messages still queued are reported, not removed.
ClassMethod ResetDemo() As %Status
{
    set nTasks = ..CancelOpenTasks("IOA-Reviewers", .nFallback, .nOpenBP)
    write "RESET_TASKS_CANCELLED=", nTasks, " RESET_TASKS_DISCARDED=", nFallback, " RESET_WAITING_BP=", nOpenBP, !
    set sc = ##class(InteropOps.Data.Decision).Purge()
    write "RESET_DECISIONS_PURGED=", $select($$$ISOK(sc):1, 1:0), !
    set sc2 = ..LoadLabCodeMap()
    set n = 0, k = ""
    for {
        set k = $order(^IOA.UnitFactor(k))
        quit:(k = "")
        set k2 = ""
        for {
            set k2 = $order(^IOA.UnitFactor(k, k2))
            quit:(k2 = "")
            set n = n + 1
        }
    }
    kill ^IOA.UnitFactor
    write "RESET_UNITFACTOR_KILLED=", n, !
    set n = 0, k = ""
    for {
        set k = $order(^IOA.Batch(k))
        quit:(k = "")
        set n = n + 1
    }
    kill ^IOA.Batch
    write "RESET_BATCH_KILLED=", n, !
    set seeded = ##class(InteropOps.Config.LLMConfig).SeedFlagsFromEnv()
    write "RESET_LIVE=", +$get(^IOA.Config("live")), " MODE=", ##class(InteropOps.Config.LLMConfig).Mode(), !
    write "RESET_RECORD=", ##class(InteropOps.Config.LLMConfig).RecordEnabled(), !
    write "RESET_FLAGS_FROM_ENV=", seeded, !
    write "RESET_DEV_MOCK=", $select($zstrip($get(^IOA.Dev("mock_base_url")), "<>W") '= "":1, 1:0), !
    kill ^IOA.Dev
    write "RESET_BUDGET_CALLS_KILLED=", +$get(^IOA.Budget("calls")), !
    kill ^IOA.Budget
    kill ^IOA.Config("dataDir"), ^IOA.Config("casesDir")
    set autoVal = $zconvert($zstrip($SYSTEM.Util.GetEnviron("IOA_AUTOAPPROVE"), "<>W"), "L")
    if (autoVal = "") {
        do ..ReadDotEnv(.envMap)
        set autoVal = $zconvert($zstrip($get(envMap("IOA_AUTOAPPROVE")), "<>W"), "L")
    }
    set ^IOA.Config("autoapprove") = $select((autoVal = "1") || (autoVal = "true") || (autoVal = "yes"):1, 1:0)
    write "RESET_AUTOAPPROVE=", ^IOA.Config("autoapprove"), " RESET_PATHS=default", !
    write "RESET_KIND=", ##class(InteropOps.Agent.ProviderFactory).Kind(), !
    set q = 0
    try {
        set rs = ##class(%ResultSet).%New("Ens.Queue:Enumerate")
        do rs.Execute()
        while rs.Next() { set q = q + rs.Get("Count") }
    } catch ex {
        set q = "?"
    }
    write "RESET_QUEUED=", q, !
    write "RESET_OPEN_TASKS=", ..CountOpenTasks("IOA-Reviewers"), !
    set rs3 = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM InteropOps_Data.Decision")
    write "RESET_DECISIONS_LEFT=", $select(rs3.%Next():rs3.%GetData(1), 1:"?"), !
    quit sc
}

/// Open (not complete) Workflow tasks of role pRole: their TaskResponse ids in pIds(id)=""
ClassMethod OpenTaskIds(pRole As %String, Output pIds) As %Integer
{
    kill pIds
    set n = 0
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM EnsLib_Workflow.TaskResponse WHERE %Status <> 'Completed'")
    while rs.%Next() {
        set t = ##class(EnsLib.Workflow.TaskResponse).%OpenId(rs.%GetData(1))
        continue:'$isobject(t)
        set st = t.%TaskStatus
        continue:st.IsComplete
        continue:(('$isobject(st.Role)) || (st.Role.Name '= pRole))
        set pIds(rs.%GetData(1)) = "", n = n + 1
    }
    quit n
}

ClassMethod CountOpenTasks(pRole As %String = "IOA-Reviewers") As %String
{
    try { set n = ..OpenTaskIds(pRole, .ids) } catch ex { set n = "?" }
    quit n
}

/// Cancel every open Workflow task of role pRole with the standard engine API.
/// EnsLib.Workflow.Engine.CompleteTask(task, "") is the cancel path of the engine (empty action):
/// %Action and %Status become the engine's "cancelled" value and the task goes back to the waiting BPL as its
/// deferred response. IOA.Process.Message applies only when %Action = "Approve", so nothing is applied.
/// If the deferred response cannot be delivered (the BPL is gone), EnsLib.Workflow.Engine.%CancelRequest marks
/// the task discarded and complete (pFallback counts those). Then waits up to pWaitSec for the BPL instances
/// that were waiting on the tasks; pOpenBP = how many are still not completed.
ClassMethod CancelOpenTasks(pRole As %String = "IOA-Reviewers", Output pFallback As %Integer, Output pOpenBP As %Integer, pWaitSec As %Integer = 15) As %Integer
{
    set (n, pFallback, pOpenBP) = 0
    try {
        do ..OpenTaskIds(pRole, .ids)
    } catch ex {
        write "RESET_TASKS_ERROR=", ex.DisplayString(), !
        quit
    }
    set id = ""
    for {
        set id = $order(ids(id))
        quit:(id = "")
        set t = ##class(EnsLib.Workflow.TaskResponse).%OpenId(id)
        continue:'$isobject(t)
        set tok = t.%TaskStatus.ResponseToken
        set hdr = $select(tok '= "":##class(Ens.MessageHeader).%OpenId($piece(tok, "|", 1)), 1:"")
        if $isobject(hdr) && (hdr.BusinessProcessId '= "") set bps(hdr.BusinessProcessId) = ""
        set sc = ##class(EnsLib.Workflow.Engine).CompleteTask(t, "")
        if $$$ISERR(sc) {
            set t = ##class(EnsLib.Workflow.TaskResponse).%OpenId(id)
            set sc = $select($isobject(t) && $isobject(t.%TaskStatus.Request):##class(EnsLib.Workflow.Engine).%CancelRequest(t.%TaskStatus.Request), 1:$$$ERROR($$$GeneralError, "no request"))
            if $$$ISOK(sc) set pFallback = pFallback + 1
        }
        if $$$ISOK(sc) set n = n + 1
        if $$$ISERR(sc) write "RESET_TASK_CANCEL_ERROR=", id, " ", $system.Status.GetErrorText(sc), !
    }
    // give the BPLs time to take the cancelled response and finish (they write a final row, purged next)
    set deadline = $zhorolog + pWaitSec
    for {
        set pOpenBP = 0, bp = ""
        for {
            set bp = $order(bps(bp))
            quit:(bp = "")
            set o = ##class(Ens.BusinessProcess).%OpenId(bp)
            if $isobject(o) && 'o.%IsCompleted set pOpenBP = pOpenBP + 1
        }
        quit:((pOpenBP = 0) || ($zhorolog > deadline))
        hang 0.5
    }
    quit n
}

/// Import+compile src (recursive, flags "ck"), sync environment to ^IOA.Config,
/// load IOA.LabCodeMap lookup table, verify DeepSeeEnabled on /csp/irisapp,
/// ensure IOA-Reviewers role and reviewer user, ensure Interoperability and AutoStart
/// for InteropOps.Production, start production if not running, and print status lines
/// for active profile (openai/openrouter) without exposing secret keys.
ClassMethod InitAndStartProduction(pSrcDir As %String = "/irisdev/app/src") As %Status
{
    do ..EnsureInterop("IRISAPP")

    if '##class(%File).DirectoryExists(pSrcDir) {
        if ##class(%File).DirectoryExists("/home/irisowner/dev/src") {
            set pSrcDir = "/home/irisowner/dev/src"
        }
    }

    set sc = $SYSTEM.OBJ.ImportDir(pSrcDir, "*.cls", "ck", .errors, 1)
    if $$$ISERR(sc) || ($order(errors("")) '= "") {
        do $SYSTEM.Status.DisplayError(sc)
        write "PRODUCTION_STATUS=IMPORT_ERROR", !
        quit sc
    }

    do ..SyncEnvToGlobal()
    write "FLAGS_FROM_ENV=", ##class(InteropOps.Config.LLMConfig).SeedFlagsFromEnv(), !
    do ..LoadLabCodeMap()
    do ..MaybeInstallDailyReset()
    // KB fixture for the agent evidence "similar past incidents" (local vectors, no paid call)
    if ##class(InteropOps.KB.Store).Count() = 0 write "KB_LOAD=", $SYSTEM.Status.GetErrorText(##class(InteropOps.KB.Store).Load(, .kbN)), " rows ", +$get(kbN), !

    set casesInDir = ##class(InteropOps.Config.LLMConfig).CasesIn()
    if (casesInDir '= "") && ('##class(%File).DirectoryExists(casesInDir)) {
        do ##class(%File).CreateDirectoryChain(casesInDir)
    }
    set replayDir = ##class(InteropOps.Config.LLMConfig).ReplayDir()
    if (replayDir '= "") && ('##class(%File).DirectoryExists(replayDir)) {
        do ##class(%File).CreateDirectoryChain(replayDir)
    }

    set deepSeeEnabled = ..EnsureDeepSee("/csp/irisapp")
    do ..EnsureReviewer()
    do ..EnsureDemoWebApp("IRISAPP")

    set prodName = "InteropOps.Production"
    do ##class(Ens.Director).SetAutoStart(prodName)

    set sc = ##class(Ens.Director).GetProductionStatus(.curProd, .curState)
    // IPM runs the Activate phase inside a transaction: its retained locks (^Ens.Runtime) block the
    // production jobs, so start in a separate process that gets the lock after IPM commits.
    if ($tlevel > 0) && (curState '= 1) {
        job ##class(InteropOps.Setup).StartInBackground(prodName)
        write "PRODUCTION_STATUS=STARTING (background job, $TLEVEL=", $tlevel, ")", !
        quit $$$OK
    }
    if (curState '= 1) || (curProd '= prodName) {
        if (curState = 4) {
            do ##class(Ens.Director).RecoverProduction()
        } elseif (curState = 1) || (curState = 3) {
            do ##class(Ens.Director).StopProduction(10, 1)
        }
        set sc = ##class(Ens.Director).StartProduction(prodName)
        if $$$ISERR(sc) {
            do $SYSTEM.Status.DisplayError(sc)
            write "PRODUCTION_STATUS=START_ERROR", !
            quit sc
        }
    }
    do ##class(Ens.Director).SetAutoStart(prodName)

    do ##class(Ens.Director).GetProductionStatus(.curProd, .curState)
    set prodStatus = $select((curState=1)&&(curProd=prodName):"RUNNING", 1:"STOPPED")

    do ##class(InteropOps.Config.LLMConfig).Resolve(.llmCfg)

    write "PRODUCTION_STATUS=", prodStatus, !
    write "DEEPSEE_ENABLED=", deepSeeEnabled, !
    write "LLM_PROFILE=", $get(llmCfg("profile")), !
    write "LLM_MODEL=", $get(llmCfg("model")), !
    write "LLM_MODE=", $get(llmCfg("mode")), !

    if (prodStatus '= "RUNNING") || (deepSeeEnabled '= 1) {
        quit $$$ERROR($$$GeneralError, "Production or DeepSee verification failed")
    }
    quit $$$OK
}

/// Job body for an IPM install: start the production; without a .NET runtime (an instance not built from
/// this Dockerfile) disable PexHl7Check, so the evidence step soft-fails at once instead of a 30 s timeout per batch.
ClassMethod StartInBackground(pProd As %String)
{
    set sc = ##class(Ens.Director).StartProduction(pProd)
    // ponytail: checks the two paths this Dockerfile and the dotnet images use, not the whole PATH
    if $$$ISOK(sc) && '##class(%File).Exists("/usr/bin/dotnet") && '##class(%File).Exists($system.Util.GetEnviron("DOTNET_ROOT")_"/dotnet") {
        set sc = ##class(Ens.Director).EnableConfigItem("PexHl7Check", 0, 1)
        do ##class(Ens.Util.Log).LogWarning($classname(), "StartInBackground", "no .NET runtime found: PexHl7Check disabled, HL7 evidence is IRIS-only")
    }
    if $$$ISERR(sc) do ##class(Ens.Util.Log).LogError($classname(), "StartInBackground", $system.Status.GetErrorText(sc))
}

/// Import and compile src recursively with "ck", print COMPILE_ERROR lines on failure,
/// synchronize environment to ^IOA.Config, load IOA.LabCodeMap, ensure reviewer user/role,
/// restart/update InteropOps.Production, and write RELOAD_RESULT=OK|FAIL.
ClassMethod Reload(pSrcDir As %String = "/irisdev/app/src") As %Status
{
    do ..EnsureInterop("IRISAPP")

    set srcDir = $zstrip(pSrcDir, "<>W")
    if (srcDir = "") {
        set srcDir = "/irisdev/app/src"
    }
    if '##class(%File).DirectoryExists(srcDir) {
        if ##class(%File).DirectoryExists("/home/irisowner/dev/src") {
            set srcDir = "/home/irisowner/dev/src"
        }
    }

    set sc = $SYSTEM.OBJ.ImportDir(srcDir, "*.cls", "ck", .errors, 1)
    if $$$ISERR(sc) || ($order(errors("")) '= "") {
        if $$$ISERR(sc) {
            do $SYSTEM.Status.DisplayError(sc)
        }
        set k = ""
        for {
            set k = $order(errors(k))
            quit:(k = "")
            write "COMPILE_ERROR: ", $get(errors(k)), !
        }
        write "RELOAD_RESULT=FAIL", !
        quit $select($$$ISERR(sc):sc, 1:$$$ERROR($$$GeneralError, "Compile errors during Reload"))
    }

    do ..SyncEnvToGlobal()
    write "FLAGS_FROM_ENV=", ##class(InteropOps.Config.LLMConfig).SeedFlagsFromEnv(), !
    do ..LoadLabCodeMap()
    do ..MaybeInstallDailyReset()
    // KB fixture for the agent evidence "similar past incidents" (local vectors, no paid call)
    if ##class(InteropOps.KB.Store).Count() = 0 write "KB_LOAD=", $SYSTEM.Status.GetErrorText(##class(InteropOps.KB.Store).Load(, .kbN)), " rows ", +$get(kbN), !
    do ..EnsureReviewer()
    do ..EnsureDemoWebApp("IRISAPP")

    set prodName = "InteropOps.Production"
    do ##class(Ens.Director).GetProductionStatus(.curProd, .curState)
    if (curState = 4) {
        do ##class(Ens.Director).RecoverProduction()
        do ##class(Ens.Director).GetProductionStatus(.curProd, .curState)
    }
    if (curState = 1) || (curState = 3) {
        set sc = ##class(Ens.Director).StopProduction(10, 1)
        if $$$ISERR(sc) {
            do $SYSTEM.Status.DisplayError(sc)
            write "RELOAD_RESULT=FAIL", !
            quit sc
        }
    }
    set sc = ##class(Ens.Director).StartProduction(prodName)
    if $$$ISERR(sc) {
        do $SYSTEM.Status.DisplayError(sc)
        write "RELOAD_RESULT=FAIL", !
        quit sc
    }
    do ##class(Ens.Director).SetAutoStart(prodName)
    write "RELOAD_RESULT=OK", !
    quit $$$OK
}

/// Name of the Task Manager task created by InstallDailyReset (= InteropOps.Task.DailyReset TaskName).
Parameter DAILYRESETTASK = "IOA Daily Budget Reset";

/// Called by InitAndStartProduction and Reload: installs the daily ^IOA.Budget reset only when IOA_DAILY_RESET is
/// 1/true/yes (process env via $SYSTEM.Util.GetEnviron, else .env; LLMConfig.EnvFlagRaw). Otherwise does nothing
/// (an already installed task is left alone; remove it with UninstallDailyReset). Not installed by default.
ClassMethod MaybeInstallDailyReset() As %Boolean
{
    set raw = ##class(InteropOps.Config.LLMConfig).EnvFlagRaw("IOA_DAILY_RESET")
    if '##class(InteropOps.Config.LLMConfig).Truthy(raw) {
        write "DAILY_RESET=off (IOA_DAILY_RESET ", $select(raw = "": "unset", 1: "not 1"), ")", !
        quit 0
    }
    quit $$$ISOK(..InstallDailyReset())
}

/// Local server time of day (seconds after midnight) that equals pUtcSec UTC, from the current $HOROLOG vs
/// $ZTIMESTAMP difference (rounded to minutes). Task Manager schedules in local server time; the compose file
/// sets no TZ, so the container normally runs in UTC and this returns pUtcSec. A DST change on the server is not
/// followed until the task is reinstalled (run InstallDailyReset again).
ClassMethod LocalSecondsForUtc(pUtcSec As %Integer = 0) As %Integer
{
    set loc = $horolog, utc = $ztimestamp
    set offset = (($piece(loc, ",", 1) - $piece(utc, ",", 1)) * 86400) + ($piece(loc, ",", 2) - $piece($piece(utc, ",", 2), ".", 1))
    set offset = $normalize(offset / 60, 0) * 60
    quit (pUtcSec + offset) # 86400
}

/// ID of the Task Manager task named DAILYRESETTASK, "" if none. Looks it up in %SYS by name.
ClassMethod DailyResetTaskId() As %String
{
    set name = ..#DAILYRESETTASK, id = ""
    new $namespace
    set $namespace = "%SYS"
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM %SYS.Task WHERE Name = ?", name)
    if (rs.%SQLCODE = 0) && rs.%Next() { set id = rs.ID }
    quit id
}

/// Create or update (idempotent, by name) a Task Manager task that runs InteropOps.Task.DailyReset once a day at
/// 00:00 UTC (converted to local server time, see LocalSecondsForUtc) in namespace IRISAPP.
/// Writes DAILY_RESET_INSTALLED=1|0 and the local start time.
ClassMethod InstallDailyReset() As %Status
{
    set sc = $$$OK, name = ..#DAILYRESETTASK, id = ..DailyResetTaskId(), startSec = ..LocalSecondsForUtc(0)
    try {
        new $namespace
        set $namespace = "%SYS"
        set task = $select(id '= "": ##class(%SYS.Task).%OpenId(id), 1: ##class(%SYS.Task).%New())
        if '$isobject(task) {
            set sc = $$$ERROR($$$GeneralError, "cannot open task " _ id)
        } else {
            set task.Name = name
            set task.Description = "Interop Ops Agent: daily reset of the LIVE/MOCK call counter ^IOA.Budget at 00:00 UTC"
            set task.NameSpace = "IRISAPP"
            set task.TaskClass = "InteropOps.Task.DailyReset"
            set task.TimePeriod = 0
            set task.TimePeriodEvery = 1
            set task.DailyFrequency = 0
            set task.DailyStartTime = startSec
            set sc = task.%Save()
        }
    } catch ex {
        set sc = ex.AsStatus()
    }
    write "DAILY_RESET_INSTALLED=", $select($$$ISOK(sc): 1, 1: 0), " TASK=", $select(id '= "": "updated " _ id, 1: "new"), " LOCAL_START=", $ztime(startSec, 2), " (00:00 UTC)", !
    if $$$ISERR(sc) { write "DAILY_RESET_ERROR=", $system.Status.GetErrorText(sc), ! }
    quit sc
}

/// Remove only the Task Manager task named DAILYRESETTASK (an IRIS task object; no files). Writes DAILY_RESET_REMOVED=1|0.
ClassMethod UninstallDailyReset() As %Status
{
    set sc = $$$OK, id = ..DailyResetTaskId()
    if id '= "" {
        try {
            new $namespace
            set $namespace = "%SYS"
            set sc = ##class(%SYS.Task).%DeleteId(id)
        } catch ex {
            set sc = ex.AsStatus()
        }
    }
    write "DAILY_RESET_REMOVED=", $select((id '= "") && $$$ISOK(sc): 1, 1: 0), $select(id = "": " (not installed)", 1: ""), !
    quit sc
}

}
