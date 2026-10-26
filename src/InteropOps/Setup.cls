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

    do ##class(InteropOps.Config.LLMConfig).SetLive(0)
    do ..SyncEnvToGlobal()
    do ..LoadLabCodeMap()

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

    set prodName = "InteropOps.Production"
    do ##class(Ens.Director).SetAutoStart(prodName)

    set sc = ##class(Ens.Director).GetProductionStatus(.curProd, .curState)
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
    do ..LoadLabCodeMap()
    do ..EnsureReviewer()

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

}
