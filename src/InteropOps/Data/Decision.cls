Class InteropOps.Data.Decision Extends %Persistent [ SqlTableName = Decision ]
{

Property CaseId As %String(MAXLEN = 32);

Property MSH10 As %String(MAXLEN = 64);

Property SessionId As %Integer;

/// Provider kind that made the decision: MOCK (dev mock, ^IOA.Dev("mock_base_url")), REPLAY (cassettes) or LIVE.
Property Mode As %String(VALUELIST = ",MOCK,REPLAY,LIVE");

/// human:auto = approved automatically by the demo auto-approver (IOA_AUTOAPPROVE / LLMConfig.AutoApprove()).
Property Source As %String(VALUELIST = ",rules,agent,human,human:auto");

Property Action As %String(MAXLEN = 64);

Property Target As %String(MAXLEN = 128);

Property Factor As %Numeric(SCALE = 6);

Property Reason As %String(MAXLEN = 2000);

Property GateResult As %String(MAXLEN = 2000);

Property FinalStatus As %String(VALUELIST = ",applied,passed,quarantined,escalated,pending_review,rejected");

Property LLMCalls As %Integer;

/// Evidence as JSON text (array or object). Plain-string evidence is stored as a one-element JSON array.
Property EvidenceJSON As %String(MAXLEN = 32000);

/// Gate details (JSON or text), e.g. replay counts per check.
Property GateDetail As %String(MAXLEN = 32000);

/// Workflow task id for pending_review / human decisions.
Property TaskId As %String(MAXLEN = 64);

Property TokensIn As %Integer;

Property TokensOut As %Integer;

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($HOROLOG,3)} ];

Index IdxCaseId On CaseId;

Index IdxMSH10 On MSH10;

Index IdxSessionId On SessionId;

Index IdxFinalStatus On FinalStatus;

/// Extract a property from a %DynamicObject trying primary and fallback key names.
ClassMethod GetDynVal(pObj As %DynamicObject, pKey1 As %String, pKey2 As %String = "") As %String [ Private ]
{
    if '$isobject(pObj) {
        quit ""
    }
    if (pKey1 '= "") && pObj.%IsDefined(pKey1) {
        set v = pObj.%Get(pKey1)
        if $isobject(v) {
            quit v.%ToJSON()
        }
        quit v
    }
    if (pKey2 '= "") && pObj.%IsDefined(pKey2) {
        set v = pObj.%Get(pKey2)
        if $isobject(v) {
            quit v.%ToJSON()
        }
        quit v
    }
    quit ""
}

/// 1 if this row comes from a dev-mock run: GateDetail.provider_kind="MOCK" (or agent.provider_kind),
/// else (rules rows: "none (rules)") whether ProviderFactory.Kind() is MOCK (an ignored mock URL is not MOCK).
ClassMethod IsMockRun(pGateDetail As %String = "") As %Boolean
{
    set kind = ""
    if $zstrip(pGateDetail, "<>W") '= "" {
        try {
            set gd = {}.%FromJSON(pGateDetail)
            set kind = $zconvert(gd."provider_kind", "U")
            if (kind = "") && $isobject(gd.agent) { set kind = $zconvert(gd.agent."provider_kind", "U") }
        } catch ex {
            set kind = ""
        }
    }
    if $listfind($listbuild("MOCK", "REPLAY", "LIVE"), kind) { quit (kind = "MOCK") }
    quit (##class(InteropOps.Agent.ProviderFactory).Kind() = "MOCK")
}

