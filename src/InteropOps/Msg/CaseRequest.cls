/// One case file = one batch of HL7 messages (sent by IOA.In.CaseFile at end of file, one session per case)
Class InteropOps.Msg.CaseRequest Extends Ens.Request
{

Property CaseId As %String;

Property FileName As %String(MAXLEN = 500);

Property FirstMSH10 As %String(MAXLEN = 64);

Property MessageCount As %Integer;

/// The parsed HL7 messages of the file (EnsLib.HL7.Message, doc type 2.5.1:ORU_R01)
Property Messages As list Of EnsLib.HL7.Message;

}
