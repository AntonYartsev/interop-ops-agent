/// Self-test for InteropOps.Py.Ucum (Embedded Python). Run: do ##class(InteropOps.Py.UcumTest).Run() -> writes UCUM_TEST=PASS|FAIL
/// Data: unit pairs of case C04 (GLU mg/dL in the feed, lookup expected_unit mmol/L; NA/K mmol/L; CREAT umol/L), one
/// non-equivalent pair, and OBX 1 of C04-MSG001 (cases/C04-glu-mgdl.hl7, synthetic).
Class InteropOps.Py.UcumTest
{

ClassMethod Run() As %Boolean
{
    Set tFail = ""
    Try {
        Set U = "InteropOps.Py.Ucum"
        // C04: GLU mg/dL -> mmol/L is analyte-dependent; lookup convention 0.0555556, molar mass gives 0.0555074
        Set r = {}.%FromJSON($CLASSMETHOD(U, "Compare", "mg/dL", "mmol/L", "GLU"))
        If '(r.convertible && r."analyte_dependent" && (r.basis = "lab_convention") && ($ZABS(r.factor - 0.0555556) < 1E-9) && ($ZABS(r."factor_molar_mass" - 0.0555074) < 1E-6)) Set tFail = tFail_" glu_factor"
        // same pair without analyte: refused (needs molar mass)
        Set r = {}.%FromJSON($CLASSMETHOD(U, "Compare", "mg/dL", "mmol/L", ""))
        If '('r.convertible && r."analyte_dependent" && (r.factor = "")) Set tFail = tFail_" glu_no_analyte"
        // synonyms / case
        Set r = {}.%FromJSON($CLASSMETHOD(U, "Compare", "mg/dl", "mg/dL", "GLU"))
        If '(r."same_unit" && (r.factor = 1)) Set tFail = tFail_" mgdl_synonym"
        Set r = {}.%FromJSON($CLASSMETHOD(U, "Compare", "mmol/l", "mmol/L", "NA"))
        If 'r."same_unit" Set tFail = tFail_" mmoll_synonym"
        Set r = {}.%FromJSON($CLASSMETHOD(U, "Compare", $CHAR(181)_"mol/L", "umol/L", "CREAT"))
        If 'r."same_unit" Set tFail = tFail_" micro_sign"
        Set r = {}.%FromJSON($CLASSMETHOD(U, "Normalize", "mg/dl"))
        If '(r.known && (r.normalized = "mg/dL") && ($ZABS(r."factor_to_base" - 0.01) < 1E-12)) Set tFail = tFail_" normalize"
        // prefix-only scale factor
        Set r = {}.%FromJSON($CLASSMETHOD(U, "Compare", "mg/dL", "g/L", ""))
        If '(r.convertible && 'r."same_unit" && 'r."analyte_dependent" && ($ZABS(r.factor - 0.01) < 1E-12)) Set tFail = tFail_" prefix_scale"
        // non-equivalent pair: mass concentration vs enzyme activity
        Set r = {}.%FromJSON($CLASSMETHOD(U, "Compare", "mg/dL", "U/L", "GLU"))
        If '('r.convertible && 'r."same_unit" && 'r."analyte_dependent" && (r.factor = "")) Set tFail = tFail_" non_equivalent"
        // OBX 1 of C04-MSG001, default delimiters and delimiters from MSH
        Set tObx = "OBX|1|NM|GLU^Glucose^L||99|mg/dL|70-105|N|||F"
        Set tMsh = "MSH|^~\&|LAB_LIS|REGIONAL_LAB|HOSP_EHR|MAIN_HOSP|20261025080000||ORU^R01^ORU_R01|C04-MSG001|P|2.5.1"
        For tDelims = "", tMsh, "^~\&" {
            Set o = {}.%FromJSON($CLASSMETHOD(U, "ParseOBX", tObx, tDelims))
            Set tOk = (o.error = "") && (o."set_id" = "1") && (o."value_type" = "NM") && (o.code.id = "GLU") && (o.code.text = "Glucose") && (o.code.system = "L")
            Set tOk = tOk && (o.value = "99") && (o."value_num" = 99) && (o.units.id = "mg/dL") && (o."ref_range".low = 70) && (o."ref_range".high = 105)
            Set tOk = tOk && (o."abnormal_flags".%Get(0) = "N") && (o.status = "F") && (o.delimiters = "|^~\&")
            If 'tOk Set tFail = tFail_" obx["_tDelims_"]"
        }
        Set o = {}.%FromJSON($CLASSMETHOD(U, "ParseOBX", "PID|1", ""))
        If o.error = "" Set tFail = tFail_" obx_not_obx"
    } Catch e {
        Set tFail = tFail_" error:"_e.DisplayString()
    }
    Write "UCUM_TEST=", $SELECT(tFail = "": "PASS", 1: "FAIL"_tFail), !
    Return (tFail = "")
}

}
