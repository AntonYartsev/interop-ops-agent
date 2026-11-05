Class InteropOps.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="InteropOps.Production" LogGeneralTraceEvents="false">
  <Description>Interop Ops Agent: case file -> DTL + rules -> agent -> replay gate -> decision</Description>
  <ActorPoolSize>2</ActorPoolSize>
  <Item Name="IOA.In.CaseFile" Category="InteropOps" ClassName="InteropOps.In.CaseFile" PoolSize="1" Enabled="true" Foreground="false" Comment="cases/in/*.hl7, one file = one case batch" LogTraceEvents="false" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/irisdev/app/cases/in/</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="ArchivePath">/irisdev/app/cases/archive/</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">IOA.Process.Message</Setting>
  </Item>
  <Item Name="IOA.Process.Message" Category="InteropOps" ClassName="InteropOps.Process.Message" PoolSize="1" Enabled="true" Foreground="false" Comment="DTL + triage + rules, agent if unresolved, replay gate, Decision row" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="IOA.Agent" Category="InteropOps" ClassName="InteropOps.Agent.Operation" PoolSize="1" Enabled="true" Foreground="false" Comment="AI Hub agent (MOCK / LIVE / REPLAY)" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="IOA.Agent.Tools" Category="InteropOps" ClassName="InteropOps.Agent.ToolTrace" PoolSize="1" Enabled="true" Foreground="false" Comment="one message per agent tool call (Visual Trace)" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="IOA.Gate.Replay" Category="InteropOps" ClassName="InteropOps.Gate.Replay" PoolSize="1" Enabled="true" Foreground="false" Comment="replay gate over batch + 200 history messages" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="IOA.Workflow" Category="InteropOps" ClassName="InteropOps.Workflow.Operation" PoolSize="1" Enabled="true" Foreground="false" Comment="Inbox task for role IOA-Reviewers (Approve / Reject)" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="IOA.Notify.Reviewer" Category="InteropOps" ClassName="InteropOps.Workflow.Notify" PoolSize="1" Enabled="true" Foreground="false" Comment="custom outbound adapter InteropOps.Adapter.ReviewerNotify: webhook POST per new review task (URL setting or env IOA_NOTIFY_URL)" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="IOA.Lookup.Apply" Category="InteropOps" ClassName="InteropOps.Lookup.Apply" PoolSize="1" Enabled="true" Foreground="false" Comment="apply approved patch to IOA.LabCodeMap / unit factor, reprocess the case" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="IOA.Reprocess" Category="InteropOps" ClassName="InteropOps.Lookup.Reprocess" PoolSize="1" Enabled="true" Foreground="false" Comment="leaf: resent messages after an approved patch (DTL + validity, no agent, no Decision)" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="IOA.Deliver" Category="InteropOps" ClassName="InteropOps.Out.Deliver" PoolSize="1" Enabled="true" Foreground="false" Comment="after the final decision: delivered messages to cases/out/, held messages to cases/held/" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="PexHl7CheckBP" Category="InteropOps,Evidence" ClassName="PexHl7.CheckProcess" PoolSize="1" Enabled="true" Foreground="false" Comment="evidence: IRIS EnsLib.HL7 validation + .NET NHapi second opinion (one PEX call per batch); soft-degrades to IRIS-only" LogTraceEvents="false" Schedule="">
    <Setting Target="Host" Name="TargetConfigName">PexHl7Check</Setting>
    <Setting Target="Host" Name="IrisValSpec">dm-zrny-x</Setting>
    <Setting Target="Host" Name="DotNetTimeout">30</Setting>
  </Item>
  <Item Name="PexHl7Check" Category="InteropOps,Evidence" ClassName="EnsLib.PEX.BusinessOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="PEX .NET: Hl7Check.OruCheckOperation (NHapi v2.5.1)" LogTraceEvents="false" Schedule="">
    <Setting Target="Host" Name="%remoteClassname">Hl7Check.OruCheckOperation</Setting>
    <Setting Target="Host" Name="%gatewayName">%DotNet Server</Setting>
    <Setting Target="Host" Name="%gatewayExtraClasspaths">/usr/irissys/dev/dotnet/bin/net8.0/InterSystems.Data.Utils.dll|/home/irisowner/pex/hl7check/System.Configuration.ConfigurationManager.dll|/home/irisowner/pex/hl7check/System.Diagnostics.EventLog.dll|/home/irisowner/pex/hl7check/System.Security.Cryptography.ProtectedData.dll|/home/irisowner/pex/hl7check/NHapi.Base.dll|/home/irisowner/pex/hl7check/NHapi.Model.V251.dll|/home/irisowner/pex/hl7check/Hl7Check.dll</Setting>
  </Item>
  <Item Name="IOA.Evidence.Ucum" Category="InteropOps,Evidence" ClassName="InteropOps.Evidence.UcumCheck" PoolSize="1" Enabled="true" Foreground="false" Comment="evidence: OBX-6 vs lookup expected unit via InteropOps.Py.Ucum (ParseOBX + Compare)" LogTraceEvents="false" Schedule="">
  </Item>
</Production>
}

}
