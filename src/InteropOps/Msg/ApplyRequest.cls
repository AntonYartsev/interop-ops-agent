/// Approved decision for IOA.Lookup.Apply
Class InteropOps.Msg.ApplyRequest Extends Ens.Request
{

Property CaseId As %String;

Property DecisionJSON As %String(MAXLEN = "");

Property TaskId As %String;

}
