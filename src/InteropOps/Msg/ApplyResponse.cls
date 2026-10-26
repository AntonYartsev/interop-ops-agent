Class InteropOps.Msg.ApplyResponse Extends Ens.Response
{

/// {applied, reprocess{total, valid, ...}, llm_calls}
Property ResultJSON As %String(MAXLEN = "");

}
