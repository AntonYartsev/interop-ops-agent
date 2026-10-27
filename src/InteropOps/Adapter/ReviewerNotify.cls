/// Outbound adapter: HTTP POST of a Slack/Teams-style JSON {"text": ...} to a reviewer webhook.
/// URL comes from the URL setting, else from env IOA_NOTIFY_URL (LLMConfig.GetVar). Empty URL = not configured, nothing is sent.
Class InteropOps.Adapter.ReviewerNotify Extends Ens.OutboundAdapter
{

/// Webhook URL (http:// or https://). Empty: IOA_NOTIFY_URL
Property URL As %String(MAXLEN = 1000);

/// SSL/TLS configuration name, needed only for https:// URLs
Property SSLConfig As %String;

/// Seconds to wait for the webhook reply
Property Timeout As %Integer [ InitialExpression = 5 ];

Parameter SETTINGS = "URL:Basic,SSLConfig:Basic:sslConfigSelector,Timeout";

Method OnInit() As %Status
{
    Set:..URL="" ..URL = ##class(InteropOps.Config.LLMConfig).GetVar("IOA_NOTIFY_URL")
    Quit $$$OK
}

/// POST {"text": pText} to URL. pHttpStatus = HTTP status code, "" if URL is empty (not configured).
/// A reply other than 2xx is an error status.
Method Post(pText As %String, Output pHttpStatus As %String) As %Status
{
    Set pHttpStatus = ""
    Quit:..URL="" $$$OK
    Set tReq = ##class(%Net.HttpRequest).%New()
    Set tReq.Timeout = ..Timeout, tReq.ContentType = "application/json"
    Set:..SSLConfig'="" tReq.SSLConfiguration = ..SSLConfig
    Do tReq.EntityBody.Write({"text": (pText)}.%ToJSON())
    Set tSC = tReq.Post(..URL)
    Quit:$$$ISERR(tSC) tSC
    Set pHttpStatus = tReq.HttpResponse.StatusCode
    Quit:pHttpStatus\100'=2 $$$ERROR($$$GeneralError, "webhook " _ ..URL _ " replied HTTP " _ pHttpStatus)
    Quit $$$OK
}

}
