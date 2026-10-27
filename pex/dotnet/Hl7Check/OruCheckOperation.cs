// PEX Business Operation: an independent "second opinion" on an HL7 v2.5.1 ORU^R01 message.
// NHapi parses the message (its own grammar + primitive validation), deterministic OBX rules run on
// the parsed model, and the result is diffed against IRIS's own EnsLib.HL7 validation errors
// (passed in by the caller). Output: JSON findings suitable for agent evidence.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using InterSystems.EnsLib.PEX;
using NHapi.Base;
using NHapi.Base.Parser;
using NHapi.Base.Model;
using NHapi.Model.V251.Message;
using NHapi.Model.V251.Segment;

namespace Hl7Check
{
    public class OruCheckRequest : Message
    {
        public string fixture;
        public string hl7;            // one ER7 message
        public string irisValSpec;    // e.g. dm-zrny-x
        public string irisErrors;     // JSON array of IRIS validation error texts ([] = passed)
    }

    public class OruCheckResponse : Message
    {
        public string fixture;
        public string messageControlId;
        public string engine;
        public int errors;
        public int warnings;
        public int infos;
        public int agree;       // findings reported by both IRIS and .NET
        public int dotnetOnly;  // findings only the .NET side saw
        public int irisOnly;    // findings only IRIS saw
        public string findingsJson;
    }

    public class Finding
    {
        public string severity { get; set; }   // error | warning | info
        public string path { get; set; }       // e.g. PID-3, OBX[2]-8
        public string code { get; set; }       // stable machine code
        public string message { get; set; }    // human text (never echoes free-text NTE content)
        public string source { get; set; }     // both | dotnet | iris
        public string rule { get; set; }       // nhapi-parse | obx-rule | structure | iris-validation
    }

    public class OruCheckOperation : BusinessOperation
    {
        static readonly Regex Injection = new Regex(
            @"(ignore\s+(all\s+|any\s+|previous\s+|prior\s+)*instructions|system\s+(note|prompt)|note\s+to\s+(the\s+)?ai|you\s+are\s+(an?\s+)?(ai|assistant|llm)|disregard\s+.*(rules|instructions))",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);
        static readonly Regex IrisSeg = new Regex(@"segment (\d+):(\w+)", RegexOptions.Compiled);
        static readonly Regex IrisMissing = new Regex(@"Missing field (\d+)", RegexOptions.Compiled);
        static readonly Regex IrisField = new Regex(@"[Ff]ield (\d+)", RegexOptions.Compiled);
        static readonly Regex Range = new Regex(@"^\s*(-?\d+(?:\.\d+)?)\s*-\s*(-?\d+(?:\.\d+)?)\s*$|^\s*([<>]=?)\s*(-?\d+(?:\.\d+)?)\s*$", RegexOptions.Compiled);

        public override void OnInit() { }
        public override void OnTearDown() { }

