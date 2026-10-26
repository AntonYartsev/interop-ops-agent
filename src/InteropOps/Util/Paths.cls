/// The ONE place for data / case file paths. Override with ^IOA.Config("dataDir") / ^IOA.Config("casesDir").
Class InteropOps.Util.Paths
{

ClassMethod DataDir() As %String
{
    Return ..Dir($GET(^IOA.Config("dataDir")), "/irisdev/app/data/", "/home/irisowner/dev/data/")
}

ClassMethod CasesDir() As %String
{
    Return ..Dir($GET(^IOA.Config("casesDir")), "/irisdev/app/cases/", "/home/irisowner/dev/cases/")
}

ClassMethod Dir(pOverride As %String, pDefault As %String, pAlt As %String) As %String [ Private ]
{
    If pOverride '= "" Return ##class(%File).NormalizeDirectory(pOverride)
    Return $SELECT(##class(%File).DirectoryExists(pDefault): pDefault, 1: pAlt)
}

/// Parse a JSON file from DataDir()
ClassMethod ReadJSON(pFile As %String) As %DynamicAbstractObject
{
    Set tStream = ##class(%Stream.FileCharacter).%New()
    Set tStream.TranslateTable = "UTF8"
    $$$ThrowOnError(tStream.LinkToFile(..DataDir() _ pFile))
    Return ##class(%DynamicAbstractObject).%FromJSON(tStream)
}

}
