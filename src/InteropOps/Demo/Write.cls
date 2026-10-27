/// Write path of the judge demo page: the only code that writes for an anonymous /demo visitor.
/// The web application role IOA-DemoWeb has the namespace data database READ only. Each entry point below raises
/// $ROLES with the privileged routine application IOA.DemoWrite (Security.Applications type 4: only routines of this
/// class may call AddRoles for it, and the caller must hold resource IOA_DemoWrite:U, which only IOA-DemoWeb has).
/// That adds role IOA-DemoWrite (data database READ/WRITE, nothing else) for the critical section and drops it
/// again in every outcome: after the Try/Catch Set $ROLES = "" removes every added role (a process may always lower
/// its roles, it may not set them back), and New $ROLES puts back the page role IOA-DemoWeb only when the method quits.
/// Writes done while raised: ^IOA.Demo (limits, run and decision log), the case file copy into LLMConfig.CasesIn(),
/// and the standard Workflow completion (InteropOps.Workflow.Operation.Complete: AssignTask + CompleteTask).
Class InteropOps.Demo.Write
{

Parameter APP = "IOA.DemoWrite";

Parameter ROLE = "IOA-DemoWrite";

/// POST /api/run/:case: drop cases/Cnn-*.hl7 into the input directory (no reset), rate-limited
ClassMethod Run(pCase As %String, pClient As %String, Output pCode As %Integer) As %DynamicObject
{
    New $ROLES
    Set pCode = 200, tCase = $ZCONVERT(pCase, "U"), A = "InteropOps.Demo.API"
    If '$MATCH(tCase, "C[0-9]{2}") Set pCode = 400 Quit {"error": "case must look like C01"}
    Set tSrc = $CLASSMETHOD(A, "CaseFile", tCase)
    If tSrc = "" Set pCode = 404 Quit {"error": "unknown case", "case": (tCase)}
    Lock +^IOA.Demo("run"):3
    If '$TEST Set pCode = 503 Quit {"error": "busy, try again"}
    Try {
        Set tNow = $CLASSMETHOD(A, "Now"), tIp = ..IpHash(pClient)
        Set tOut = ..Limited("lastRun", tIp, tNow, .pCode)
        If $ISOBJECT(tOut) {
        } ElseIf $CLASSMETHOD(A, "PendingFiles", tCase_"-") > 0 {
            Set pCode = 409, tOut = {"error": "this case is still waiting in the input directory", "case": (tCase)}
        } ElseIf '..Raise(.tPerm) {
            Set pCode = 500, tOut = {"error": "write role not available"}
        } Else {
            Set tB = ##class(%File).GetFilename(tSrc), tDst = ##class(InteropOps.Config.LLMConfig).CasesIn()_tB
            Set tMaxId = 0, tR = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) AS M FROM InteropOps_Data.Decision")
            Set:(tR.%Next()) tMaxId = +tR.M
            If '##class(%File).CopyFile(tSrc, tDst) {
                Set pCode = 500, tOut = {"error": "could not write the case file to the input directory"}
            } Else {
                Do ..Count(tIp, tNow)
                Set ^IOA.Demo("lastRun") = tNow, ^IOA.Demo("lastRun", "case") = tCase, ^IOA.Demo("lastRun", "afterId") = tMaxId
                // run log for the task check (InteropOps.Demo.API.OwnTask); entries older than a day are dropped
                Set k = ""
                For { Set k = $ORDER(^IOA.Demo("runs", tCase, k), 1, t)  Quit:(k = "")  Kill:((tNow - t) > 86400) ^IOA.Demo("runs", tCase, k) }
                Set ^IOA.Demo("runs", tCase, tMaxId) = tNow
                Set st = $CLASSMETHOD(A, "Status", .c)
                Set tOut = {"accepted": true, "case": (tCase), "file": (tB), "startedUtc": ($CLASSMETHOD(A, "UTC", tNow)), "afterDecisionId": (tMaxId),
                    "mode": (st.mode), "kind": (st.kind), "budget": (st.budget), "nextRunInSec": ($PARAMETER(A, "RUNEVERYSEC")),
                    "note": "no reset: a case whose fix was already applied may now pass; the daily reset or demo.sh restores the seed",
                    "dataPermissionRaised": (tPerm)}
            }
        }
    } Catch ex {
        Set pCode = 500, tOut = {"error": "run failed"}
    }
    Set $ROLES = ""
    Lock -^IOA.Demo("run")
    Do tOut.%Set("writeRoleDropped", ..Dropped(), "boolean")
    Quit tOut
}

