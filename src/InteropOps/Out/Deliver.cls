/// IOA.Deliver: the downstream end of the flow. After the final decision of a case it writes the batch through the DTL
/// (with the lookup and unit factors in force now) to two files:
///   <cases>/out/<CaseId>.hl7  = delivered messages (canonical LOINC, units and ranges)
///   <cases>/held/<CaseId>.hl7 = held messages (raw, as received)
/// passed, applied: all messages delivered. quarantined: the first copy of HoldMSH10 is delivered, the other copies are held.
/// escalated, rejected: all messages held until an engineer acts.
Class InteropOps.Out.Deliver Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As InteropOps.Msg.DeliverRequest, Output pResponse As Ens.StringResponse) As %Status
{
    Set tR = ..Run(pRequest.CaseId, pRequest.FinalStatus, pRequest.HoldMSH10)
    Set pResponse = ##class(Ens.StringResponse).%New(tR.%ToJSON())
    $$$LOGINFO("deliver " _ pRequest.CaseId _ " " _ pRequest.FinalStatus _ ": " _ pResponse.StringValue)
    Return $$$OK
}

ClassMethod Run(pCaseId As %String, pStatus As %String, pHoldMSH10 As %String = "") As %DynamicObject
{
    Set tDeliverAll = $LISTFIND($LISTBUILD("passed", "applied", "quarantined"), pStatus) > 0
    Set tKey = ##class(InteropOps.Util.Ids).NormMSH10(pHoldMSH10), tSeen = 0
    Set tOut = ..Open("out", pCaseId), tHeld = ..Open("held", pCaseId)
    Set tAux("lookup") = ##class(InteropOps.Rules.Data).Lookup(), (tNOut, tNHeld) = 0
    For i = 1:1:##class(InteropOps.Rules.Data).BatchCount(pCaseId) {
        Set tRaw = ##class(InteropOps.Rules.Data).BatchRaw(pCaseId, i), tHold = 'tDeliverAll
        If 'tHold && (pStatus = "quarantined") && (##class(InteropOps.Util.Ids).NormMSH10(##class(InteropOps.Rules.Data).MSH10(tRaw)) = tKey) {
            Set tSeen = tSeen + 1, tHold = (tSeen > 1)
        }
        If tHold {
            Do tHeld.Write(tRaw _ $CHAR(10)), $INCREMENT(tNHeld)
            Continue
        }
        Set tIn = ##class(EnsLib.HL7.Message).ImportFromString(tRaw, .tSC)
        $$$ThrowOnError(tSC)
        $$$ThrowOnError(##class(InteropOps.Rules.LabToCanonical).Transform(tIn, .tMsg, .tAux))
        Do tOut.Write(tMsg.OutputToString() _ $CHAR(10)), $INCREMENT(tNOut)
    }
    $$$ThrowOnError(tOut.%Save())
    $$$ThrowOnError(tHeld.%Save())
    Return {"delivered": (tNOut), "held": (tNHeld), "out_file": (tOut.Filename), "held_file": (tHeld.Filename)}
}

/// New (truncated) file <cases>/<pSub>/<pCaseId>.hl7
ClassMethod Open(pSub As %String, pCaseId As %String) As %Stream.FileCharacter [ Private ]
{
    Set tDir = ##class(InteropOps.Util.Paths).CasesDir() _ pSub _ "/"
    Do ##class(%File).CreateDirectoryChain(tDir)
    Set tFile = tDir _ $TRANSLATE(pCaseId, "/\:", "___") _ ".hl7"
    Do:##class(%File).Exists(tFile) ##class(%File).Delete(tFile)
    Set tS = ##class(%Stream.FileCharacter).%New()
    $$$ThrowOnError(tS.LinkToFile(tFile))
    Return tS
}

}
