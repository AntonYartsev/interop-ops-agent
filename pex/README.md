# PEX spike (stage 1): .NET 8 Business Operation on IRIS for Health EAP 154 arm64

Status: **it works.** A BPL calls a C# PEX Business Operation through the `%DotNet Server`
External Language Server and gets a response back (round-trip verified on 2026-10-27).

This is a separate compose project (`ioa-pex`). It does not touch the main `interop-ops-agent` stack.

| | |
|---|---|
| Base image | `irishealth-aihub:2026.3.0AI.154.0` (aarch64, Ubuntu 24.04) |
| Container | `ioa-pex-iris-1` |
| Ports | `127.0.0.1:51372` → superserver, `127.0.0.1:52373` → web/portal |
| Namespace | `PEX` (DBs `PEX_DATA` / `PEX_CODE`, Interop enabled) |
| .NET | `mcr.microsoft.com/dotnet/runtime:8.0` (linux-arm64) copied into `/usr/share/dotnet`; DLL built in `mcr.microsoft.com/dotnet/sdk:8.0` |
| IRIS .NET SDK | `/usr/irissys/dev/dotnet/bin/{net8.0,net9.0,net10.0}/` (`InterSystems.Data.GatewayArm`, `IRISClient.dll`, `InterSystems.Data.Utils.dll`) |

## Layout
- `dotnet/PexDemo/`: `EchoOperation : InterSystems.EnsLib.PEX.BusinessOperation`, plus `EchoRequest` / `EchoResponse : Message`. It compiles against the image's own net8.0 SDK DLLs (`-p:IrisSdk=...`).
- `src/PexDemo/Production.cls`: production with `PexEchoBPL` (BPL) and `PexEcho` (`EnsLib.PEX.BusinessOperation`). `TestingEnabled="true"`.
- `src/PexDemo/EchoBPL.cls`: takes `Ens.StringRequest`, sends `EnsLib.PEX.Message` (`%classname=PexDemo.EchoRequest`, `%jsonObject.text`) synchronously, and returns `Ens.StringResponse`.
- `Dockerfile`, `docker-compose.yml`, `merge.cpf`, `iris.script`: build the image and set up the namespace and classes.

## Run
```sh
cd pex
docker compose -p ioa-pex up -d --build
docker exec -i ioa-pex-iris-1 iris session IRIS -U PEX <<'X'
set sc=##class(Ens.Director).StartProduction("PexDemo.Production")
set req=##class(Ens.StringRequest).%New(),req.StringValue="hello PEX"
set sc=##class(EnsLib.Testing.Service).SendTestRequest("PexEchoBPL",req,.resp,.sid,1)
write resp.StringValue,!
X
docker compose -p ioa-pex stop
```
To see the session in Visual Trace, open the portal at http://127.0.0.1:52373, go to namespace PEX, then Interoperability → Messages.

## Evidence (session 7)
```
send: 1  ms=175.5
RESPONSE: echo:hello PEX | .NET 8.0.33 Arm64
HDR 7  EnsLib.Testing.Service -> EnsLib.Testing.Process EnsLib.Testing.Request type=1 status=9
HDR 8  EnsLib.Testing.Process -> PexEchoBPL             Ens.StringRequest       type=1 status=9
HDR 9  PexEchoBPL             -> PexEcho                EnsLib.PEX.Message      type=1 status=9
HDR 10 PexEcho                -> PexEchoBPL             EnsLib.PEX.Message      type=2 status=9
HDR 11 PexEchoBPL             -> EnsLib.Testing.Process Ens.StringResponse      type=2 status=9
HDR 12 EnsLib.Testing.Process -> EnsLib.Testing.Service Ens.StringResponse      type=2 status=9
BODY9  PexDemo.EchoRequest  {"text":"hello PEX"}
BODY10 PexDemo.EchoResponse {"reply":"echo:hello PEX","runtime":".NET 8.0.33 Arm64"}
gateway process: /usr/irissys/dev/dotnet/bin/net8.0/InterSystems.Data.GatewayArm 53372 ... %DotNet Server
```
Status 9 means Completed. A second run (session 14) took 95 ms.

## Gotchas found
1. **No .NET runtime in the base image.** `GatewayArm` is a framework-dependent apphost, so you must add a .NET 8 runtime and set `DOTNET_ROOT`.
2. **`Class not found: PexDemo+EchoOperation`**: the exact error is
   `<GATEWAY> System.Exception InterSystems.Data.IRISClient.Gateway.Gateway.loadClass(String className) Class not found: PexDemo+EchoOperation`.
   The gateway does load `PexDemo.dll` (its log shows `Loading Assembly: /home/irisowner/pex/PexDemo.dll`), but it does **not** preload `InterSystems.Data.Utils.dll`, which holds the PEX base types. Even `InterSystems.EnsLib.PEX.Message` resolves only after that DLL is added. The `+` in the message is just the gateway retrying with nested-type syntax.
   **Fix:** set `%gatewayExtraClasspaths` = `/usr/irissys/dev/dotnet/bin/net8.0/InterSystems.Data.Utils.dll|/home/irisowner/pex/PexDemo.dll`.
