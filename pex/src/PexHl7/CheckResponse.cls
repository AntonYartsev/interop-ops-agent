/// Agent-evidence result: IRIS validation vs NHapi (.NET) second opinion plus OBX rules.
/// FindingsJson is a JSON array of {severity,path,code,message,source(both|dotnet|iris),rule}.
Class PexHl7.CheckResponse Extends Ens.Response
{

Property Fixture As %String(MAXLEN = 200);

Property MessageControlId As %String(MAXLEN = 200);

Property Engine As %String(MAXLEN = 500);

Property IrisValSpec As %String(MAXLEN = 50);

Property IrisValid As %Boolean;

Property Errors As %Integer;

Property Warnings As %Integer;

Property Infos As %Integer;

Property Agree As %Integer;

Property DotNetOnly As %Integer;

Property IrisOnly As %Integer;

Property FindingsJson As %String(MAXLEN = "");

Storage Default
{
<Data name="CheckResponseDefaultData">
<Subscript>"CheckResponse"</Subscript>
<Value name="1">
<Value>Fixture</Value>
</Value>
<Value name="2">
<Value>MessageControlId</Value>
</Value>
<Value name="3">
<Value>Engine</Value>
</Value>
<Value name="4">
<Value>IrisValSpec</Value>
</Value>
<Value name="5">
<Value>IrisValid</Value>
</Value>
<Value name="6">
<Value>Errors</Value>
</Value>
<Value name="7">
<Value>Warnings</Value>
</Value>
<Value name="8">
<Value>Infos</Value>
</Value>
<Value name="9">
<Value>Agree</Value>
</Value>
<Value name="10">
<Value>DotNetOnly</Value>
</Value>
<Value name="11">
<Value>IrisOnly</Value>
</Value>
<Value name="12">
<Value>FindingsJson</Value>
</Value>
</Data>
<DefaultData>CheckResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