/// Record a decision row from a %DynamicObject and save it.
ClassMethod Record(pData As %DynamicObject, Output pId As %Integer) As %Status
{
    set pId = ""
    if '$isobject(pData) {
        if ($zstrip($get(pData), "<>W") '= "") {
            try {
                set pData = {}.%FromJSON(pData)
            } catch ex {
                set pData = ""
            }
        }
        if '$isobject(pData) {
            quit $$$ERROR($$$GeneralError, "InteropOps.Data.Decision:Record requires a %DynamicObject")
        }
    }

    set rec = ..%New()
    set rec.CaseId = $extract(..GetDynVal(pData, "CaseId", "caseId"), 1, 32)
    set rec.MSH10 = $extract(..GetDynVal(pData, "MSH10", "msh10"), 1, 64)

    set sessionVal = ..GetDynVal(pData, "SessionId", "sessionId")
    if (sessionVal '= "") {
        set rec.SessionId = +sessionVal
    }

    set modeVal = $zconvert(..GetDynVal(pData, "Mode", "mode"), "U")
    if (modeVal '= "MOCK") && (modeVal '= "REPLAY") && (modeVal '= "LIVE") {
        set modeVal = ##class(InteropOps.Config.LLMConfig).Mode()
    }
    // Record the mode the row really ran in: callers pass LLMConfig.Mode() (REPLAY|LIVE); a dev-mock run is MOCK
    // (GateDetail.provider_kind=MOCK, else ProviderFactory.Kind()=MOCK); MOCK may run with Mode() LIVE or REPLAY.
    if (modeVal '= "MOCK") && ..IsMockRun(..GetDynVal(pData, "gateDetail", "GateDetail")) {
        set modeVal = "MOCK"
    }
    set rec.Mode = modeVal

    set srcVal = $zconvert(..GetDynVal(pData, "Source", "source"), "L")
    if (srcVal = "rules") || (srcVal = "agent") || (srcVal = "human") || (srcVal = "human:auto") {
        set rec.Source = srcVal
    }

    set rec.Action = $extract(..GetDynVal(pData, "Action", "action"), 1, 64)
    set rec.Target = $extract(..GetDynVal(pData, "Target", "target"), 1, 128)

    set factorVal = ..GetDynVal(pData, "Factor", "factor")
    if (factorVal '= "") {
        set rec.Factor = +factorVal
    }

    set rec.Reason = $extract(..GetDynVal(pData, "Reason", "reason"), 1, 2000)
    set rec.GateResult = $extract(..GetDynVal(pData, "GateResult", "gateResult"), 1, 2000)

    set evVal = ..GetDynVal(pData, "evidence", "Evidence")
    if (evVal = "") {
        set evVal = ..GetDynVal(pData, "EvidenceJSON", "evidenceJSON")
    }
    if (evVal '= "") && ($extract($zstrip(evVal, "<W"), 1) '= "[") && ($extract($zstrip(evVal, "<W"), 1) '= "{") {
        set tmpArr = ##class(%Library.DynamicArray).%New()
        do tmpArr.%Push(evVal)
        set evVal = tmpArr.%ToJSON()
    }
    set rec.EvidenceJSON = $extract(evVal, 1, 32000)
    set rec.GateDetail = $extract(..GetDynVal(pData, "gateDetail", "GateDetail"), 1, 32000)
    set rec.TaskId = $extract(..GetDynVal(pData, "taskId", "TaskId"), 1, 64)

    set statusVal = $zconvert(..GetDynVal(pData, "FinalStatus", "finalStatus"), "L")
    if $listfind($listbuild("applied", "passed", "quarantined", "escalated", "pending_review", "rejected"), statusVal) {
        set rec.FinalStatus = statusVal
    }

    set llmCallsVal = ..GetDynVal(pData, "LLMCalls", "llmCalls")
    set rec.LLMCalls = $select(llmCallsVal="":0, 1:+llmCallsVal)

    set tokensInVal = ..GetDynVal(pData, "TokensIn", "tokensIn")
    set rec.TokensIn = $select(tokensInVal="":0, 1:+tokensInVal)

    set tokensOutVal = ..GetDynVal(pData, "TokensOut", "tokensOut")
    set rec.TokensOut = $select(tokensOutVal="":0, 1:+tokensOutVal)

    set createdVal = ..GetDynVal(pData, "CreatedAt", "createdAt")
    if (createdVal '= "") {
        set rec.CreatedAt = createdVal
    }

    set sc = rec.%Save()
    if $$$ISOK(sc) {
        set pId = rec.%Id()
    }
    quit sc
}

