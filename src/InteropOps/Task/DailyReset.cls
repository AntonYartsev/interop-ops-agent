/// Task Manager task: daily reset of the agent budget ^IOA.Budget (structure from Agent.Operation, every non-REPLAY kind:
/// ^IOA.Budget("calls") = calls reserved/used against BUDGETCALLS, ("tokens_in") / ("tokens_out") = token totals,
/// ("usd") = estimated USD spent against IOA_MAX_USD). The whole global is killed, so the USD counter is reset too.
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
            set calls = +$get(^IOA.Budget("calls")), tin = +$get(^IOA.Budget("tokens_in")), tout = +$get(^IOA.Budget("tokens_out")), usd = +$get(^IOA.Budget("usd"))
            kill ^IOA.Budget
            lock -^IOA.Budget
            set msg = "Daily budget reset: calls=" _ calls _ " tokens_in=" _ tin _ " tokens_out=" _ tout _ " usd=" _ $fnumber(usd, "", 4) _ " -> 0"
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