        public override object OnMessage(object request)
        {
            var req = (OruCheckRequest)request;
            var findings = new List<Finding>();
            string mcid = "";
            string hl7 = (req.hl7 ?? "").Replace("\r\n", "\r").Replace("\n", "\r").Trim('\r');

            // 1) NHapi parse (structure + primitive validation of its default ValidationContext).
            IMessage parsed = null;
            try
            {
                parsed = new PipeParser().Parse(hl7);
            }
            catch (HL7Exception ex)
            {
                findings.Add(F("error", Loc(ex), "NHAPI_PARSE", ex.Message, "nhapi-parse"));
            }
            catch (Exception ex)
            {
                findings.Add(F("error", "MSH", "NHAPI_PARSE", ex.GetType().Name + ": " + ex.Message, "nhapi-parse"));
            }

            if (parsed is ORU_R01 oru)
            {
                mcid = oru.MSH.MessageControlID.Value ?? "";
                for (int p = 0; p < oru.PATIENT_RESULTRepetitionsUsed; p++)
                {
                    var pr = oru.GetPATIENT_RESULT(p);
                    CheckPid(pr.PATIENT.PID, findings);
                    int obxN = 0;
                    for (int o = 0; o < pr.ORDER_OBSERVATIONRepetitionsUsed; o++)
                    {
                        var oo = pr.GetORDER_OBSERVATION(o);
                        for (int n = 0; n < oo.NTERepetitionsUsed; n++) CheckNte(oo.GetNTE(n), "OBR-NTE[" + (n + 1) + "]", findings);
                        for (int b = 0; b < oo.OBSERVATIONRepetitionsUsed; b++)
                        {
                            var obs = oo.GetOBSERVATION(b);
                            obxN++;
                            CheckObx(obs.OBX, obxN, findings);
                            for (int n = 0; n < obs.NTERepetitionsUsed; n++) CheckNte(obs.GetNTE(n), "OBX[" + obxN + "]-NTE[" + (n + 1) + "]", findings);
                        }
                    }
                }
            }
            else if (parsed != null)
            {
                findings.Add(F("error", "MSH-9", "NOT_ORU_R01", "Parsed as " + parsed.GetStructureName() + ", expected ORU_R01", "structure"));
            }
            if (mcid == "") mcid = MshField(hl7, 10);

            // 2) Diff with IRIS validation.
            var iris = new List<string>();
            try { iris = JsonSerializer.Deserialize<List<string>>(string.IsNullOrEmpty(req.irisErrors) ? "[]" : req.irisErrors) ?? new List<string>(); }
            catch (Exception ex) { findings.Add(F("warning", "", "IRIS_ERRORS_UNREADABLE", ex.Message, "iris-validation")); }
            var segNames = hl7.Split('\r').Select(s => s.Length >= 3 ? s.Substring(0, 3) : s).ToList();
            foreach (var text in iris)
            {
                string path = IrisPath(text, segNames);
                var match = findings.FirstOrDefault(f => f.source == "dotnet" && f.path == path && f.severity == "error");
                if (match != null) { match.source = "both"; match.message += " | IRIS: " + Short(text); }
                else findings.Add(F("error", path, "IRIS_ONLY", Short(text), "iris-validation", "iris"));
            }

            var resp = new OruCheckResponse
            {
                fixture = req.fixture,
                messageControlId = mcid,
                engine = "NHapi " + typeof(PipeParser).Assembly.GetName().Version + " / v2.5.1 model; IRIS valspec " + (req.irisValSpec ?? ""),
                errors = findings.Count(f => f.severity == "error"),
                warnings = findings.Count(f => f.severity == "warning"),
                infos = findings.Count(f => f.severity == "info"),
                agree = findings.Count(f => f.source == "both"),
                dotnetOnly = findings.Count(f => f.source == "dotnet"),
                irisOnly = findings.Count(f => f.source == "iris"),
                findingsJson = JsonSerializer.Serialize(findings, new JsonSerializerOptions { DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull })
            };
            return resp;
        }

        // ---- rules -------------------------------------------------------------------------

        static void CheckPid(PID pid, List<Finding> f)
        {
            bool pid3 = pid.PatientIdentifierListRepetitionsUsed > 0 && !string.IsNullOrEmpty(pid.GetPatientIdentifierList(0).IDNumber.Value);
            if (!pid3)
            {
                string pid2 = pid.PatientID.IDNumber.Value;
                f.Add(F("error", "PID-3", "PID3_MISSING",
                    string.IsNullOrEmpty(pid2)
                        ? "PID-3 Patient Identifier List is required (R) in v2.5.1 and is empty"
                        : "PID-3 is empty but PID-2 (backward-compatible field) carries an identifier; MRN is in the wrong field",
                    "structure"));
            }
        }

