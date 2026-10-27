/// Judge demo page: web application /demo (registered by InteropOps.Setup.EnsureDemoWebApp, unauthenticated,
/// application role IOA-DemoWeb only: data database READ). Routes are read-only except POST /api/run/:case and
/// POST /api/tasks/:id/approve|reject, which raise the write role inside InteropOps.Demo.Write only. Any other POST,
/// PUT, PATCH or DELETE is answered 403.
/// Page assets come from InteropOps.Demo.Page XData (no external CDN, CSP default-src 'self').
Class InteropOps.Demo.REST Extends %CSP.REST
{

Parameter CHARSET = "utf-8";

Parameter CONTENTTYPE = "application/json";

Parameter HandleCorsRequest = 0;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/" Method="GET" Call="Index"/>
<Route Url="/app.css" Method="GET" Call="Css"/>
<Route Url="/app.js" Method="GET" Call="Js"/>
<Route Url="/api/status" Method="GET" Call="Status"/>
<Route Url="/api/cases" Method="GET" Call="Cases"/>
<Route Url="/api/decisions" Method="GET" Call="Decisions"/>
<Route Url="/api/decisions/:id" Method="GET" Call="Decision"/>
<Route Url="/api/trace/:session" Method="GET" Call="Trace"/>
<Route Url="/api/tasks" Method="GET" Call="Tasks"/>
<Route Url="/api/kb" Method="GET" Call="KB"/>
<Route Url="/api/run" Method="GET" Call="LastRun"/>
<Route Url="/api/run/:case" Method="POST" Call="Run"/>
<Route Url="/api/tasks/:id/:action" Method="POST" Call="Decide"/>
<Route Url="/(.*)" Method="POST" Call="Forbidden"/>
<Route Url="/(.*)" Method="PUT" Call="Forbidden"/>
<Route Url="/(.*)" Method="PATCH" Call="Forbidden"/>
<Route Url="/(.*)" Method="DELETE" Call="Forbidden"/>
</Routes>
}

