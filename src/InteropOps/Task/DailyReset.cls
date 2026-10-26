/// Task Manager task: daily reset of the LIVE call counter ^IOA.Budget (structure from Agent.Operation:
/// ^IOA.Budget("calls") = LIVE calls reserved/used against BUDGETCALLS, ("tokens_in") / ("tokens_out") = token totals).
/// Same effect as step 7 of Setup.ResetDemo (kill ^IOA.Budget), nothing else is touched. Turns the total cap into a
/// daily cap. Installed only on request: Setup.InstallDailyReset (IOA_DAILY_RESET=1), removed by UninstallDailyReset.
/// Logs the counter values before the reset to the Event Log (Ens.Util.Log, works outside a production host).
Class InteropOps.Task.DailyReset Extends %SYS.Task.Definition
{

Parameter TaskName = "IOA Daily Budget Reset";

Method OnTask() As %Status
{
    set sc = $$$OK
    try {
        lock +^IOA.Budget:10
        if '$test {
            set sc = $$$ERROR($$$GeneralError, "^IOA.Budget locked, reset skipped")
        } else {
            set calls = +$get(^IOA.Budget("calls")), tin = +$get(^IOA.Budget("tokens_in")), tout = +$get(^IOA.Budget("tokens_out"))
            kill ^IOA.Budget
            lock -^IOA.Budget
            set msg = "Daily budget reset: calls=" _ calls _ " tokens_in=" _ tin _ " tokens_out=" _ tout _ " -> 0"
            try { do ##class(Ens.Util.Log).LogInfo($classname(), "OnTask", msg) } catch { }
        }
    } catch ex {
        lock -^IOA.Budget
        set sc = ex.AsStatus()
    }
    if $$$ISERR(sc) {
        try { do ##class(Ens.Util.Log).LogError($classname(), "OnTask", $system.Status.GetErrorText(sc)) } catch { }
    }
    quit sc
}

}