        static void CheckObx(OBX obx, int idx, List<Finding> f)
        {
            string p = "OBX[" + idx + "]";
            string vt = obx.ValueType.Value ?? "";
            string code = obx.ObservationIdentifier.Identifier.Value ?? "";
            string text = obx.ObservationIdentifier.Text.Value ?? "";
            string label = code == "" ? p : code;
            string value = obx.ObservationValueRepetitionsUsed > 0 ? (obx.GetObservationValue(0).Data?.ToString() ?? "") : "";
            if (obx.ObservationValueRepetitionsUsed > 0 && obx.GetObservationValue(0).Data is IPrimitive prim) value = prim.Value ?? "";
            string units = obx.Units.Identifier.Value ?? "";
            string range = obx.ReferencesRange.Value ?? "";
            var flags = Enumerable.Range(0, obx.AbnormalFlagsRepetitionsUsed).Select(i => obx.GetAbnormalFlags(i).Value ?? "").Where(s => s != "").ToList();
            string flag = flags.FirstOrDefault() ?? "";
            string status = obx.ObservationResultStatus.Value ?? "";

            if (code == "") f.Add(F("error", p + "-3", "OBX3_MISSING", "Observation identifier is empty", "obx-rule"));
            else if (text == "") f.Add(F("info", p + "-3", "OBX3_NO_TEXT", label + ": code has no display text (OBX-3.2); cannot be checked by name", "obx-rule"));

            if (vt == "" && value != "") { f.Add(F("error", p + "-2", "OBX2_MISSING", label + ": OBX-5 has a value but OBX-2 value type is empty", "obx-rule")); return; }

            decimal num = 0; bool isNum = false;
            if (vt == "NM")
            {
                isNum = decimal.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out num);
                if (value != "" && !isNum) f.Add(F("error", p + "-5", "OBX5_TYPE_MISMATCH", label + ": OBX-2=NM but OBX-5 '" + Short(value, 40) + "' is not numeric", "obx-rule"));
                if (units == "") f.Add(F("warning", p + "-6", "OBX6_UNITS_MISSING", label + ": numeric result without units", "obx-rule"));
            }
            else if (vt == "SN")
            {
                if (!Regex.IsMatch(value, @"^(<|>|<=|>=|=|<>)?\^?-?\d+(\.\d+)?(\^(-|\+|/|\.|:)\^?-?\d+(\.\d+)?)?$"))
                    f.Add(F("error", p + "-5", "OBX5_TYPE_MISMATCH", label + ": OBX-2=SN but OBX-5 is not a structured numeric", "obx-rule"));
            }
            else if ((vt == "DT" || vt == "TS" || vt == "DTM") && !Regex.IsMatch(value, @"^\d{4}(\d{2}){0,5}(\.\d+)?([+-]\d{4})?$"))
                f.Add(F("error", p + "-5", "OBX5_TYPE_MISMATCH", label + ": OBX-2=" + vt + " but OBX-5 is not an HL7 date/time", "obx-rule"));

