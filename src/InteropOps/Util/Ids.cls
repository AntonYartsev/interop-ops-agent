/// The ONE place that knows the case / MSH-10 id format. Accepts both separators: "C06-MSG031" and "C06_MSG031".
Class InteropOps.Util.Ids
{

/// "C06-MSG031" or "C06_MSG031" (or a file name "C06.hl7") -> "C06". Returns "" if the id does not start with a case prefix (C + 2 digits).
ClassMethod CaseIdFromMSH10(pMsh10 As %String) As %String
{
    Set tId = $ZSTRIP(pMsh10, "<>W")
    Return $SELECT($MATCH(tId, "(?i)C\d\d([-_.].*)?"): $ZCONVERT($EXTRACT(tId, 1, 3), "U"), 1: "")
}

/// Canonical MSH-10 form of this feed: "C06_MSG031" -> "C06-MSG031" (only the separator after the case prefix changes).
ClassMethod NormMSH10(pMsh10 As %String) As %String
{
    Set tId = $ZSTRIP(pMsh10, "<>W")
    If $MATCH(tId, "(?i)C\d\d_.*") Set $EXTRACT(tId, 4) = "-"
    Return tId
}

/// "C01-new-code-sod.hl7" or ".../C01_x.hl7" -> "C01"; "" if the name has no case prefix.
ClassMethod CaseIdFromFile(pFileName As %String) As %String
{
    Set tName = $TRANSLATE(pFileName, "\", "/")
    Return ..CaseIdFromMSH10($PIECE(tName, "/", $LENGTH(tName, "/")))
}

/// Self-check: do ##class(InteropOps.Util.Ids).Test() -> writes IDS_TEST=PASS|FAIL
ClassMethod Test() As %Boolean
{
    Set tOk = (..CaseIdFromMSH10("C06-MSG031") = "C06") && (..CaseIdFromMSH10("c06_MSG031") = "C06") && (..CaseIdFromMSH10("H-MSG1") = "")
    Set tOk = tOk && (..NormMSH10("C06_MSG031") = "C06-MSG031") && (..NormMSH10("C06-MSG031") = "C06-MSG031") && (..NormMSH10("X_1") = "X_1")
    Set tOk = tOk && (..CaseIdFromFile("/irisdev/app/cases/in/C01-new-code-sod.hl7") = "C01") && (..CaseIdFromFile("C10.hl7") = "C10")
    Write "IDS_TEST=", $SELECT(tOk: "PASS", 1: "FAIL"), !
    Return tOk
}

}
