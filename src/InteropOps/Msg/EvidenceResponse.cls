/// Result of a deterministic evidence step. Status: ok | unavailable (soft degradation, never a fault).
/// FindingsJSON: JSON array of aggregated findings.
Class InteropOps.Msg.EvidenceResponse Extends Ens.Response
{

Property CaseId As %String;

Property Kind As %String;

Property Status As %String;

Property Summary As %String(MAXLEN = 2000);

Property FindingsJSON As %String(MAXLEN = "");

}
