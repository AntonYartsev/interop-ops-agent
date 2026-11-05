/// Static assets of the demo page (served by InteropOps.Demo.REST at /demo/, /demo/app.css, /demo/app.js).
/// Plain HTML/CSS/JS, no external CDN or font; all data comes from /demo/api/* and is inserted as text (no innerHTML).
Class InteropOps.Demo.Page
{

XData HTML [ MimeType = text/html ]
{
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Interop Ops Agent - demo</title>
<link rel="stylesheet" href="app.css">
</head>
<body>
<header>
  <div class="brand"><b>Interop Ops Agent</b> <span class="muted">HL7 lab-feed triage on InterSystems IRIS - synthetic data</span></div>
  <div id="status" class="status"><span class="muted">loading status...</span></div>
</header>
<main>
  <section class="card wide">
    <h2>Cases <span class="muted small" id="runinfo"></span></h2>
    <table id="cases"><thead><tr><th>Case</th><th>File</th><th>Expected</th><th>Latest decision</th><th>Final</th><th>Source</th><th>LLM calls</th><th>Session</th><th></th></tr></thead><tbody></tbody></table>
    <div id="runbox" class="runbox hidden"></div>
  </section>
  <section class="card wide">
    <h2>Latest agent decisions</h2>
    <table id="decisions"><thead><tr><th>#</th><th>Case</th><th>Action</th><th>Target</th><th>Gate</th><th>Final</th><th>Source</th><th>Mode</th><th>Calls</th><th>Reason / evidence</th><th>Session</th></tr></thead><tbody></tbody></table>
  </section>
  <section class="card wide">
    <h2>Message trace <span class="muted small">Ens.MessageHeader by session</span></h2>
    <form id="traceform" class="row"><label>Session <input id="session" inputmode="numeric" pattern="[0-9]{1,18}" maxlength="18" size="10"></label><button type="submit">Show</button><span id="traceerr" class="err"></span></form>
    <div id="steps" class="steps"></div>
    <table id="trace" class="hidden"><thead><tr><th>Header</th><th>Time (UTC)</th><th>From</th><th>To</th><th>Body</th><th>Type</th><th>Status</th></tr></thead><tbody></tbody></table>
  </section>
  <section class="card wide">
    <h2>Workflow queue <span class="muted small" id="taskcount"></span></h2>
    <table id="tasks"><thead><tr><th>Task</th><th>Subject</th><th>Status</th><th>Action</th><th>Role</th><th>Session</th><th>Review</th></tr></thead><tbody></tbody></table>
  </section>
  <section class="card">
    <h2>Knowledge base <span class="muted small">Vector Search, local embedder</span></h2>
    <form id="kbform" class="row"><input id="kbq" maxlength="200" size="34" placeholder="e.g. unit changed mg/dL to mmol/L"><button type="submit">Search</button><span id="kberr" class="err"></span></form>
    <ol id="kb" class="kb"></ol>
  </section>
</main>
<footer class="muted small">Read-only views plus two actions: "Run" (drops the case file into the production input folder; the current mode and the agent budget apply) and "Approve / Reject as reviewer" (only for the review task of a case run from this page; the standard Workflow completion, as in the Inbox). One run and one review decision per 30 s for all visitors, 20 actions per hour per client. No keys or settings are shown: key is reported only as set / unset.</footer>
<script src="app.js"></script>
</body>
</html>
}

XData CSS [ MimeType = text/css ]
{
:root { --bg:#f5f6f8; --card:#fff; --ink:#1d2330; --mute:#6b7385; --line:#e2e5ea; --ok:#167a3e; --warn:#a35b00; --bad:#b3261e; --acc:#2456c9; }
* { box-sizing: border-box; }
body { margin:0; font:14px/1.4 system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif; background:var(--bg); color:var(--ink); }
header { display:flex; flex-wrap:wrap; gap:12px; justify-content:space-between; align-items:center; padding:12px 18px; background:#1d2330; color:#fff; }
header .muted { color:#b9c0cf; }
.status { display:flex; flex-wrap:wrap; gap:8px; align-items:center; }
.pill { display:inline-block; padding:2px 8px; border-radius:10px; background:#e8ecf5; color:var(--ink); font-size:12px; white-space:nowrap; }
header .pill { background:#343c4f; color:#fff; }
.pill.REPLAY { background:#2456c9; color:#fff; } .pill.LIVE { background:#b3261e; color:#fff; } .pill.MOCK { background:#a35b00; color:#fff; }
.bar { display:inline-block; width:90px; height:8px; background:#454e63; border-radius:4px; vertical-align:middle; overflow:hidden; }
.bar i { display:block; height:100%; background:#5fd38a; }
main { display:grid; grid-template-columns:1fr 1fr; gap:14px; padding:14px 18px; }
.card { background:var(--card); border:1px solid var(--line); border-radius:8px; padding:10px 14px; min-width:0; overflow:auto; }
.card.wide { grid-column:1 / -1; }
h2 { font-size:15px; margin:4px 0 10px; }
table { border-collapse:collapse; width:100%; font-size:13px; }
th, td { text-align:left; padding:4px 6px; border-bottom:1px solid var(--line); vertical-align:top; }
th { color:var(--mute); font-weight:600; }
.muted { color:var(--mute); } .small { font-size:12px; font-weight:normal; }
.ok { color:var(--ok); font-weight:600; } .warn { color:var(--warn); font-weight:600; } .bad { color:var(--bad); font-weight:600; }
.err { color:var(--bad); margin-left:8px; }
button { font:inherit; padding:3px 10px; border:1px solid var(--acc); background:var(--acc); color:#fff; border-radius:5px; cursor:pointer; }
button:disabled { opacity:.45; cursor:not-allowed; }
button.link { background:none; color:var(--acc); border:none; padding:0; text-decoration:underline; }
input { font:inherit; padding:3px 6px; border:1px solid var(--line); border-radius:5px; }
.row { display:flex; gap:8px; align-items:center; margin-bottom:8px; }
.ev { margin:2px 0 0 0; padding-left:16px; color:var(--mute); font-size:12px; }
.steps { display:flex; flex-wrap:wrap; align-items:center; gap:4px; margin:6px 0 10px; }
.step { border:1px solid var(--acc); color:var(--acc); border-radius:6px; padding:3px 8px; font-size:12px; background:#f0f4ff; }
.arrow { color:var(--mute); }
button.rej { background:var(--bad); border-color:var(--bad); }
.runbox button, #tasks button { margin:4px 6px 0 0; }
#tasks pre { white-space:pre-wrap; max-width:110ch; margin:4px 0; font-size:12px; }
.runbox { margin-top:10px; padding:8px 10px; border-left:4px solid var(--acc); background:#f0f4ff; border-radius:4px; }
.kb li { margin-bottom:8px; } .kb .score { color:var(--mute); font-size:12px; }
#trace { display:block; max-height:330px; overflow:auto; }
.hidden { display:none; }
#trace.hidden { display:none; }
footer { padding:0 18px 18px; }
@media (max-width: 900px) { main { grid-template-columns:1fr; } }
}

XData JS [ MimeType = application/javascript ]
{
(function () {
  "use strict";
  var BASE = location.pathname.slice(-1) === "/" ? location.pathname : location.pathname + "/";
  var nextRunAt = 0, polling = null;

  function el(tag, attrs, kids) {
    var e = document.createElement(tag);
    if (attrs) Object.keys(attrs).forEach(function (k) { if (k === "text") e.textContent = attrs[k]; else if (k === "cls") e.className = attrs[k]; else e.setAttribute(k, attrs[k]); });
    (kids || []).forEach(function (c) { if (c != null) e.appendChild(typeof c === "string" ? document.createTextNode(c) : c); });
    return e;
  }
  function td(v, cls) { return el("td", { text: v == null ? "" : String(v), cls: cls || "" }); }
  function api(path, opts) {
    return fetch(BASE + "api/" + path, opts || {}).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) { j._code = r.status; return j; });
    });
  }
  function statusCls(s) { return ({ applied: "ok", passed: "ok", quarantined: "warn", escalated: "warn", pending_review: "warn", rejected: "bad" })[s] || ""; }
  function tgt(t) { if (t == null || t === "") return ""; return typeof t === "object" ? Object.keys(t).map(function (k) { var v = t[k]; return k + "=" + (typeof v === "number" ? String(+v.toPrecision(4)) : v); }).join(" ") : String(t); }
  function sessBtn(s) { if (!s) return td(""); var c = el("td"); c.appendChild(el("button", { cls: "link", text: String(s), type: "button", "data-session": String(s) })); return c; }

  function loadStatus() {
    return api("status").then(function (s) {
      var box = document.getElementById("status"); box.textContent = "";
      if (s._code !== 200) { box.appendChild(el("span", { text: "status error " + s._code })); return; }
      var b = s.budget || {}, used = b.callsCap ? Math.min(100, Math.round(100 * b.calls / b.callsCap)) : 0;
      box.appendChild(el("span", { cls: "pill " + s.kind, text: "mode " + s.kind }));
      box.appendChild(el("span", { cls: "pill", text: "profile " + s.profile + " / " + s.model }));
      box.appendChild(el("span", { cls: "pill", text: "key " + s.key }));
      var bar = el("span", { cls: "bar" }); bar.appendChild(el("i", { style: "width:" + (100 - used) + "%" }));
      box.appendChild(el("span", { cls: "pill" }, ["budget ", bar, " " + b.callsLeft + "/" + b.callsCap + " calls, $" + b.usdLeft + " of $" + b.usdCap + " left"]));
      box.appendChild(el("span", { cls: "pill", text: "production " + (s.production && s.production.state) }));
      if (s.rights) box.appendChild(el("span", { cls: "pill", title: "role " + s.rights.roles + "; writes only inside InteropOps.Demo.Write", text: "page data access " + s.rights.dataPermission }));
      nextRunAt = Date.now() + 1000 * (s.runLimit ? s.runLimit.nextRunInSec : 0);
      updateButtons();
    });
  }
  function updateButtons() {
    var wait = Math.max(0, Math.ceil((nextRunAt - Date.now()) / 1000));
    document.querySelectorAll("button[data-run]").forEach(function (b) { b.disabled = wait > 0 || !!polling; });
    document.getElementById("runinfo").textContent = wait > 0 ? "next run in " + wait + " s" : (polling ? "run in progress..." : "one run per 30 s for all visitors");
  }

  function loadCases() {
    return api("cases").then(function (j) {
      var tb = document.querySelector("#cases tbody"); tb.textContent = "";
      (j.cases || []).forEach(function (c) {
        var d = c.latest || {}, e = c.expected || {};
        var run = el("td"); run.appendChild(el("button", { type: "button", "data-run": c.id, text: "Run" }));
        tb.appendChild(el("tr", null, [td(c.id), td((c.set === "pair" ? "specimen pair: " : "") + c.title, "muted"), td((e.action || "") + " " + tgt(e.target)),
          td(d.action ? d.action + " " + tgt(d.target) : "-"), td(d.finalStatus || "", statusCls(d.finalStatus)), td(d.source || ""),
          td(d.llmCalls != null ? d.llmCalls : ""), sessBtn(d.sessionId), run]));
      });
      updateButtons();
    });
  }

  function loadDecisions() {
    return api("decisions?limit=6").then(function (j) {
      var tb = document.querySelector("#decisions tbody"); tb.textContent = "";
      (j.decisions || []).forEach(function (d) {
        var rs = String(d.reason || ""), why = el("td", { text: rs.length > 200 ? rs.slice(0, 200) + "..." : rs, title: rs });
        if (Array.isArray(d.evidence) && d.evidence.length) { var ul = el("ul", { cls: "ev" }); d.evidence.slice(0, 2).forEach(function (x) { ul.appendChild(el("li", { text: String(x) })); }); why.appendChild(ul); }
        tb.appendChild(el("tr", null, [td(d.id), td(d.caseId), td(d.action), td(tgt(d.target)), td(d.gateResult), td(d.finalStatus, statusCls(d.finalStatus)),
          td(d.source), td(d.mode), td(d.llmCalls), why, sessBtn(d.sessionId)]));
      });
    });
  }

  function loadTrace(s) {
    var err = document.getElementById("traceerr"); err.textContent = "";
    document.getElementById("session").value = s;
    return api("trace/" + encodeURIComponent(s)).then(function (j) {
      var steps = document.getElementById("steps"), tbl = document.getElementById("trace"), tb = tbl.querySelector("tbody");
      steps.textContent = ""; tb.textContent = "";
      if (j._code !== 200) { err.textContent = j.error || ("error " + j._code); tbl.classList.add("hidden"); return; }
      (j.hosts || []).forEach(function (h, i) { if (i) steps.appendChild(el("span", { cls: "arrow", text: "\u2192" })); steps.appendChild(el("span", { cls: "step", text: h })); });
      (j.messages || []).forEach(function (m) {
        tb.appendChild(el("tr", null, [td(m.id), td(m.timeUtc), td(m.from), td(m.to), td(m.body, "muted"), td(m.type), td(m.status, m.isError ? "bad" : "")]));
      });
      tbl.classList.remove("hidden");
    });
  }

  function loadTasks() {
    return api("tasks?limit=8").then(function (j) {
      var tb = document.querySelector("#tasks tbody"); tb.textContent = "";
      document.getElementById("taskcount").textContent = "open: " + (j.openTotal != null ? j.openTotal : "?");
      (j.tasks || []).forEach(function (t) {
        var rv = el("td");
        if (t.canDecide) reviewButtons(t.id).forEach(function (b) { rv.appendChild(b); });
        var subj = el("td", null, [el("div", { text: String(t.subject || "") })]);
        if (t.message) { var det = el("details", null, [el("summary", { text: "what the gate checked / what the proposer says" }), el("pre", { cls: "small", text: String(t.message) })]); subj.appendChild(det); }
        tb.appendChild(el("tr", null, [td(t.id), subj, td(t.status, t.isComplete ? "ok" : "warn"), td(t.action), td(t.role), sessBtn(t.sessionId), rv]));
      });
    });
  }

  function kb(q) {
    var err = document.getElementById("kberr"), ol = document.getElementById("kb"); err.textContent = ""; ol.textContent = "";
    return api("kb?k=3&q=" + encodeURIComponent(q)).then(function (j) {
      if (j._code !== 200) { err.textContent = j.error || ("error " + j._code); return; }
      (j.results || []).forEach(function (r) {
        ol.appendChild(el("li", null, [el("b", { text: r.title }), " ", el("span", { cls: "score", text: "score " + Number(r.score).toFixed(3) + " - " + r.slug }), el("div", { cls: "muted small", text: String(r.body).slice(0, 220) })]));
      });
    });
  }

  function run(id) {
    var box = document.getElementById("runbox"); box.classList.remove("hidden"); box.textContent = "Starting " + id + "...";
    api("run/" + encodeURIComponent(id), { method: "POST", headers: { "X-IOA-Demo": "1" } }).then(function (j) {
      if (j._code !== 200) { box.textContent = (j.error || "error") + (j.retryAfterSec ? " (retry in " + j.retryAfterSec + " s)" : ""); if (j.retryAfterSec) nextRunAt = Date.now() + 1000 * j.retryAfterSec; updateButtons(); return; }
      nextRunAt = Date.now() + 1000 * j.nextRunInSec;
      box.textContent = "Case " + j.case + " dropped into the input folder (mode " + j.kind + "). Waiting for the agent...";
      var t0 = Date.now();
      polling = setInterval(function () {
        api("run").then(function (r) {
          var d = r.decision;
          if (d) box.textContent = "Case " + d.caseId + ": " + d.action + " " + tgt(d.target) + " -> " + d.finalStatus + " (source " + d.source + ", gate " + d.gateResult + ", LLM calls " + d.llmCalls + ", session " + d.sessionId + ")" + (r.done ? "" : " ...");
          var review = d && d.finalStatus === "pending_review" && d.canDecide;
          if (r.done || review || Date.now() - t0 > 120000) {
            clearInterval(polling); polling = null;
            if (!d) box.textContent = "No decision yet for " + j.case + " after 120 s; see the decisions table later.";
            if (review) { box.appendChild(el("div", { text: "Waiting for a human reviewer (Workflow task " + d.taskId + "):" })); reviewButtons(d.taskId).forEach(function (b) { box.appendChild(b); }); }
            refresh(); if (d && d.sessionId) loadTrace(d.sessionId);
          }
          updateButtons();
        });
      }, 2000);
      updateButtons();
    });
  }

  function reviewButtons(id) {
    return [el("button", { type: "button", "data-decide": String(id), "data-act": "approve", text: "Approve as reviewer" }),
      el("button", { type: "button", cls: "rej", "data-decide": String(id), "data-act": "reject", text: "Reject as reviewer" })];
  }

  function decide(id, act) {
    var box = document.getElementById("runbox"); box.classList.remove("hidden");
    document.querySelectorAll("button[data-decide]").forEach(function (b) { b.disabled = true; });
    box.textContent = (act === "approve" ? "Approving" : "Rejecting") + " task " + id + "...";
    api("tasks/" + encodeURIComponent(id) + "/" + act, { method: "POST", headers: { "X-IOA-Demo": "1" } }).then(function (j) {
      if (j._code !== 200) { box.textContent = (j.error || "error") + (j.retryAfterSec ? " (retry in " + j.retryAfterSec + " s)" : ""); refresh(); return; }
      box.textContent = "Task " + j.taskId + " completed: " + j.action + " by " + j.reviewer + " (case " + j.caseId + ", session " + j.sessionId + "). Waiting for the business process...";
      var t0 = Date.now(), iv = setInterval(function () {
        api("trace/" + encodeURIComponent(j.sessionId)).then(function (r) {
          var d = r.decision;
          if ((d && d.finalStatus !== "pending_review") || Date.now() - t0 > 60000) {
            clearInterval(iv);
            if (d) box.textContent = "Case " + d.caseId + ": " + j.action + " -> " + d.finalStatus + " (source " + d.source + ", LLM calls " + d.llmCalls + ", session " + d.sessionId + "): " + String(d.reason || "").slice(0, 160);
            refresh(); loadTrace(j.sessionId);
          }
        });
      }, 2000);
    });
  }

  function refresh() { return Promise.all([loadStatus(), loadCases(), loadDecisions(), loadTasks()]); }

  document.addEventListener("click", function (ev) {
    var b = ev.target.closest("button"); if (!b) return;
    if (b.getAttribute("data-run")) run(b.getAttribute("data-run"));
    else if (b.getAttribute("data-decide")) decide(b.getAttribute("data-decide"), b.getAttribute("data-act"));
    else if (b.getAttribute("data-session")) loadTrace(b.getAttribute("data-session"));
  });
  document.getElementById("traceform").addEventListener("submit", function (ev) { ev.preventDefault(); var v = document.getElementById("session").value.trim(); if (v) loadTrace(v); });
  document.getElementById("kbform").addEventListener("submit", function (ev) { ev.preventDefault(); var v = document.getElementById("kbq").value.trim(); if (v) kb(v); });
  setInterval(updateButtons, 1000);
  refresh().then(function () {
    var first = document.querySelector("#decisions button[data-session]"); if (first) loadTrace(first.getAttribute("data-session"));
  });
  kb("unit changed from mg/dL");
  document.getElementById("kbq").value = "unit changed from mg/dL";
 })();
}

}
