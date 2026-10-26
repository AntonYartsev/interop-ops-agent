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
  <Item Name="IOA.Lookup.Apply" Category="InteropOps" ClassName="InteropOps.Lookup.Apply" PoolSize="1" Enabled="true" Foreground="false" Comment="apply approved patch to IOA.LabCodeMap / unit factor, reprocess the case" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="IOA.Reprocess" Category="InteropOps" ClassName="InteropOps.Lookup.Reprocess" PoolSize="1" Enabled="true" Foreground="false" Comment="leaf: resent messages after an approved patch (DTL + validity, no agent, no Decision)" LogTraceEvents="false" Schedule="">
  </Item>
</Production>
}

}