/// Write to stdout a JSON array of the latest decision per CaseId (or just that case) with all fields,
/// using %DynamicArray %ToJSON.
ClassMethod ReportJSON(caseId As %String = "") As %Status
{
    set filterCase = $zstrip(caseId, "<>W")
    kill latestByCase

    set stmt = ##class(%SQL.Statement).%New()
    set sql = "SELECT ID, CaseId FROM InteropOps_Data.Decision ORDER BY ID ASC"
    set sc = stmt.%Prepare(sql)
    if $$$ISOK(sc) {
        set rs = stmt.%Execute()
        while rs.%Next() {
            set rowId = rs.%Get("ID")
            set rowCase = $zstrip(rs.%Get("CaseId"), "<>W")
            if (rowCase = "") {
                set rowCase = "UNKNOWN_" _ rowId
            }
            if (filterCase '= "") && ($zconvert(rowCase, "U") '= $zconvert(filterCase, "U")) {
                continue
            }
            set latestByCase(rowCase) = rowId
        }
    }

    set arr = ##class(%Library.DynamicArray).%New()
    set cKey = ""
    for {
        set cKey = $order(latestByCase(cKey))
        quit:(cKey = "")
        set id = latestByCase(cKey)
        set obj = ..%OpenId(id)
        if '$isobject(obj) {
            continue
        }
        set item = ##class(%Library.DynamicObject).%New()
        set item.ID = +obj.%Id()
        set item.CaseId = obj.CaseId
        set item.MSH10 = obj.MSH10
        set item.SessionId = $select(obj.SessionId="":"", 1:+obj.SessionId)
        set item.Mode = obj.Mode
        set item.Source = obj.Source
        set item.Action = obj.Action
        set item.Target = obj.Target
        set item.Factor = $select(obj.Factor="":"", 1:+obj.Factor)
        set item.Reason = obj.Reason
        set item.GateResult = obj.GateResult
        set item.FinalStatus = obj.FinalStatus
        set item.Evidence = ..ParseOrText(obj.EvidenceJSON, 1)
        set item.GateDetail = ..ParseOrText(obj.GateDetail, 0)
        set item.TaskId = obj.TaskId
        set item.LLMCalls = +obj.LLMCalls
        set item.TokensIn = +obj.TokensIn
        set item.TokensOut = +obj.TokensOut
        set item.CreatedAt = obj.CreatedAt
        do arr.%Push(item)
    }

    do arr.%ToJSON()
    quit $$$OK
}

/// Return parsed JSON (%DynamicAbstractObject) when pText is valid JSON; otherwise the text
/// (or an empty array when pArray=1 and the text is empty).
ClassMethod ParseOrText(pText As %String, pArray As %Boolean = 0) [ Private ]
{
    if (pText = "") {
        quit $select(pArray:##class(%Library.DynamicArray).%New(), 1:"")
    }
    try {
        set v = ##class(%Library.DynamicAbstractObject).%FromJSON(pText)
    } catch ex {
        set v = pText
    }
    quit v
}

/// Delete all rows from InteropOps_Data.Decision for demo resets.
ClassMethod Purge() As %Status
{
    quit ..%KillExtent()
}

/// Smoke-test cleanup (scripts/smoke_generic.sh): delete ONE row by id, only if its MSH10 equals pMsh10 and its
/// CaseId is not a demo case (Cnn), then kill ^IOA.Batch of that CaseId. Writes SMOKE_DELETED=1|0 (reason).
ClassMethod DeleteSmokeRow(pId As %Integer, pMsh10 As %String) As %Boolean
{
    set ok = 0, why = ""
    set obj = $select(+pId > 0: ..%OpenId(+pId), 1: "")
    if '$isobject(obj) {
        set why = "no row " _ pId
    } elseif ($zstrip(pMsh10, "<>W") = "") || (obj.MSH10 '= pMsh10) {
        set why = "MSH10 mismatch"
    } elseif ($zstrip(obj.CaseId, "<>W") = "") || (##class(InteropOps.Util.Ids).CaseIdFromMSH10(obj.CaseId) '= "") {
        set why = "demo or empty CaseId, refused"
    } else {
        set case = obj.CaseId, obj = ""
        set sc = ..%DeleteId(+pId)
        if $$$ISOK(sc) {
            kill ^IOA.Batch(case)
            set ok = 1
        } else {
            set why = $system.Status.GetErrorText(sc)
        }
    }
    write "SMOKE_DELETED=", ok, $select(why '= "": " (" _ why _ ")", 1: ""), !
    quit ok
}

}
