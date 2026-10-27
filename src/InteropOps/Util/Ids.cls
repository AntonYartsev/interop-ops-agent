/// The ONE place that knows the case / MSH-10 id format. Accepts both separators: "Cnn-MSG031" and "Cnn_MSG031".
Class InteropOps.Util.Ids
{

/// "Cnn-MSG031" or "Cnn_MSG031" (or a file name "Cnn.hl7") -> "Cnn". Returns "" if the id does not start with a case prefix (C + 2 digits).
ClassMethod CaseIdFromMSH10(pMsh10 As %String) As %String
{
    Set tId = $ZSTRIP(pMsh10, "<>W")
    Return $SELECT($MATCH(tId, "(?i)C\d\d([-_.].*)?"): $ZCONVERT($EXTRACT(tId, 1, 3), "U"), 1: "")
}

/// Canonical MSH-10 form of this feed: "Cnn_MSG031" -> "Cnn-MSG031" (only the separator after the case prefix changes).
ClassMethod NormMSH10(pMsh10 As %String) As %String
{
    Set tId = $ZSTRIP(pMsh10, "<>W")
    If $MATCH(tId, "(?i)C\d\d_.*") Set $EXTRACT(tId, 4) = "-"
    Return tId
}

/// "Cnn-name.hl7" or ".../Cnn_x.hl7" -> "Cnn"; "" if the name has no case prefix.
ClassMethod CaseIdFromFile(pFileName As %String) As %String
{
    Set tName = $TRANSLATE(pFileName, "\", "/")
    Return ..CaseIdFromMSH10($PIECE(tName, "/", $LENGTH(tName, "/")))
}

/// Case id of a file: Cnn prefix of the MSH-10 or of the file name (demo cases), else the file name without extension,
/// else MSH-10, else "F"_session id. Sanitised for a global subscript, max 32 chars, never empty.
ClassMethod CaseIdForFile(pFileName As %String, pMsh10 As %String, pSessionId As %String) As %String
{
    Set tId = ..CaseIdFromMSH10(pMsh10)
    Set:tId="" tId = ..CaseIdFromFile(pFileName)
    If tId="" {
        Set tName = $TRANSLATE(pFileName, "\", "/")
        Set tName = $PIECE(tName, "/", $LENGTH(tName, "/"))
        Set:$LENGTH(tName, ".")>1 tName = $PIECE(tName, ".", 1, $LENGTH(tName, ".") - 1)
        Set tId = ..Clean(tName)
    }
    Set:tId="" tId = ..Clean(pMsh10)
    Set:tId="" tId = "F" _ $SELECT($GET(pSessionId)'="": pSessionId, 1: $ZHOROLOG\1)
    Return tId
}

ClassMethod Clean(pText As %String) As %String
{
    Return $EXTRACT($ZSTRIP($ZSTRIP($TRANSLATE($GET(pText), "|^~\&", "_____"), "*", $CHAR(1,31)_" ./:"_$CHAR(34)_"'"), "<>", "_"), 1, 32)
}

/// Self-check: do ##class(InteropOps.Util.Ids).Test() -> writes IDS_TEST=PASS|FAIL
ClassMethod Test() As %Boolean
{
    Set tOk = (..CaseIdFromMSH10("C06-MSG031") = "C06") && (..CaseIdFromMSH10("c06_MSG031") = "C06") && (..CaseIdFromMSH10("H-MSG1") = "")
    Set tOk = tOk && (..NormMSH10("C06_MSG031") = "C06-MSG031") && (..NormMSH10("C06-MSG031") = "C06-MSG031") && (..NormMSH10("X_1") = "X_1")
    Set tOk = tOk && (..CaseIdFromFile("/irisdev/app/cases/in/C01-new-code-sod.hl7") = "C01") && (..CaseIdFromFile("C10.hl7") = "C10")
    Set tOk = tOk && (..CaseIdForFile("/x/lab-feed-oct.hl7", "LAB-1", 5) = "lab-feed-oct") && (..CaseIdForFile("", "", 7) = "F7") && (..CaseIdForFile("a.hl7", "C03-MSG1", 7) = "C03") && (..CaseIdForFile("", "X 1", 7) = "X1")
    Write "IDS_TEST=", $SELECT(tOk: "PASS", 1: "FAIL"), !
    Return tOk
}

}
