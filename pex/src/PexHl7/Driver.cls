/// Test driver: split a fixture file into messages and send each through PexHl7CheckBP.
/// do ##class(PexHl7.Driver).RunFixture("/home/irisowner/fixtures/C11-critical-k.hl7")
Class PexHl7.Driver
{

ClassMethod RunFixture(pFile As %String, pMax As %Integer = 0, pVerbose As %Boolean = 1) As %DynamicObject
{
	set s=##class(%Stream.FileCharacter).%New() set sc=s.LinkToFile(pFile) if 'sc { write $system.Status.GetErrorText(sc),! quit "" }
	set t="" while 's.AtEnd { set t=t_s.Read(32000) }
	set t=$replace($replace(t,$c(13,10),$c(13)),$c(10),$c(13))
	set name=$p($p(pFile,"/",*),".",1)
	set parts=$lfs(t,$c(13)_"MSH|"), sum={"fixture":(name),"messages":0,"irisInvalid":0,"errors":0,"warnings":0,"infos":0,"agree":0,"dotnetOnly":0,"irisOnly":0,"codes":{},"sessions":[],"samples":[]}
	for i=1:1:$ll(parts) {
		quit:pMax&&(i>pMax)
		set msg=$s(i=1:$lg(parts,1),1:"MSH|"_$lg(parts,i)) continue:$zstrip(msg,"<>W")=""
		set req=##class(PexHl7.CheckRequest).%New(), req.Fixture=name, req.Seq=i, req.HL7=msg
		set sc=##class(EnsLib.Testing.Service).SendTestRequest("PexHl7CheckBP",req,.resp,.sid,1)
		if 'sc { write "send failed #",i,": ",$system.Status.GetErrorText(sc),! quit }
		do sum.sessions.%Push(+sid) set sum.messages=sum.messages+1
		set:'resp.IrisValid sum.irisInvalid=sum.irisInvalid+1
		for k="Errors","Warnings","Infos","Agree","DotNetOnly","IrisOnly" { set key=$s(k="DotNetOnly":"dotnetOnly",k="IrisOnly":"irisOnly",1:$zcvt($e(k),"L")_$e(k,2,*)) do sum.%Set(key,sum.%Get(key)+$property(resp,k)) }
		set fa=[].%FromJSON(resp.FindingsJson), it=fa.%GetIterator()
		while it.%GetNext(,.f) {
			set c=f.code_"/"_f.source do sum.codes.%Set(c,sum.codes.%Get(c)+1)
			if '$d(seen(c)) { set seen(c)=1 do f.%Set("msg",resp.MessageControlId) do sum.samples.%Push(f) }
		}
	}
	if pVerbose {
		write "== ",name," messages=",sum.messages," irisInvalid=",sum.irisInvalid," errors=",sum.errors," warnings=",sum.warnings," infos=",sum.infos," agree=",sum.agree," dotnetOnly=",sum.dotnetOnly," irisOnly=",sum.irisOnly,!
		if sum.sessions.%Size() write "   sessions ",sum.sessions.%Get(0),"..",sum.sessions.%Get(sum.sessions.%Size()-1),!
		write "   codes ",sum.codes.%ToJSON(),!
		set it=sum.samples.%GetIterator() while it.%GetNext(,.f) { write "   ",f.%ToJSON(),! }
	}
	quit sum
}

}
