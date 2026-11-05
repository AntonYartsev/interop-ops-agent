/// Final decision of a case for IOA.Deliver
Class InteropOps.Msg.DeliverRequest Extends Ens.Request
{

Property CaseId As %String;

/// Decision FinalStatus: passed, applied, quarantined, escalated, rejected
Property FinalStatus As %String;

/// quarantined: MSH-10 whose repeated copies are held
Property HoldMSH10 As %String;

}
