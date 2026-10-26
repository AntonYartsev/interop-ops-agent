Class InteropOps.Msg.GateResponse Extends Ens.Response
{

/// GATE_PASSED | GATE_REJECTED | NOT_A_PATCH
Property GateStatus As %String;

Property FinalAction As %String;

Property Summary As %String(MAXLEN = 2000);

Property GateJSON As %String(MAXLEN = "");

}
