/// Approved decision for IOA.Lookup.Apply
Class InteropOps.Msg.ApplyRequest Extends Ens.Request
{

Property CaseId As %String;

Property DecisionJSON As %String(MAXLEN = "");

Property TaskId As %String;

/// SHA-256 of the batch that was reviewed (InteropOps.Rules.Data.BatchSHA at ingest)
Property BatchSHA As %String(MAXLEN = 64);

}
