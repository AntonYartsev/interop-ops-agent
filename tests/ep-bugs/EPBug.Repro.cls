/// Embedded Python bug repro (IRIS 2026.3.0AI build 154). Load into a scratch namespace (USER), not into IRISAPP.
/// Run tests/ep-bugs/repro.sh: each case runs in its own iris session (a clean process).
Class EPBug.Repro Extends %RegisteredObject
{

/// Case 1: argument with an unpaired UTF-16 surrogate, e.g. "a"_$c(55357)_"b" -> SIGSEGV of the process
ClassMethod Len(s As %String) As %Integer [ Language = python ]
{
    return len(s)
}

/// Case 2: returns a Python str with an unpaired surrogate -> ObjectScript gets "-31", no error
ClassMethod RetLone() As %String [ Language = python ]
{
    return "a\ud83db"
}

/// Case 3: returns a Python int outside int64 -> ObjectScript gets -1, no error
ClassMethod Pow2(n As %Integer) [ Language = python ]
{
    return 2**n
}

/// Case 4: a ByRef argument in the signature -> TypeError "descriptor ... doesn't apply to a 'int' object", even for a value argument
ClassMethod TwoRef(ByRef a, b) [ Language = python ]
{
    return f"{a}|{b}"
}

}
