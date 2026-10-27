/// Batch result. Status: ok (IRIS + .NET), unavailable (.NET gateway/BO failed: IRIS findings only, plus a
/// DOTNET_UNAVAILABLE warning; never an error status). FindingsJson: JSON array of aggregated findings
/// {severity,path,code,message,source(both|dotnet|iris),rule,count,examples[MSH-10]}.
Class PexHl7.BatchCheckResponse Extends Ens.Response
{

Property Fixture As %String(MAXLEN = 200);

Property Status As %String(VALUELIST = ",ok,unavailable");

Property Warning As %String(MAXLEN = 1000);

Property Engine As %String(MAXLEN = 500);

Property IrisValSpec As %String(MAXLEN = 50);

Property Messages As %Integer;

Property MessagesWithErrors As %Integer;

Property IrisInvalid As %Integer;

Property Errors As %Integer;

Property Warnings As %Integer;

Property Infos As %Integer;

Property Agree As %Integer;

Property DotNetOnly As %Integer;

Property IrisOnly As %Integer;

Property FindingsJson As %String(MAXLEN = "");

}