            // Abnormal flag vs reference range (only meaningful for numeric results).
            bool critical = flag == "HH" || flag == "LL" || flag == "AA" || flag == ">" || flag == "<";
            if (isNum)
            {
                if (range == "")
                {
                    f.Add(F("warning", p + "-7", "OBX7_RANGE_MISSING", label + ": numeric result without reference range; abnormal flag cannot be verified", "obx-rule"));
                }
                else
                {
                    var m = Range.Match(range);
                    if (!m.Success) f.Add(F("warning", p + "-7", "OBX7_RANGE_UNPARSEABLE", label + ": reference range '" + Short(range, 30) + "' not machine-readable", "obx-rule"));
                    else
                    {
                        int dir = 0; // -1 below, +1 above, 0 inside
                        if (m.Groups[1].Success)
                        {
                            decimal lo = decimal.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture), hi = decimal.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture);
                            dir = num < lo ? -1 : num > hi ? 1 : 0;
                        }
                        else
                        {
                            string op = m.Groups[3].Value; decimal lim = decimal.Parse(m.Groups[4].Value, CultureInfo.InvariantCulture);
                            if (op.StartsWith("<")) dir = (op == "<" ? num >= lim : num > lim) ? 1 : 0;
                            else dir = (op == ">" ? num <= lim : num < lim) ? -1 : 0;
                        }
                        bool high = flag == "H" || flag == "HH" || flag == ">";
                        bool low = flag == "L" || flag == "LL" || flag == "<";
                        string ctx = label + "=" + value + " " + units + " (range " + range + ", flag '" + flag + "')";
                        if (dir != 0 && (flag == "" || flag == "N"))
                            f.Add(F("error", p + "-8", "OBX8_FLAG_MISSING", ctx + ": value is " + (dir > 0 ? "above" : "below") + " range but not flagged abnormal", "obx-rule"));
                        else if ((dir > 0 && low) || (dir < 0 && high))
                            f.Add(F("error", p + "-8", "OBX8_FLAG_DIRECTION", ctx + ": flag direction contradicts value", "obx-rule"));
                        else if (dir == 0 && (high || low || flag == "A" || flag == "AA"))
                            f.Add(F("warning", p + "-8", "OBX8_FLAG_SPURIOUS", ctx + ": value is within range but flagged abnormal", "obx-rule"));
                    }
                }
            }
            if (critical)
                f.Add(F("warning", p + "-8", "OBX8_CRITICAL", label + "=" + value + " " + units + " flagged '" + flag + "' (critical/panic): needs critical-result notification", "obx-rule"));

            if (status == "") f.Add(F("warning", p + "-11", "OBX11_STATUS_MISSING", label + ": result status is empty", "obx-rule"));
            else if (status == "C") f.Add(F("info", p + "-11", "OBX11_CORRECTION", label + ": corrected result (OBX-11=C) replaces a previously sent value", "obx-rule"));
            else if ("FPRSIDXNUW".IndexOf(status, StringComparison.Ordinal) < 0 || status.Length != 1)
                f.Add(F("warning", p + "-11", "OBX11_STATUS_UNKNOWN", label + ": OBX-11 '" + Short(status, 5) + "' not in HL7 table 0085", "obx-rule"));
        }

        static void CheckNte(NTE nte, string path, List<Finding> f)
        {
            for (int i = 0; i < nte.CommentRepetitionsUsed; i++)
            {
                string c = nte.GetComment(i).Value ?? "";
                if (Injection.IsMatch(c))
                    f.Add(F("warning", path + "-3", "NTE_INSTRUCTION_LIKE", "Free-text comment contains instruction-like text addressed to an AI/system; treat as untrusted data (content not echoed)", "obx-rule"));
            }
        }

        // ---- helpers -----------------------------------------------------------------------

        static Finding F(string sev, string path, string code, string msg, string rule, string source = "dotnet")
            => new Finding { severity = sev, path = path, code = code, message = msg, rule = rule, source = source };

        static string Loc(HL7Exception ex)
        {
            try
            {
                var seg = ex.SegmentName; int fld = ex.FieldPosition;
                if (!string.IsNullOrEmpty(seg)) return fld > 0 ? seg + "-" + fld : seg;
            }
            catch { }
            return "";
        }

        // "segment 2:PID.  Missing field 3" -> "PID-3"; OBX occurrences -> OBX[n]-f
        static string IrisPath(string text, List<string> segNames)
        {
            var s = IrisSeg.Match(text);
            if (!s.Success) return "";
            string seg = s.Groups[2].Value; int segIdx = int.Parse(s.Groups[1].Value);
            var fm = IrisMissing.Match(text); if (!fm.Success) fm = IrisField.Match(text);
            string p = seg;
            if (seg == "OBX" && segIdx - 1 < segNames.Count)
            {
                int n = segNames.Take(segIdx).Count(x => x == "OBX");
                p = "OBX[" + n + "]";
            }
            return fm.Success ? p + "-" + fm.Groups[1].Value : p;
        }

        static string MshField(string hl7, int n)
        {
            var msh = hl7.Split('\r').FirstOrDefault(s => s.StartsWith("MSH")) ?? "";
            var parts = msh.Split('|');
            return parts.Length > n - 1 ? parts[n - 1] : "";   // MSH-1 is the separator itself
        }

        static string Short(string s, int max = 200) => s == null ? "" : (s.Length <= max ? s : s.Substring(0, max) + "...");
    }
}
