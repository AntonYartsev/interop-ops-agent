/// ONE place that cleans free text (provider errors) before it goes to a log, a Decision row or a cassette.
Class InteropOps.Util.Redact
{

/// Replace key-like strings (sk-..., Bearer ..., api_key=...) with "[redacted]", then cut to pMax characters.
ClassMethod Text(pText As %String, pMax As %Integer = 500) As %String
{
    Set tText = pText
    For tRe = "sk-[A-Za-z0-9_\-]{6,}", "(?i)Bearer\s+\S+", "(?i)api[_-]?key[""':= ]+\S+" {
        Set tText = ##class(%Regex.Matcher).%New(tRe, tText).ReplaceAll("[redacted]")
    }
    Return $EXTRACT(tText, 1, pMax)
}

/// Self-check with a FAKE string: returns 1 if all key-like parts are gone
ClassMethod Check() As %Boolean
{
    Set t = ..Text("err sk-test_FAKEFAKEFAKE Bearer abc api_key=zzz9 ok")
    Write t, !
    Return (t '[ "FAKE") && (t '[ "abc") && (t '[ "zzz9") && (t [ "ok")
}

}