3. The default gateway config is `%DotNet Server` `DotNetVersion=N6.0`, even though only net8/9/10 binaries ship. It still works: IRIS starts the `net8.0` `GatewayArm` (tested with both N6.0 and N8.0), so no cpf change is needed.
4. `EnsLib.Testing.Service` needs `TestingEnabled="true"` on the production. Without it you get `ErrBusinessDispatchNameNotRegistered`.
5. If the BO job dies, a synchronous `SendTestRequest` waits forever. Check `Ens_Util.Log` instead of waiting.

## Cost
- Image size: 8,599,619,568 B vs base 5,448,470,224 B. The .NET part is **+78.8 MB** (runtime layer) plus 4.6 kB (DLL). The remaining ~3.07 GB is the `iris start / merge / ImportDir` layer, which every derived IRIS image gets (copy-on-write of the databases); it is not caused by .NET.
- Build time:
  - The first build took 1006 s, almost all of it one-time pulls of `dotnet/sdk:8.0` and `dotnet/runtime:8.0` on a slow link.
  - The .NET build steps themselves take about 2 s (`dotnet build` 1.8 s, runtime COPY 0.1 s).
  - A warm rebuild after a `.cls` change took 50 s, all of it IRIS setup and export.
- Runtime RAM: the container uses about 420 MiB with the production and the gateway running.

---

# Stage 2: NHapi ORU^R01 second-opinion operation (Hl7Check)

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
- `integration/Dockerfile.hl7check.fragment` holds the stages and production items for later integration
  into the main image. It is not applied.
- `docker-compose.yml` mounts `../cases` read-only at `/home/irisowner/fixtures`.

## Run
```
docker compose -p ioa-pex up -d --build
# PEX namespace; the production does not auto-start after a container recreate:
do ##class(Ens.Director).StartProduction("PexDemo.Production")
do ##class(PexHl7.Driver).RunFixture("/home/irisowner/fixtures/C11-critical-k.hl7",30)
```

## Evidence (2026-10-27, 30 msgs per fixture, ~0.3 s per fixture)
| Fixture | IRIS invalid | Findings | Source |
|---|---|---|---|
| C10-mrn-pid2 | 30/30 | `PID3_MISSING` error x30, PID-3 | both (agree) |
| C11-critical-k | 0 | `OBX8_CRITICAL` warning, OBX[3]-8, "K=6.8 mmol/L flagged 'HH'" (MSG015) | dotnet only |
| C09-unknown-code-q77 | 0 | `OBX3_NO_TEXT` info, plus `OBX6_UNITS_MISSING` and `OBX7_RANGE_MISSING` warnings, x30 each, OBX[6] | dotnet only |
| C08-prompt-injection-nte | 0 | `NTE_INSTRUCTION_LIKE` and `OBX7_RANGE_MISSING` warnings x30 | dotnet only |
| C01-new-code-sod (control) | 0 | none | |

Visual Trace session 284 (C11-MSG015) shows this chain: Testing.Service -> Testing.Process -> PexHl7CheckBP
-> **PexHl7Check (EnsLib.PEX.Message)** -> reply -> PexHl7.CheckResponse.

## Cost of the dependencies
- The image layer `/home/irisowner/pex/hl7check` is 4.32 MB. The total image grew 8,599,619,568 -> 8,605,855,825 B (+6.2 MB).
- The `dotnet publish` step, including the NuGet restore, takes 5.9 s. The full warm rebuild takes 47.9 s, most of it the IRIS class-load layer.
- Everything in `%gatewayExtraClasspaths`: InterSystems.Data.Utils.dll (from IRIS), Hl7Check.dll, NHapi.Base.dll,
  NHapi.Model.V251.dll, System.Configuration.ConfigurationManager.dll, System.Diagnostics.EventLog.dll,
  System.Security.Cryptography.ProtectedData.dll.

## Gotchas
- IRIS validation `f` and `t` (code tables) flag every local `L` coding system against table 396, which is noise. That is why `dm-zrny-x` is used:
  it gives required fields, repeats and types, and reports every error. `dm-z` alone does not catch C10.
- `EnsLib.Testing.Service.SendTestRequest` needs an `Ens.Request`, so a wrapper `PexHl7.CheckRequest` carries the HL7 text.
- NHapi pulls in System.Configuration.ConfigurationManager and its dependencies. Use `publish` with `CopyLocalLockFileAssemblies` and list each DLL in the
  classpaths. `runtimes/win` can be dropped.
- After `up` recreates the container, the production is stopped, and the testing service fails with
  `ErrBusinessDispatchNameNotRegistered`.
