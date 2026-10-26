/// IOA.Reprocess: leaf host for resent messages after an approved patch (called only by IOA.Lookup.Apply).
/// Runs DTL + validity on one message with the patched lookup. No triage, no agent, no Decision row, no further sends.
Class InteropOps.Lookup.Reprocess Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As EnsLib.HL7.Message, Output pResponse As Ens.StringResponse) As %Status
{
    Set tR = ##class(InteropOps.Rules.LabToCanonical).CheckMessage(pRequest, .tAux)
    Set pResponse = ##class(Ens.StringResponse).%New(tR.%ToJSON())
    Return $$$OK
}

}
