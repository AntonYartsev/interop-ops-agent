# .NET PEX: Hl7Check, an NHapi ORU^R01 second-opinion operation

A C# PEX Business Operation that runs in the main production as agent evidence:
`PexHl7CheckBP` (`PexHl7.CheckProcess`) -> `PexHl7Check` (`EnsLib.PEX.BusinessOperation`), one call per batch.
It runs in the evidence step of `IOA.Process.Message`, before the agent; if .NET is unavailable, the step logs a warning and the case continues.

The main [`Dockerfile`](../Dockerfile) builds it: stage `hl7build` (dotnet/sdk:8.0) publishes `dotnet/Hl7Check/` against
the IRIS .NET SDK of the image, stage `dotnetrt` (dotnet/runtime:8.0) supplies the runtime. `iris.script` imports
`src/PexHl7/`. Without the .NET runtime the step soft-fails to IRIS-only findings.

| | |
|---|---|
| Base image | `irishealth-aihub:2027.1.0AI.109.0` (`ARG IMAGE` in the main [`Dockerfile`](../Dockerfile)) |
| .NET | `mcr.microsoft.com/dotnet/runtime:8.0` (linux-arm64) copied into `/usr/share/dotnet`; DLLs built in `mcr.microsoft.com/dotnet/sdk:8.0` |
| IRIS .NET SDK | `/usr/irissys/dev/dotnet/bin/{net8.0,net9.0,net10.0}/` (`InterSystems.Data.GatewayArm`, `IRISClient.dll`, `InterSystems.Data.Utils.dll`) |

## Variant choice
The NHapi variant, not Firely. `grep -rniE 'fhir|sda3|HS\.FHIR' src` in the main repo finds 0 files. The production
maps HL7 into its own canonical model (Rules/LabToCanonical, Msg/CaseRequest, In/CaseFile), so there is no FHIR
Observation/Bundle on the message path to validate. No UCUM checks here, because `src/InteropOps/Py/Ucum.cls` covers units.

## Pieces
- `dotnet/Hl7Check/OruCheckOperation.cs` is the C# PEX BO `Hl7Check.OruCheckOperation`. It uses NHapi 3.2.x
  (`nhapi.model.v251` 3.2.4 and `nhapi.base` 3.2.3) to parse ORU^R01, runs the OBX rules, and diffs the result
  against the IRIS validation errors that the BP passes in.
  - Rules: PID-3 missing; OBX-2 missing; OBX-5 vs OBX-2 value type (NM, SN, DT/TS/DTM); OBX-6 units missing;
    OBX-7 range missing or unparseable.
  - OBX-8 flag vs range: missing, wrong direction, spurious, or critical (HH/LL/AA).
  - OBX-11 status; NTE text that reads like an instruction (the content is not echoed).
- `src/PexHl7/CheckProcess.cls` is the BP (`PexHl7CheckBP`). It runs
  `EnsLib.HL7.Util.Validator.Validate(msg,"dm-zrny-x")`, sends hl7 plus irisErrors to the BO as an
  `EnsLib.PEX.Message`, and maps the reply into a `PexHl7.CheckResponse`.
- `src/PexHl7/Driver.cls` provides `RunFixture(file,max)`. It splits a fixture batch and sends each message via
  `EnsLib.Testing.Service`, so every message gets a Visual Trace session.
- The finding format (`FindingsJson`) is a JSON array:
  `{"severity","path","code","message","source":"both|dotnet|iris","rule"}`.

## Evidence (2026-10-27, separate test stack, 30 msgs per fixture, ~0.3 s per fixture)
| Fixture | IRIS invalid | Findings | Source |
|---|---|---|---|
| C10-mrn-pid2 | 30/30 | `PID3_MISSING` error x30, PID-3 | both (agree) |
| C11-critical-k | 0 | `OBX8_CRITICAL` warning, OBX[3]-8, "K=6.8 mmol/L flagged 'HH'" (MSG015) | dotnet only |
| C09-unknown-code-q77 | 0 | `OBX3_NO_TEXT` info, plus `OBX6_UNITS_MISSING` and `OBX7_RANGE_MISSING` warnings, x30 each, OBX[6] | dotnet only |
| C08-prompt-injection-nte | 0 | `NTE_INSTRUCTION_LIKE` and `OBX7_RANGE_MISSING` warnings x30 | dotnet only |
| C01-new-code-sod (control) | 0 | none | |

## Cost of the dependencies
- The .NET runtime layer is +78.8 MB. The image layer `/home/irisowner/pex/hl7check` is 4.32 MB.
- The `dotnet publish` step, including the NuGet restore, takes 5.9 s. NuGet restore needs network access at build time.
- Runtime RAM: about 420 MiB for a container with a production and the gateway running (test stack).
- Everything in `%gatewayExtraClasspaths`: InterSystems.Data.Utils.dll (from IRIS), Hl7Check.dll, NHapi.Base.dll,
  NHapi.Model.V251.dll, System.Configuration.ConfigurationManager.dll, System.Diagnostics.EventLog.dll,
  System.Security.Cryptography.ProtectedData.dll.

## Gotchas found
1. **No .NET runtime in the base image.** `GatewayArm` is a framework-dependent apphost, so you must add a .NET 8 runtime and set `DOTNET_ROOT`.
2. **`Class not found: <user class>`**: the gateway loads the user DLL but does **not** preload `InterSystems.Data.Utils.dll`,
   which holds the PEX base types. The error names the user class, not the missing assembly.
   **Fix:** list `/usr/irissys/dev/dotnet/bin/net8.0/InterSystems.Data.Utils.dll` first in `%gatewayExtraClasspaths`.
3. The default gateway config is `%DotNet Server` `DotNetVersion=N6.0`, even though only net8/9/10 binaries ship. It still works: IRIS starts the `net8.0` `GatewayArm` (tested with both N6.0 and N8.0), so no cpf change is needed.
4. `EnsLib.Testing.Service` needs `TestingEnabled="true"` on the production. Without it you get `ErrBusinessDispatchNameNotRegistered`.
5. If the BO job dies, a synchronous `SendTestRequest` waits forever. Check `Ens_Util.Log` instead of waiting.
6. IRIS validation `f` and `t` (code tables) flag every local `L` coding system against table 396, which is noise. That is why `dm-zrny-x` is used:
   it gives required fields, repeats and types, and reports every error. `dm-z` alone does not catch C10.
7. `EnsLib.Testing.Service.SendTestRequest` needs an `Ens.Request`, so a wrapper `PexHl7.CheckRequest` carries the HL7 text.
8. NHapi pulls in System.Configuration.ConfigurationManager and its dependencies. Use `publish` with `CopyLocalLockFileAssemblies` and list each DLL in the
   classpaths. `runtimes/win` can be dropped.
