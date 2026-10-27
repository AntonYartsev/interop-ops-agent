Class InteropOps.Msg.AgentRequest Extends Ens.Request
{

Property CaseId As %String;

Property FirstMSH10 As %String(MAXLEN = 64);

Property MessageCount As %Integer;

Property TicketJSON As %String(MAXLEN = "");

/// Deterministic validation evidence (InteropOps.Evidence.Builder.Combine): .NET NHapi second opinion + UCUM.
/// In the prompt unless IOA_EVIDENCE_IN_PROMPT=0; always available through the tool GetValidationEvidence.
Property EvidenceJSON As %String(MAXLEN = "");

}
