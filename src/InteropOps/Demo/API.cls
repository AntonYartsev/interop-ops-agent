/// Judge demo page backend, read-only part (runs with role IOA-DemoWeb: data database READ). Used by
/// InteropOps.Demo.REST; every method returns a %DynamicObject and sets pCode (HTTP status). No arbitrary SQL or
/// code: fixed queries with validated parameters. Secrets are never returned: the API key is "set" / "unset" only.
/// The two write actions (run a case, approve/reject its review task) are in InteropOps.Demo.Write.
/// Limits (shared by both): 1 run and 1 decision per RUNEVERYSEC seconds globally (Lock ^IOA.Demo("run")) and
/// RUNSPERIPHOUR actions per client IP per hour. A run copies cases/Cnn-*.hl7 into LLMConfig.CasesIn() (the same
/// path as scripts/demo.sh) without a reset, so the production runs it in the current mode and the core applies
/// ^IOA.Budget itself.
Class InteropOps.Demo.API
{

Parameter RUNEVERYSEC = 30;

Parameter RUNSPERIPHOUR = 20;

Parameter MAXKBQUERY = 200;

/// Case id whitelist: Cnn, and a file cases/Cnn-*.hl7 must exist
ClassMethod CaseFile(pId As %String) As %String
{
    Quit:('$MATCH(pId, "C[0-9]{2}")) ""
    Set tDir = ##class(InteropOps.Util.Paths).CasesDir(), tF = $ZSEARCH(tDir_pId_"-*.hl7"), tOut = ""
    While tF '= "" {
        Set tB = ##class(%File).GetFilename(tF)
        If $MATCH(tB, pId_"-[A-Za-z0-9_-]+\.hl7") Set tOut = tF
        Set tF = $ZSEARCH("")
    }
    Quit tOut
}

/// Seconds since 1840-12-31 UTC
ClassMethod Now() As %Integer
{
    Set z = $ZTIMESTAMP
    Quit ($PIECE(z, ",") * 86400) + $PIECE($PIECE(z, ",", 2), ".")
}

ClassMethod UTC(pSec As %Integer) As %String
{
    Quit:(pSec = "") ""
    Quit $ZDATETIME((pSec \ 86400)_","_(pSec # 86400), 3, 1)_"Z"
}

/// GET /api/status
ClassMethod Status(Output pCode As %Integer) As %DynamicObject
{
    Set pCode = 200, C = "InteropOps.Config.LLMConfig", O = "InteropOps.Agent.Operation"
    Set tOut = {}
    Set tOut.mode = $CLASSMETHOD(C, "Mode"), tOut.kind = ##class(InteropOps.Agent.ProviderFactory).Kind()
    Set tOut.profile = $CLASSMETHOD(C, "Profile"), tOut.model = $CLASSMETHOD(C, "Model")
    Set tOut.key = $SELECT($CLASSMETHOD(C, "KeyPresent"): "set", 1: "unset")
    Set tOut.autoapprove = +$GET(^IOA.Config("autoapprove"))
    Set tOver = $CLASSMETHOD(O, "OverUSD", .tSpent, .tCap), tCalls = +$GET(^IOA.Budget("calls")), tMax = $PARAMETER(O, "BUDGETCALLS")
    Set tOut.budget = {"calls": (tCalls), "callsCap": (tMax), "callsLeft": ($SELECT(tMax > tCalls: tMax - tCalls, 1: 0)),
        "usd": (+tSpent), "usdCap": (+tCap), "usdLeft": ($SELECT(tCap > tSpent: +$FNUMBER(tCap - tSpent, "", 4), 1: 0)), "overUsd": (''tOver),
        "appliesTo": "LIVE and MOCK agent calls (REPLAY is free)"}
    Do ##class(Ens.Director).GetProductionStatus(.tProd, .tState)
    Set tOut.production = {"name": (tProd), "state": ($CASE(tState, 1: "running", 2: "stopped", 3: "suspended", 4: "troubled", : "unknown"))}
    Set tLast = +$GET(^IOA.Demo("lastRun")), tWait = 0
    Set:(tLast > 0) tWait = ..#RUNEVERYSEC - (..Now() - tLast)
    Set:(tWait < 0) tWait = 0
    Set tLastD = +$GET(^IOA.Demo("lastDecide")), tWaitD = 0
    Set:(tLastD > 0) tWaitD = ..#RUNEVERYSEC - (..Now() - tLastD)
    Set:(tWaitD < 0) tWaitD = 0
    Set tOut.runLimit = {"everySec": (..#RUNEVERYSEC), "perIpPerHour": (..#RUNSPERIPHOUR), "nextRunInSec": (tWait), "nextDecisionInSec": (tWaitD)}
    // rights of this request: the data database permission is READ for the page role (writes only in InteropOps.Demo.Write)
    Set tRes = $GET(^IOA.Demo("cfg", "dataResource"))
    Set tOut.rights = {"roles": ($ROLES), "dataResource": (tRes), "dataPermission": ($SELECT(tRes = "": "", 1: $SYSTEM.Security.Check(tRes)))}
    Set tOut.casesInPending = ..PendingFiles("")
    Set tOut.serverTimeUtc = ..UTC(..Now())
    Quit tOut
}

/// Files waiting in the input directory (pPrefix = "" all .hl7, else Cnn-)
ClassMethod PendingFiles(pPrefix As %String) As %Integer
{
    Set n = 0, tF = $ZSEARCH(##class(InteropOps.Config.LLMConfig).CasesIn()_pPrefix_"*.hl7")
    While tF '= "" { Set n = n + 1, tF = $ZSEARCH("") }
    Quit n
}

/// GET /api/cases: the case files with the expected result (cases/expected.json) and the latest Decision row
ClassMethod Cases(Output pCode As %Integer) As %DynamicObject
{
    Set pCode = 200, tDir = ##class(InteropOps.Util.Paths).CasesDir(), tExp = ""
    Try {
        Set tS = ##class(%Stream.FileCharacter).%New(), tS.TranslateTable = "UTF8"
        If $$$ISOK(tS.LinkToFile(tDir_"expected.json")) Set tExp = ##class(%DynamicObject).%FromJSON(tS).cases
    } Catch { Set tExp = "" }
    Set tList = [], tF = $ZSEARCH(tDir_"C*.hl7")
    While tF '= "" {
        Set tB = ##class(%File).GetFilename(tF)
        Set:$MATCH(tB, "C[0-9]{2}-[A-Za-z0-9_-]+\.hl7") tSort(tB) = ""
        Set tF = $ZSEARCH("")
    }
    Set tB = ""
    For {
        Set tB = $ORDER(tSort(tB))
        Quit:(tB = "")
        Set tId = $PIECE(tB, "-")
        If 1 {
            Set tC = {"id": (tId), "file": (tB), "title": ($TRANSLATE($PIECE($PIECE(tB, ".hl7"), "-", 2, 99), "-", " "))}
            If $ISOBJECT(tExp) && $ISOBJECT(tExp.%Get(tId)) Set e = tExp.%Get(tId), tC.expected = {"action": (e.action), "target": (e.target)}
            Set tLast = ..DecisionRows("WHERE CaseId = ?", tId, 1, 0)
            Set tC.latest = $SELECT(tLast.%Size(): tLast.%Get(0), 1: "")
            Do tList.%Push(tC)
        }
    }
    Quit {"cases": (tList)}
}

/// GET /api/decisions?limit=n (1..50, default 20): latest Decision rows, newest first, with evidence
ClassMethod Decisions(pLimit As %String, Output pCode As %Integer) As %DynamicObject
{
    Set pCode = 200, tN = $SELECT(pLimit = "": 20, $MATCH(pLimit, "[0-9]{1,3}"): +pLimit, 1: -1)
    If (tN < 1) || (tN > 50) Set pCode = 400 Quit {"error": "limit must be an integer 1..50"}
    Quit {"decisions": (..DecisionRows("", "", tN, 0))}
}

/// GET /api/decisions/:id: one Decision row incl. gate detail
ClassMethod Decision(pId As %String, Output pCode As %Integer) As %DynamicObject
{
    Set pCode = 200
    If '$MATCH(pId, "[1-9][0-9]{0,17}") Set pCode = 400 Quit {"error": "id must be a positive integer"}
    Set tR = ..DecisionRows("WHERE ID = ?", pId, 1, 1)
    If tR.%Size() = 0 Set pCode = 404 Quit {"error": "decision not found"}
    Quit tR.%Get(0)
}

/// Decision rows as dynamic objects (fixed column list; pWhere is one of the literal clauses above)
ClassMethod DecisionRows(pWhere As %String, pArg As %String, pTop As %Integer, pFull As %Boolean = 0) As %DynamicArray [ Private ]
{
    Set tSql = "SELECT TOP "_(+pTop)_" ID, CaseId, MSH10, SessionId, Mode, Source, Action, Target, Factor, Reason, GateResult, FinalStatus,"
        _" LLMCalls, EvidenceJSON, GateDetail, TaskId, TokensIn, TokensOut, CreatedAt FROM InteropOps_Data.Decision "_pWhere_" ORDER BY ID DESC"
    Set tR = $SELECT(pWhere = "": ##class(%SQL.Statement).%ExecDirect(, tSql), 1: ##class(%SQL.Statement).%ExecDirect(, tSql, pArg))
    Set tA = []
    If tR.%SQLCODE < 0 Quit tA
    While tR.%Next() {
        Set o = {"id": (+tR.ID), "caseId": (tR.CaseId), "msh10": (tR.MSH10), "sessionId": ($SELECT(tR.SessionId = "": "", 1: +tR.SessionId)),
            "mode": (tR.Mode), "source": (tR.Source), "action": (tR.Action), "target": (tR.Target), "factor": (tR.Factor),
            "reason": (tR.Reason), "gateResult": (tR.GateResult), "finalStatus": (tR.FinalStatus), "llmCalls": (+tR.LLMCalls),
            "taskId": (tR.TaskId), "tokensIn": (+tR.TokensIn), "tokensOut": (+tR.TokensOut), "createdAtUtc": (tR.CreatedAt)}
        Set o.evidence = ..ParseJSON(tR.EvidenceJSON)
        Set:pFull o.gateDetail = ..ParseJSON(tR.GateDetail)
        Do tA.%Push(o)
    }
    Quit tA
}

ClassMethod ParseJSON(pText As %String) [ Private ]
{
    Quit:(pText = "") ""
    Try { Set v = ##class(%DynamicAbstractObject).%FromJSON(pText) } Catch { Set v = pText }
    Quit v
}

/// GET /api/trace/:session: Ens.MessageHeader rows of one session (max 500), the host steps and the Decision row
ClassMethod Trace(pSession As %String, Output pCode As %Integer) As %DynamicObject
{
    Set pCode = 200
    If '$MATCH(pSession, "[1-9][0-9]{0,17}") Set pCode = 400 Quit {"error": "session must be a positive integer"}
    Set tR = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 500 ID, TimeCreated, SourceConfigName, TargetConfigName, MessageBodyClassName, Type, Status, IsError FROM Ens.MessageHeader WHERE SessionId = ? ORDER BY ID", pSession)
    Set tM = [], tHosts = [], tSeen = ""
    While tR.%Next() {
        Do tM.%Push({"id": (+tR.ID), "timeUtc": (tR.TimeCreated), "from": (tR.SourceConfigName), "to": (tR.TargetConfigName),
            "body": (tR.MessageBodyClassName), "type": ($CASE(tR.Type, 1: "request", 2: "response", : tR.Type)),
            "status": ($CASE(tR.Status, 1: "created", 2: "queued", 3: "delivered", 4: "discarded", 5: "suspended", 6: "deferred", 7: "aborted", 8: "error", 9: "completed", : tR.Status)),
            "isError": (''tR.IsError)})
        For h = tR.SourceConfigName, tR.TargetConfigName {
            If (h '= "") && '$LISTFIND(tSeen, h) Set tSeen = tSeen_$LISTBUILD(h) Do tHosts.%Push(h)
        }
    }
    If tM.%Size() = 0 Set pCode = 404 Quit {"error": "no messages for this session", "sessionId": (+pSession)}
    Set tD = ..DecisionRows("WHERE SessionId = ?", pSession, 1, 0)
    Quit {"sessionId": (+pSession), "hosts": (tHosts), "messages": (tM), "decision": ($SELECT(tD.%Size(): tD.%Get(0), 1: ""))}
}

/// GET /api/tasks?limit=n (1..50, default 20): Workflow tasks (EnsLib.Workflow.TaskResponse), newest first
ClassMethod Tasks(pLimit As %String, Output pCode As %Integer) As %DynamicObject
{
    Set pCode = 200, tN = $SELECT(pLimit = "": 20, $MATCH(pLimit, "[0-9]{1,3}"): +pLimit, 1: -1)
    If (tN < 1) || (tN > 50) Set pCode = 400 Quit {"error": "limit must be an integer 1..50"}
    Set tR = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP "_tN_" ID, %Status AS St, %Subject AS Subj, %Message AS Msg, %RoleName AS RoleN, %UserName AS UserN, %Action AS Act, %Actions AS Acts, TaskStatus_IsComplete AS Done, TaskStatus_SessionId AS Sess, TaskStatus_TimeCreated AS Created, TaskStatus_TimeCompleted AS Completed FROM EnsLib_Workflow.TaskResponse ORDER BY ID DESC")
    Set tA = [], tOpen = 0
    While tR.%Next() {
        Set:('tR.Done) tOpen = tOpen + 1
        Do tA.%Push({"id": (+tR.ID), "status": (tR.St), "subject": (tR.Subj), "message": ($EXTRACT(tR.Msg, 1, 2000)), "role": (tR.RoleN),
            "user": (tR.UserN), "action": (tR.Act), "actions": (tR.Acts), "isComplete": (''tR.Done), "sessionId": ($SELECT(tR.Sess = "": "", 1: +tR.Sess)),
            "createdUtc": (tR.Created), "completedUtc": (tR.Completed)})
        Do tA.%Get(tA.%Size() - 1).%Set("canDecide", ('tR.Done && (..OwnTask(tR.ID, .tI) = 200)), "boolean")
    }
    Quit {"openInPage": (tOpen), "openTotal": (+##class(InteropOps.Setup).CountOpenTasks("IOA-Reviewers")), "tasks": (tA)}
}

/// GET /api/kb?q=text&k=n: InteropOps.KB.Store.Search with the local embedder only (never a paid call)
ClassMethod KB(pQ As %String, pK As %String, Output pCode As %Integer) As %DynamicObject
{
    Set pCode = 200, tQ = $ZSTRIP(pQ, "<>WC"), tK = $SELECT(pK = "": 3, $MATCH(pK, "[0-9]{1,2}"): +pK, 1: -1)
    If tQ = "" Set pCode = 400 Quit {"error": "q is required"}
    If $LENGTH(tQ) > ..#MAXKBQUERY Set pCode = 400 Quit {"error": ("q longer than "_..#MAXKBQUERY_" characters")}
    If (tK < 1) || (tK > 10) Set pCode = 400 Quit {"error": "k must be an integer 1..10"}
    If ##class(InteropOps.KB.Store).Count() = 0 Set pCode = 503 Quit {"error": "knowledge base not loaded (scripts/reload.sh loads it)"}
    Set r = ##class(%DynamicObject).%FromJSON(##class(InteropOps.KB.Store).Search(tQ, tK, "local"))
    If r.error '= "" Set pCode = 500 Quit {"error": "kb search failed"}
    Quit r
}

/// GET /api/run: the last page run and the newest Decision row of that case written after it (done = final status)
ClassMethod LastRun(Output pCode As %Integer) As %DynamicObject
{
    Set pCode = 200, tLast = +$GET(^IOA.Demo("lastRun"))
    If tLast = 0 Quit {"run": "", "decision": "", "done": false}
    Set tCase = $GET(^IOA.Demo("lastRun", "case")), tAfter = +$GET(^IOA.Demo("lastRun", "afterId"))
    Set tR = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM InteropOps_Data.Decision WHERE CaseId = ? AND ID > ? ORDER BY ID DESC", tCase, tAfter)
    Set tD = ""
    If tR.%Next() Set tA = ..DecisionRows("WHERE ID = ?", tR.ID, 1, 0), tD = tA.%Get(0)
    Set tDone = $ISOBJECT(tD) && (tD.finalStatus '= "pending_review")
    If $ISOBJECT(tD) && (tD.taskId '= "") Do tD.%Set("canDecide", (..OwnTask(tD.taskId, .tI) = 200), "boolean")
    Set tOut = {"run": {"case": (tCase), "startedUtc": (..UTC(tLast)), "agoSec": (..Now() - tLast), "afterDecisionId": (tAfter), "pendingInInput": (..PendingFiles(tCase_"-"))},
        "decision": (tD)}
    Do tOut.%Set("done", tDone, "boolean")
    Quit tOut
}

/// Is pTask an open review task of a case run from this page? Returns the HTTP code (200 = yes) and pInfo
/// (the error, or caseId / sessionId / decisionId). Link: ^IOA.Demo("runs", case, afterDecisionId) = run time
/// (written by InteropOps.Demo.Write.Run) -> the pending_review Decision row of that case with ID > afterDecisionId,
/// written within 15 minutes after the run -> its TaskId (set by InteropOps.Workflow.Operation.SetDecisionTask).
ClassMethod OwnTask(pTask As %String, Output pInfo As %DynamicObject) As %Integer
{
    Set pInfo = ""
    If '$MATCH(pTask, "[1-9][0-9]{0,17}") Set pInfo = {"error": "task id must be a positive integer"} Quit 400
    Set tR = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, TaskStatus_IsComplete AS Done, %Status AS St, %RoleName AS RoleN FROM EnsLib_Workflow.TaskResponse WHERE ID = ?", pTask)
    If 'tR.%Next() Set pInfo = {"error": "task not found"} Quit 404
    Set tDone = tR.Done, tSt = tR.St, tRole = tR.RoleN
    Set tR = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID, CaseId, SessionId, CreatedAt FROM InteropOps_Data.Decision WHERE TaskId = ? AND FinalStatus = 'pending_review' ORDER BY ID DESC", pTask)
    If 'tR.%Next() Set pInfo = {"error": "not a review task of a demo case"} Quit 403
    Set tDec = +tR.ID, tCase = tR.CaseId, tSess = tR.SessionId, tAt = tR.CreatedAt
    If tRole '= "IOA-Reviewers" Set pInfo = {"error": "not a review task of a demo case"} Quit 403
    Set tAtSec = "", tH = $ZDATETIMEH(tAt, 3, , , , , , , , "")
    Set:(tH '= "") tAtSec = ($PIECE(tH, ",") * 86400) + $PIECE(tH, ",", 2)
    Set tOwn = 0, k = ""
    For {
        Set k = $ORDER(^IOA.Demo("runs", tCase, k), 1, t)
        Quit:(k = "")
        If (k < tDec) && (tAtSec '= "") && (tAtSec >= (t - 5)) && ((tAtSec - t) <= 900) Set tOwn = 1 Quit
    }
    If 'tOwn Set pInfo = {"error": "this task was not started from the demo page"} Quit 403
    If tDone || (tSt = "Completed") || $DATA(^IOA.Demo("decided", +pTask)) Set pInfo = {"error": "task already closed", "taskId": (+pTask)} Quit 409
    Set tR = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 FinalStatus AS F FROM InteropOps_Data.Decision WHERE CaseId = ? AND SessionId = ? ORDER BY ID DESC", tCase, tSess)
    If tR.%Next() && (tR.F '= "pending_review") Set pInfo = {"error": "the case already has a final decision", "finalStatus": (tR.F)} Quit 409
    Set pInfo = {"taskId": (+pTask), "caseId": (tCase), "sessionId": ($SELECT(tSess = "": "", 1: +tSess)), "decisionId": (tDec)}
    Quit 200
}

}