/// POST /api/tasks/:id/approve|reject: complete an open Workflow task of a case run from this page, as the reviewer
/// does in the Inbox (InteropOps.Workflow.Operation.Complete = EnsLib.Workflow.Engine AssignTask + CompleteTask with
/// %Action Approve or Reject; IOA.Process.Message then writes the final row: applied or rejected). Same limits as a run.
ClassMethod Decide(pTask As %String, pAction As %String, pClient As %String, Output pCode As %Integer) As %DynamicObject
{
    New $ROLES
    Set pCode = 200, A = "InteropOps.Demo.API"
    Set tAct = $CASE($ZCONVERT(pAction, "L"), "approve": "Approve", "reject": "Reject", : "")
    If tAct = "" Set pCode = 400 Quit {"error": "action must be approve or reject"}
    Set pCode = $CLASSMETHOD(A, "OwnTask", pTask, .tInfo)
    If pCode '= 200 Quit tInfo
    Lock +^IOA.Demo("run"):3
    If '$TEST Set pCode = 503 Quit {"error": "busy, try again"}
    Try {
        Set tNow = $CLASSMETHOD(A, "Now"), tIp = ..IpHash(pClient)
        Set tOut = ..Limited("lastDecide", tIp, tNow, .pCode)
        If $ISOBJECT(tOut) {
        } Else {
            // checked again under the lock: a parallel request may have closed it
            Set pCode = $CLASSMETHOD(A, "OwnTask", pTask, .tInfo)
            If pCode '= 200 {
                Set tOut = tInfo
            } ElseIf '..Raise(.tPerm) {
                Set pCode = 500, tOut = {"error": "write role not available"}
            } Else {
                Set tUser = $ZSTRIP($GET(^IOA.Config("IOA_REVIEWER_USER")), "<>W")
                Set:(tUser = "") tUser = "reviewer"
                Set tTask = ##class(EnsLib.Workflow.TaskResponse).%OpenId(+pTask)
                Do tTask.%FormValues.SetAt("demo-page", "CompletedVia")
                Set tSC = tTask.%Save()
                Set:$$$ISOK(tSC) tSC = ##class(InteropOps.Workflow.Operation).Complete(+pTask, tAct, tUser)
                If $$$ISERR(tSC) {
                    Set pCode = 500, tOut = {"error": "could not complete the task"}
                } Else {
                    Do ..Count(tIp, tNow)
                    Set ^IOA.Demo("lastDecide") = tNow, ^IOA.Demo("decided", +pTask) = $LISTBUILD(tNow, tAct, tInfo.caseId, tInfo.sessionId)
                    Set tOut = {"accepted": true, "taskId": (+pTask), "action": (tAct), "reviewer": (tUser), "caseId": (tInfo.caseId),
                        "sessionId": (tInfo.sessionId), "decisionId": (tInfo.decisionId), "completedUtc": ($CLASSMETHOD(A, "UTC", tNow)),
                        "next": "the business process writes the final Decision row (applied or rejected); poll GET /api/run or /api/trace/:session",
                        "dataPermissionRaised": (tPerm)}
                }
            }
        }
    } Catch ex {
        Set pCode = 500, tOut = {"error": "decision failed"}
    }
    Set $ROLES = ""
    Lock -^IOA.Demo("run")
    Do tOut.%Set("writeRoleDropped", ..Dropped(), "boolean")
    Quit tOut
}

/// Add IOA-DemoWrite to $ROLES (privileged routine application; works only from this class).
/// pPerm = the data database permission while raised (READ,WRITE)
ClassMethod Raise(Output pPerm As %String) As %Boolean [ Private ]
{
    Set tRes = $GET(^IOA.Demo("cfg", "dataResource"))
    Set tSC = $SYSTEM.Security.AddRoles(..#APP)
    Set pPerm = $SELECT(tRes = "": "", 1: $SYSTEM.Security.Check(tRes))
    Quit $$$ISOK(tSC) && ''$LISTFIND($LISTFROMSTRING($ROLES), ..#ROLE)
}

/// 1 if the write role is no longer in $ROLES
ClassMethod Dropped() As %Boolean [ Private ]
{
    Quit '$LISTFIND($LISTFROMSTRING($ROLES), ..#ROLE)
}

/// Shared limits (caller holds Lock ^IOA.Demo("run")): one action of kind pKind per RUNEVERYSEC for all visitors, and
/// RUNSPERIPHOUR actions (runs and decisions together) per client per hour. "" if allowed, else the 429 body.
ClassMethod Limited(pKind As %String, pIp As %String, pNow As %Integer, Output pCode As %Integer) As %DynamicObject [ Private ]
{
    Set tEvery = $PARAMETER("InteropOps.Demo.API", "RUNEVERYSEC"), tMax = $PARAMETER("InteropOps.Demo.API", "RUNSPERIPHOUR")
    Set tLast = +$GET(^IOA.Demo(pKind)), tWhat = $SELECT(pKind = "lastRun": "run", 1: "decision")
    If (tLast > 0) && ((pNow - tLast) < tEvery) {
        Set pCode = 429
        Quit {"error": ("rate limited: one "_tWhat_" per "_tEvery_" s (all visitors)"), "retryAfterSec": (tEvery - (pNow - tLast))}
    }
    If +$GET(^IOA.Demo("ip", pIp, pNow \ 3600)) >= tMax {
        Set pCode = 429
        Quit {"error": ("rate limited: "_tMax_" actions per hour per client"), "retryAfterSec": (3600 - (pNow # 3600))}
    }
    Quit ""
}

/// Count one action for the client (only the current hour bucket is kept); caller is raised
ClassMethod Count(pIp As %String, pNow As %Integer) [ Private ]
{
    Set tHour = pNow \ 3600, n = +$GET(^IOA.Demo("ip", pIp, tHour))
    Kill ^IOA.Demo("ip", pIp)
    Set ^IOA.Demo("ip", pIp, tHour) = n + 1
}

ClassMethod IpHash(pClient As %String) As %String [ Private ]
{
    Quit $EXTRACT($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHA1Hash(pClient)), 1, 12)
}

}
