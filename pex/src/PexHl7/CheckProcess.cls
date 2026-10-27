/// Wrapper BP: validates the message with IRIS's own EnsLib.HL7 validator, then asks the
/// C# PEX operation (NHapi) for a second opinion and returns the merged, diffed findings.
Class PexHl7.CheckProcess Extends Ens.BusinessProcess
{

/// Target config item: EnsLib.PEX.BusinessOperation hosting Hl7Check.OruCheckOperation.
Property TargetConfigName As Ens.DataType.ConfigName [ InitialExpression = "PexHl7Check" ];

/// IRIS validation flags (see EnsLib.HL7.Util.Validator): DocType, map, required fields,
/// segment structure, data types; -x = report all errors. Code tables ('t') left out on purpose:
/// local coding systems ('L') make every OBX-3 fail table 396.
Property IrisValSpec As %String [ InitialExpression = "dm-zrny-x" ];

/// HL7 DocType used for IRIS validation.
Property DocType As %String [ InitialExpression = "2.5.1:ORU_R01" ];

Parameter SETTINGS = "TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},IrisValSpec:Basic,DocType:Basic";

Method OnRequest(pRequest As PexHl7.CheckRequest, Output pResponse As PexHl7.CheckResponse) As %Status
{
	set tSC=$$$OK
	try {
		set tText=$replace($replace(pRequest.HL7,$c(13,10),$c(13)),$c(10),$c(13))
		set tDoc=##class(EnsLib.HL7.Message).ImportFromString(tText,.tSC) quit:$$$ISERR(tSC)
		set tDoc.DocType=..DocType
		set tVal=##class(EnsLib.HL7.Util.Validator).Validate(tDoc,..IrisValSpec)
		set tErrs=[]
		if $$$ISERR(tVal) {
			do $system.Status.DecomposeStatus(tVal,.tList)
			for i=1:1:$g(tList) do tErrs.%Push($g(tList(i)))
		}
		set tReq=##class(EnsLib.PEX.Message).%New()
		set tReq.%classname="Hl7Check.OruCheckRequest"
		set tReq.%jsonObject={"fixture":(pRequest.Fixture_"#"_pRequest.Seq),"hl7":(tText),"irisValSpec":(..IrisValSpec),"irisErrors":(tErrs.%ToJSON())}
		set tSC=..SendRequestSync(..TargetConfigName,tReq,.tResp) quit:$$$ISERR(tSC)
		set j=tResp.%jsonObject
		set pResponse=##class(PexHl7.CheckResponse).%New()
		set pResponse.Fixture=j.fixture, pResponse.MessageControlId=j.messageControlId, pResponse.Engine=j.engine
		set pResponse.IrisValSpec=..IrisValSpec, pResponse.IrisValid=$$$ISOK(tVal)
		set pResponse.Errors=j.errors, pResponse.Warnings=j.warnings, pResponse.Infos=j.infos
		set pResponse.Agree=j.agree, pResponse.DotNetOnly=j.dotnetOnly, pResponse.IrisOnly=j.irisOnly
		set pResponse.FindingsJson=j.findingsJson
	} catch ex { set tSC=ex.AsStatus() }
	quit tSC
}

Storage Default
{
<Data name="CheckProcessDefaultData">
<Subscript>"CheckProcess"</Subscript>
<Value name="1">
<Value>TargetConfigName</Value>
</Value>
<Value name="2">
<Value>IrisValSpec</Value>
</Value>
<Value name="3">
<Value>DocType</Value>
</Value>
</Data>
<DefaultData>CheckProcessDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
