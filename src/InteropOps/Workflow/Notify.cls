/// IOA.Notify.Reviewer: tells the reviewer channel that a new IOA-Reviewers Inbox task waits (sent by IOA.Workflow).
/// Transport: InteropOps.Adapter.ReviewerNotify (webhook POST). The outcome goes to the Event Log.
Class InteropOps.Workflow.Notify Extends Ens.BusinessOperation
{

Parameter ADAPTER = "InteropOps.Adapter.ReviewerNotify";

Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As Ens.StringRequest, Output pResponse As Ens.StringResponse) As %Status
{
    Set tSC = ..Adapter.Post(pRequest.StringValue, .tHttp)
    Quit:$$$ISERR(tSC) tSC
    Set pResponse = ##class(Ens.StringResponse).%New($SELECT(tHttp="": "not configured (IOA_NOTIFY_URL empty), not sent", 1: "sent, HTTP " _ tHttp))
    $$$LOGINFO("reviewer notify: " _ pResponse.StringValue)
    Quit $$$OK
}

}
