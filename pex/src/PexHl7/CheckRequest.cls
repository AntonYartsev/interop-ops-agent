/// One ER7 HL7 v2 message to be checked by the .NET second-opinion operation.
Class PexHl7.CheckRequest Extends Ens.Request
{

Property Fixture As %String(MAXLEN = 200);

Property Seq As %Integer;

Property HL7 As %String(MAXLEN = "");

Storage Default
{
<Data name="CheckRequestDefaultData">
<Subscript>"CheckRequest"</Subscript>
<Value name="1">
<Value>Fixture</Value>
</Value>
<Value name="2">
<Value>Seq</Value>
</Value>
<Value name="3">
<Value>HL7</Value>
</Value>
</Data>
<DefaultData>CheckRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
