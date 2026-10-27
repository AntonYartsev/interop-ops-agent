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

Parameter SETTINGS = "TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},IrisValSpec:Basic,DocType:Basic,DotNetTimeout:Basic";

/// Seconds to wait for the .NET operation before degrading to IRIS-only findings (batch requests).
Property DotNetTimeout As %Integer [ InitialExpression = 30 ];

Method OnRequest(pRequest As PexHl7.CheckRequest, Output pResponse As PexHl7.CheckResponse) As %Status
{
	if pRequest.%IsA("PexHl7.BatchCheckRequest") quit ..OnBatch(pRequest,.pResponse)
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

/// Batch: IRIS-validate every message, ONE PEX call with the whole batch, aggregated findings back.
/// Soft degradation: if the .NET side fails or times out, the response carries the IRIS findings only,
/// Status=unavailable and a DOTNET_UNAVAILABLE warning; the method still returns $$$OK.
Method OnBatch(pRequest As PexHl7.BatchCheckRequest, Output pResponse As PexHl7.BatchCheckResponse) As %Status
{
	set pResponse=##class(PexHl7.BatchCheckResponse).%New()
	set pResponse.Fixture=pRequest.Fixture, pResponse.IrisValSpec=..IrisValSpec, pResponse.Messages=pRequest.Messages.Count()
	set tItems=[], tInvalid=0, tIrisAgg={}
	for i=1:1:pRequest.Messages.Count() {
		set tText=$replace($replace(pRequest.Messages.GetAt(i),$c(13,10),$c(13)),$c(10),$c(13))
		set tErrs=[], tSC=$$$OK
		try {
			set tDoc=##class(EnsLib.HL7.Message).ImportFromString(tText,.tSC)
			if $$$ISOK(tSC) {
				set tDoc.DocType=..DocType
				set tVal=##class(EnsLib.HL7.Util.Validator).Validate(tDoc,..IrisValSpec)
				if $$$ISERR(tVal) {
					kill tList do $system.Status.DecomposeStatus(tVal,.tList)
					for k=1:1:$g(tList) do tErrs.%Push($g(tList(k)))
				}
			} else { do tErrs.%Push("IRIS import: "_$system.Status.GetErrorText(tSC)) }
		} catch ex { do tErrs.%Push("IRIS validate: "_ex.DisplayString()) }
		set:tErrs.%Size() tInvalid=tInvalid+1
		set tMsh10=$piece($piece(tText,$c(13)),"|",10)
		set tIt=tErrs.%GetIterator()
		while tIt.%GetNext(,.tE) {
			set tKey=$extract(tE,1,200), tA=tIrisAgg.%Get(tKey)
			if '$isobject(tA) { set tA={"severity":"error","path":"","code":"IRIS_VALIDATION","message":(tKey),"source":"iris","rule":"iris-validation","count":0,"examples":[]} do tIrisAgg.%Set(tKey,tA) }
			set tA.count=tA.count+1 do:(tA.examples.%Size()<3)&&(tMsh10'="") tA.examples.%Push(tMsh10)
		}
		do tItems.%Push({"hl7":(tText),"irisErrors":(tErrs)})
	}
	set pResponse.IrisInvalid=tInvalid
	try {
		// fail fast (no queued request, no timeout wait) when the .NET operation is disabled or not in the production
		if '##class(Ens.Director).IsItemEnabled(..TargetConfigName) throw ##class(%Exception.General).%New(..TargetConfigName_" is disabled or not configured")
		set tReq=##class(EnsLib.PEX.Message).%New()
		set tReq.%classname="Hl7Check.OruBatchCheckRequest"
		set tReq.%jsonObject={"fixture":(pRequest.Fixture),"irisValSpec":(..IrisValSpec),"messagesJson":(tItems.%ToJSON())}
		set tSC=..SendRequestSync(..TargetConfigName,tReq,.tResp,..DotNetTimeout)
		if $$$ISERR(tSC) throw ##class(%Exception.StatusException).CreateFromStatus(tSC)
		if '$isobject($g(tResp)) throw ##class(%Exception.General).%New("no response from "_..TargetConfigName_" within "_..DotNetTimeout_"s")
		set j=tResp.%jsonObject
		set pResponse.Status="ok", pResponse.Engine=j.engine, pResponse.MessagesWithErrors=j.messagesWithErrors
		set pResponse.Errors=j.errors, pResponse.Warnings=j.warnings, pResponse.Infos=j.infos
		set pResponse.Agree=j.agree, pResponse.DotNetOnly=j.dotnetOnly, pResponse.IrisOnly=j.irisOnly
		set pResponse.FindingsJson=j.findingsJson
	} catch ex {
		set tWhy=$extract(ex.DisplayString(),1,300)
		$$$LOGWARNING("PexHl7 batch "_pRequest.Fixture_": .NET second opinion unavailable, IRIS-only findings ("_tWhy_")")
		set tF=[{"severity":"warning","path":"","code":"DOTNET_UNAVAILABLE","message":(".NET (NHapi) second opinion unavailable: "_tWhy),"source":"iris","rule":"degraded","count":0,"examples":[]}]
		set tIt=tIrisAgg.%GetIterator(), tErrN=0
		while tIt.%GetNext(,.tA) { do tF.%Push(tA) set tErrN=tErrN+tA.count }
		set pResponse.Status="unavailable", pResponse.Warning=".NET unavailable: "_tWhy, pResponse.Engine="IRIS EnsLib.HL7 valspec "_..IrisValSpec_" only"
		set pResponse.MessagesWithErrors=tInvalid, pResponse.Errors=tErrN, pResponse.Warnings=1, pResponse.Infos=0
		set pResponse.Agree=0, pResponse.DotNetOnly=0, pResponse.IrisOnly=tErrN, pResponse.FindingsJson=tF.%ToJSON()
	}
	quit $$$OK
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