ClassMethod Headers(pType As %String) [ Private ]
{
    Set %response.ContentType = pType
    Do %response.SetHeader("Cache-Control", "no-store")
    Do %response.SetHeader("X-Content-Type-Options", "nosniff")
    Do %response.SetHeader("X-Frame-Options", "DENY")
    Do %response.SetHeader("Referrer-Policy", "no-referrer")
    Do %response.SetHeader("Content-Security-Policy", "default-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
}

ClassMethod Asset(pName As %String, pType As %String) As %Status [ Private ]
{
    Do ..Headers(pType)
    Set tX = ##class(%Dictionary.CompiledXData).%OpenId("InteropOps.Demo.Page||"_pName)
    If '$ISOBJECT(tX) Set %response.Status = "404 Not Found" Quit $$$OK
    Do tX.Data.Rewind()
    While 'tX.Data.AtEnd { Write tX.Data.Read(16000) }
    Quit $$$OK
}

ClassMethod Send(pObj As %DynamicObject, pCode As %Integer) As %Status [ Private ]
{
    Do ..Headers("application/json")
    Set %response.Status = $CASE(pCode, 200: "200 OK", 400: "400 Bad Request", 403: "403 Forbidden", 404: "404 Not Found",
        409: "409 Conflict", 429: "429 Too Many Requests", 503: "503 Service Unavailable", : "500 Internal Server Error")
    If (pCode = 429) && (pObj.retryAfterSec '= "") Do %response.SetHeader("Retry-After", pObj.retryAfterSec)
    Write pObj.%ToJSON()
    Quit $$$OK
}

/// Client IP: the last X-Forwarded-For element (set by Caddy, which replaces untrusted values), else REMOTE_ADDR
ClassMethod Client() As %String [ Private ]
{
    Set tX = $ZSTRIP($PIECE($GET(%request.CgiEnvs("HTTP_X_FORWARDED_FOR")), ",", *), "<>W")
    Quit $SELECT(tX '= "": tX, 1: $GET(%request.CgiEnvs("REMOTE_ADDR")))
}

ClassMethod Index() As %Status
{
    Quit ..Asset("HTML", "text/html")
}

ClassMethod Css() As %Status
{
    Quit ..Asset("CSS", "text/css")
}

ClassMethod Js() As %Status
{
    Quit ..Asset("JS", "application/javascript")
}

ClassMethod Status() As %Status
{
    Try { Set o = ##class(InteropOps.Demo.API).Status(.c) } Catch { Set o = {"error": "internal error"}, c = 500 }
    Quit ..Send(o, c)
}

ClassMethod Cases() As %Status
{
    Try { Set o = ##class(InteropOps.Demo.API).Cases(.c) } Catch { Set o = {"error": "internal error"}, c = 500 }
    Quit ..Send(o, c)
}

ClassMethod Decisions() As %Status
{
    Try { Set o = ##class(InteropOps.Demo.API).Decisions($GET(%request.Data("limit", 1)), .c) } Catch { Set o = {"error": "internal error"}, c = 500 }
    Quit ..Send(o, c)
}

ClassMethod Decision(pId As %String) As %Status
{
    Try { Set o = ##class(InteropOps.Demo.API).Decision(pId, .c) } Catch { Set o = {"error": "internal error"}, c = 500 }
    Quit ..Send(o, c)
}

ClassMethod Trace(pSession As %String) As %Status
{
    Try { Set o = ##class(InteropOps.Demo.API).Trace(pSession, .c) } Catch { Set o = {"error": "internal error"}, c = 500 }
    Quit ..Send(o, c)
}

ClassMethod Tasks() As %Status
{
    Try { Set o = ##class(InteropOps.Demo.API).Tasks($GET(%request.Data("limit", 1)), .c) } Catch { Set o = {"error": "internal error"}, c = 500 }
    Quit ..Send(o, c)
}

ClassMethod KB() As %Status
{
    Try { Set o = ##class(InteropOps.Demo.API).KB($GET(%request.Data("q", 1)), $GET(%request.Data("k", 1)), .c) } Catch { Set o = {"error": "internal error"}, c = 500 }
    Quit ..Send(o, c)
}

ClassMethod LastRun() As %Status
{
    Try { Set o = ##class(InteropOps.Demo.API).LastRun(.c) } Catch { Set o = {"error": "internal error"}, c = 500 }
    Quit ..Send(o, c)
}

/// POST only, and the custom header X-IOA-Demo: 1 (a cross-site form cannot set it; CORS is off)
ClassMethod Run(pCase As %String) As %Status
{
    If $GET(%request.CgiEnvs("HTTP_X_IOA_DEMO")) '= "1" Quit ..Send({"error": "header X-IOA-Demo: 1 required"}, 403)
    Try { Set o = ##class(InteropOps.Demo.Write).Run(pCase, ..Client(), .c) } Catch { Set o = {"error": "internal error"}, c = 500 }
    Quit ..Send(o, c)
}

/// POST /api/tasks/:id/approve|reject (header X-IOA-Demo: 1): only open review tasks of cases run from this page
ClassMethod Decide(pId As %String, pAction As %String) As %Status
{
    If $GET(%request.CgiEnvs("HTTP_X_IOA_DEMO")) '= "1" Quit ..Send({"error": "header X-IOA-Demo: 1 required"}, 403)
    Try { Set o = ##class(InteropOps.Demo.Write).Decide(pId, pAction, ..Client(), .c) } Catch { Set o = {"error": "internal error"}, c = 500 }
    Quit ..Send(o, c)
}

/// Every other write request: the API is read-only
ClassMethod Forbidden(pPath As %String) As %Status
{
    Quit ..Send({"error": "read-only API: the only writes are POST /api/run/:case and POST /api/tasks/:id/approve|reject"}, 403)
}

}
