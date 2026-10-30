Include Ensemble

/// IOA.In.CaseFile: EnsLib.HL7.Service.FileService for cases/in/*.hl7 (one file = the batch of one case).
/// The standard service parses every HL7 message of the file (MessageSchemaCategory 2.5.1 -> ORU_R01) and saves it.
/// Change: the messages are not forwarded one by one; at end of file ONE InteropOps.Msg.CaseRequest with all of them goes to
/// TargetConfigNames in a new session (one Visual Trace session per case).
Class InteropOps.In.CaseFile Extends EnsLib.HL7.Service.FileService
{

Property CaseDocs As list Of EnsLib.HL7.Message [ Transient ];

Method OnInit() As %Status
{
    // FilePath comes from InteropOps.Config.LLMConfig.CasesIn() (env IOA_CASES_IN), not only from the production XData
    Set ..Adapter.FilePath = ##class(InteropOps.Config.LLMConfig).CasesIn()
    // XData ArchivePath is the repository mount; an IPM install without it archives into Util.Paths.CasesDir() archive/
    Set:'##class(%File).DirectoryExists(..Adapter.ArchivePath) ..Adapter.ArchivePath = ##class(InteropOps.Util.Paths).CasesDir() _ "archive/"
    Return ##super()
}

Method OnProcessInput(pFileStream As %CharacterStream, Output pOutput As %RegisteredObject) As %Status
{
    Do ..CaseDocs.Clear()
    Set tSC = ##super(pFileStream, .pOutput)
    Quit:..CaseDocs.Count()=0 tSC
    Set tReq = ##class(InteropOps.Msg.CaseRequest).%New()
    Set tReq.FileName = pFileStream.Filename, tReq.MessageCount = ..CaseDocs.Count()
    Set tReq.FirstMSH10 = ##class(InteropOps.Util.Ids).NormMSH10(..CaseDocs.GetAt(1).GetValueAt("MSH:10"))
    Set tReq.CaseId = ##class(InteropOps.Util.Ids).CaseIdForFile(pFileStream.Filename, tReq.FirstMSH10, ..%SessionId)
    For i = 1:1:..CaseDocs.Count() Do tReq.Messages.Insert(..CaseDocs.GetAt(i))
    Do ..CaseDocs.Clear()
    // new session for the case
    Set ..%SessionId = ""
    Kill $$$JobSessionId
    For i = 1:1:$LENGTH(..TargetConfigNames, ",") {
        Set tTarget = $ZSTRIP($PIECE(..TargetConfigNames, ",", i), "<>W")
        Set:tTarget'="" tSC = $$$ADDSC(tSC, ..SendRequestAsync(tTarget, tReq))
    }
    $$$LOGINFO("case " _ tReq.CaseId _ ": " _ tReq.MessageCount _ " HL7 messages from " _ tReq.FileName)
    Quit tSC
}

/// Called by the parser for each HL7 message of the file: resolve the doc type, save, collect (no forwarding)
Method standardOnProcessInput(pDocIn As EnsLib.HL7.Message, Output pDocOut As EnsLib.HL7.Message) As %Status
{
    Set pDocOut = $$$NULLOREF
    Set tSC = ..resolveAndIndex(pDocIn, pDocIn.getSegmentByIndex(1))
    Quit:$$$ISERR(tSC) tSC
    Set pDocIn.IsMutable = 0
    Set tSC = pDocIn.%Save()
    Do:$$$ISOK(tSC) ..CaseDocs.Insert(pDocIn)
    Quit tSC
}

}
