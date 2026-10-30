/// The ONE place for data / case / replay file paths. Override with ^IOA.Config("dataDir") / ^IOA.Config("casesDir").
/// Without an override: the repository mount /irisdev/app/, then /home/irisowner/dev/, then the IPM install
/// directory InstallDir() (module.xml FileCopy) when no repository is mounted.
Class InteropOps.Util.Paths
{

/// IPM install directory of cases/, data/, replay/: module.xml FileCopy target ${mgrdir}interop-ops-agent/
ClassMethod InstallDir() As %String
{
    Return ##class(%File).NormalizeDirectory($SYSTEM.Util.ManagerDirectory() _ "interop-ops-agent")
}

ClassMethod DataDir() As %String
{
    Return ..Dir($GET(^IOA.Config("dataDir")), "data", "/irisdev/app/data/", "/home/irisowner/dev/data/")
}

ClassMethod CasesDir() As %String
{
    Return ..Dir($GET(^IOA.Config("casesDir")), "cases", "/irisdev/app/cases/", "/home/irisowner/dev/cases/")
}

/// Default cassette directory (LLMConfig.ReplayDir() when env IOA_REPLAY_DIR is empty)
ClassMethod ReplayDir() As %String
{
    Return ..Dir("", "replay", "/irisdev/app/replay/", "/home/irisowner/dev/replay/")
}

ClassMethod Dir(pOverride As %String, pSub As %String, pDefault As %String, pAlt As %String) As %String [ Private ]
{
    If pOverride '= "" Return ##class(%File).NormalizeDirectory(pOverride)
    // Repository mount first: demo.sh drops cases into the repo cases/in and records cassettes into the repo replay/
    If ##class(%File).DirectoryExists(pDefault) Return pDefault
    If ##class(%File).DirectoryExists(pAlt) Return pAlt
    Return ..InstallDir() _ pSub _ "/"
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
