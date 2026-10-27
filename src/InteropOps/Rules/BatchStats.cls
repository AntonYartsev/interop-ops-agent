/// ObjectScript port of summarize() in spike-v2 generate.py: per-batch statistics computed from the received messages
/// (the spike read them precomputed from tool_cache.json).
Class InteropOps.Rules.BatchStats
{

/// pRaws: %DynamicArray of raw HL7 messages; pDTL: baseline DTL (required_fields, known_segments)
ClassMethod Summarize(pRaws As %DynamicArray, pDTL As %DynamicObject) As %DynamicObject
{
    Set tSegsSeen = {}, tPidStats = {}, tZ = {}, tReq = {}, tMsh = {}, tSamples = []
    Set tKnown = "", tIt = pDTL."known_segments".%GetIterator()
    While tIt.%GetNext(, .tS) { Set tKnown(tS) = "" }
    Set tIt = pDTL."required_fields".%GetIterator()
    While tIt.%GetNext(.tN, .tC) {
        Do tReq.%Set(tN, {"target_field": (tN), "source_field": (tC."source_field"), "format_regex": (tC."format_regex"),
            "source_non_empty": 0, "source_regex_matches": 0, "candidate_siblings": {}})
    }
    // by code: tB(" "_code, ...) (the " " prefix keeps string collation for numeric-looking codes)
    Set tOrder = 0
    Set tIt = pRaws.%GetIterator()
    While tIt.%GetNext(.tIdx, .tRaw) {
        Do:tIdx<3 tSamples.%Push($TRANSLATE(tRaw, $CHAR(13), $CHAR(10)))
        Kill tPid, tObx, tCodes
        Set tLines = $TRANSLATE(tRaw, $CHAR(10), $CHAR(13)), tMsh10 = "", tNObx = 0
        For s = 1:1:$LENGTH(tLines, $CHAR(13)) {
            Set tL = $ZSTRIP($PIECE(tLines, $CHAR(13), s), "<>W")
            Continue:tL=""
            Set tName = $PIECE(tL, "|")
            Do tSegsSeen.%Set(tName, tSegsSeen.%Get(tName) + 1)
            If '$DATA(tKnown(tName)) {
                Set tZi = tZ.%Get(tName)
                If '$ISOBJECT(tZi) Set tZi = {"count": 0, "samples": [], "field_examples": {}} Do tZ.%Set(tName, tZi)
                Set tZi.count = tZi.count + 1
            }
            If tName = "MSH" { Set tMsh10 = $PIECE(tL, "|", 10) }
            ElseIf tName = "PID" { For f = 2:1:$LENGTH(tL, "|") Set tPid(f - 1) = $PIECE(tL, "|", f) }
            ElseIf tName = "OBX" {
                Set tC3 = $PIECE(tL, "|", 4), tV = $PIECE(tL, "|", 6), tNObx = tNObx + 1
                Set tObx(tNObx) = $LISTBUILD($PIECE(tC3, "^"), $PIECE(tC3, "^", 2), $SELECT($ISVALIDNUM(tV) && (tV '= ""): +tV, 1: ""),
                    $PIECE($PIECE(tL, "|", 7), "^"), $PIECE(tL, "|", 8), $PIECE(tL, "|", 12),
                    $SELECT(($LENGTH(tC3, "^") >= 6) && ($PIECE(tC3, "^", 6) = "LN"): $PIECE(tC3, "^", 4, 6), 1: ""))
                Set tCodes(" " _ $PIECE(tC3, "^")) = ""
            }
        }
        Do tMsh.%Set(tMsh10, tMsh.%Get(tMsh10) + 1)
        // PID stats (PID-n_non_empty, PID-n_samples, in field order)
        Set f = ""
        For {
            Set f = $ORDER(tPid(f), 1, tVal)
            Quit:f=""
            Set tK = "PID-" _ f
            Do:'tPidStats.%IsDefined(tK _ "_non_empty") tPidStats.%Set(tK _ "_non_empty", 0), tPidStats.%Set(tK _ "_samples", [])
            Set tVal = $ZSTRIP(tVal, "<>W")
            If tVal '= "" {
                Do tPidStats.%Set(tK _ "_non_empty", tPidStats.%Get(tK _ "_non_empty") + 1)
                Do:tPidStats.%Get(tK _ "_samples").%Size()<3 tPidStats.%Get(tK _ "_samples").%Push(tVal)
            }
        }
        // required fields and sibling candidates
        Set tRIt = tReq.%GetIterator()
        While tRIt.%GetNext(, .tR) {
            Set tSrcN = +$PIECE(tR."source_field", "-", 2), tSv = $ZSTRIP($GET(tPid(tSrcN)), "<>W")
            If tSv '= "" {
                Set tR."source_non_empty" = tR."source_non_empty" + 1
                Set:$MATCH(tSv, tR."format_regex") tR."source_regex_matches" = tR."source_regex_matches" + 1
            } Else {
                Set f = ""
                For {
                    Set f = $ORDER(tPid(f), 1, tVal)
                    Quit:f=""
                    Set tVal = $ZSTRIP(tVal, "<>W")
                    Continue:(f=tSrcN)||(tVal="")||'$MATCH(tVal, tR."format_regex")
                    Set tCand = tR."candidate_siblings".%Get("PID-" _ f)
                    If '$ISOBJECT(tCand) Set tCand = {"non_empty": 0, "regex_matches": 0, "samples": []} Do tR."candidate_siblings".%Set("PID-" _ f, tCand)
                    Set tCand."non_empty" = tCand."non_empty" + 1, tCand."regex_matches" = tCand."regex_matches" + 1
                    Do:tCand.samples.%Size()<3 tCand.samples.%Push(tVal)
                }
            }
        }
        // OBX per code
        For o = 1:1:tNObx {
            Set tO = tObx(o), tK = " " _ $LIST(tO, 1)
            If '$DATA(tB(tK)) Set tOrder = tOrder + 1, tB(tK) = tOrder, tB(tK, "name") = $LIST(tO, 2), tByOrder(tOrder) = tK
            If $LIST(tO, 3) '= "" Set tB(tK, "v", $INCREMENT(tB(tK, "v"))) = $LIST(tO, 3)
            For tP = "units|4", "ref|5", "status|6", "alt|7" {
                Set tKey = " " _ $LIST(tO, $PIECE(tP, "|", 2))
                Continue:($PIECE(tP, "|")="alt")&&(tKey=" ")
                If '$DATA(tB(tK, $PIECE(tP, "|"), "o", tKey)) Set tB(tK, $PIECE(tP, "|"), "o", tKey) = $INCREMENT(tB(tK, $PIECE(tP, "|")))
                Set tB(tK, $PIECE(tP, "|"), "n", tKey) = $GET(tB(tK, $PIECE(tP, "|"), "n", tKey)) + 1
            }
            Set tC = ""
            For { Set tC = $ORDER(tCodes(tC)) Quit:tC=""  Set:tC'=tK tB(tK, "co", tC) = "" }
        }
    }
    Set tCodeStats = {}
    For o = 1:1:tOrder {
        Set tK = tByOrder(o), tCode = $EXTRACT(tK, 2, *), tN = +$GET(tB(tK, "v"))
        Kill tV
        Set (tSum, tMin, tMax) = ""
        For i = 1:1:tN Set x = tB(tK, "v", i), tV(x, i) = "", tSum = tSum + x
        Set tSt = {"code": (tCode), "description": (tB(tK, "name")), "count": (tN)}
        If tN {
            Set tMin = $ORDER(tV("")), tMax = $ORDER(tV(""), -1), tMean = tSum / tN
            // median: middle value(s) of the sorted list
            Set j = 0, x = "", (tM1, tM2) = ""
            For { Set x = $ORDER(tV(x)) Quit:x=""  Set i = "" For { Set i = $ORDER(tV(x, i)) Quit:i=""  Set j = j + 1 Set:j=((tN + 1) \ 2) tM1 = x Set:j=((tN \ 2) + 1) tM2 = x } }
            Set tMed = $SELECT(tN # 2: tM1, 1: (tM1 + tM2) / 2)
            Set tSq = 0
            For i = 1:1:tN Set tSq = tSq + ((tB(tK, "v", i) - tMean) ** 2)
            Do tSt.%Set("min", ..R2(tMin), "number"), tSt.%Set("max", ..R2(tMax), "number"), tSt.%Set("mean", ..R2(tMean), "number")
            Do tSt.%Set("median", ..R2(tMed), "number"), tSt.%Set("stddev", $SELECT(tN > 1: ..R2($ZSQR(tSq / (tN - 1))), 1: 0), "number")
        } Else {
            For tF = "min", "max", "mean", "median" Do tSt.%Set(tF, "", "null")
            Do tSt.%Set("stddev", 0, "number")
        }
        For tP = "units", "ref_ranges|ref", "obx11_status|status", "alt_codes|alt" {
            Set tSrc = $PIECE(tP, "|", $SELECT($PIECE(tP, "|", 2) = "": 1, 1: 2)), tObj = {}
            Kill tByO
            Set x = ""
            For { Set x = $ORDER(tB(tK, tSrc, "o", x), 1, tI) Quit:x=""  Set tByO(tI) = x }
            Set i = ""
            For { Set i = $ORDER(tByO(i), 1, x) Quit:i=""  Do tObj.%Set($EXTRACT(x, 2, *), tB(tK, tSrc, "n", x)) }
            Do tSt.%Set($PIECE(tP, "|"), tObj)
            Do:$PIECE(tP, "|")="ref_ranges" tSt.%Set("co_occurring_codes", ..CoCodes(.tB, tK))
        }
        Do tCodeStats.%Set(tCode, tSt)
    }
    // reorder keys to the generate.py order
    Set tOut = {}
    Set tIt = tCodeStats.%GetIterator()
    While tIt.%GetNext(.tCode, .tSt) {
        Do tOut.%Set(tCode, {"code": (tSt.code), "description": (tSt.description), "count": (tSt.count), "min": (tSt.min), "max": (tSt.max),
            "mean": (tSt.mean), "median": (tSt.median), "stddev": (tSt.stddev), "units": (tSt.units), "ref_ranges": (tSt."ref_ranges"),
            "co_occurring_codes": (tSt."co_occurring_codes"), "obx11_status": (tSt."obx11_status"), "alt_codes": (tSt."alt_codes")})
        For tF = "min", "max", "mean", "median" Do:tSt.%GetTypeOf(tF)="null" tOut.%Get(tCode).%Set(tF, "", "null")
    }
    Set tDups = {}, tUnique = 0
    Set tIt = tMsh.%GetIterator()
    While tIt.%GetNext(.tK, .tN) { Set tUnique = tUnique + 1 Do:tN>1 tDups.%Set(tK, tN) }
    Return {"total_messages": (pRaws.%Size()), "segments_seen": (tSegsSeen), "pid_stats": (tPidStats), "required_field_stats": (tReq),
        "non_standard_segments": (tZ), "code_stats": (tOut), "msh10_stats": {"unique": (tUnique), "duplicates": (tDups)}, "sample_messages": (tSamples)}
}

ClassMethod CoCodes(ByRef pB, pK As %String) As %DynamicArray [ Private ]
{
    Set tA = [], x = ""
    For { Set x = $ORDER(pB(pK, "co", x)) Quit:x=""  Do tA.%Push($EXTRACT(x, 2, *)) }
    Return tA
}

/// round to 2 decimals, as a number
ClassMethod R2(x) As %Numeric [ Private ]
{
    Return +$FNUMBER(x, "", 2)
}

ClassMethod Diff(pA, pB, pPath As %String) As %String
{
    If $ISOBJECT(pA) '= $ISOBJECT(pB) Return pPath _ " type; "
    If '$ISOBJECT(pA) {
        If $ISVALIDNUM(pA) && $ISVALIDNUM(pB) && (pA '= "") && (pB '= "") Return $SELECT($ZABS(pA - pB) <= 0.011: "", 1: pPath _ " " _ pA _ "<>" _ pB _ "; ")
        Return $SELECT(##class(InteropOps.Util.Ids).NormMSH10(pA) = pB: "", 1: pPath _ " " _ pA _ "<>" _ pB _ "; ")
    }
    Set tOut = "", tKeys = ""
    Set tIt = pA.%GetIterator()
    While tIt.%GetNext(.k, .v) { Set tKeys(" " _ ##class(InteropOps.Util.Ids).NormMSH10(k)) = $LB(k) }
    Set tIt = pB.%GetIterator()
    While tIt.%GetNext(.k, .v) { Set $LIST(tKeys(" " _ k), 2) = k }
    Set k = ""
    For {
        Set k = $ORDER(tKeys(k), 1, tL)
        Quit:k=""
        If '$LISTDATA(tL, 1) || '$LISTDATA(tL, 2) { Set tOut = tOut _ pPath _ "/" _ k _ " missing; " Continue }
        Set tOut = tOut _ ..Diff(pA.%Get($LIST(tL, 1)), pB.%Get($LIST(tL, 2)), pPath _ "/" _ k)
    }
    Return tOut
}

}
