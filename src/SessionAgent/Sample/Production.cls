/// <p>Sample Ensemble production for Story 3.9. Defines the BS / BP / BO
/// items + their dispatch wiring. Operators install + start this
/// production via <class>SessionAgent.Sample.Bootstrap</class>; it is NOT
/// auto-started by the IPM install hook (the package is intended as a
/// test fixture, not runtime).</p>
///
/// <p>Items are configured with <code>Enabled=1</code> + <code>PoolSize=1</code>.
/// The BS is configured but never invoked by an adapter — its
/// <method>RunScenario</method> ClassMethod is the operator entry point.</p>
Class SessionAgent.Sample.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="SessionAgent.Sample.Production" LogGeneralTraceEvents="false">
  <Description>Sample interop production for SessionAgent inspection-agent walkthrough rich-data testing (Story 3.9).</Description>
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="SessionAgent.Sample.BS.OrderIngest" Category="" ClassName="SessionAgent.Sample.BS.OrderIngest" PoolSize="0" Enabled="true" Foreground="false" Comment="Adapterless BS — invoke via RunScenario ClassMethod" LogTraceEvents="true" Schedule=""/>
  <Item Name="SessionAgent.Sample.BP.OrderRouter" Category="" ClassName="SessionAgent.Sample.BP.OrderRouter" PoolSize="1" Enabled="true" Foreground="false" Comment="Routes OrderRequests through validator + persist + publish" LogTraceEvents="true" Schedule=""/>
  <Item Name="SessionAgent.Sample.BP.OrderValidator" Category="" ClassName="SessionAgent.Sample.BP.OrderValidator" PoolSize="1" Enabled="true" Foreground="false" Comment="Validates line items + total amount" LogTraceEvents="true" Schedule=""/>
  <Item Name="SessionAgent.Sample.BO.SqlPersist" Category="" ClassName="SessionAgent.Sample.BO.SqlPersist" PoolSize="1" Enabled="true" Foreground="false" Comment="Persists OrderRequest to SessionAgent.Sample.Persist.OrderRow" LogTraceEvents="true" Schedule=""/>
  <Item Name="SessionAgent.Sample.BO.FilePublish" Category="" ClassName="SessionAgent.Sample.BO.FilePublish" PoolSize="1" Enabled="true" Foreground="false" Comment="Writes stub file to mgr/Temp/" LogTraceEvents="true" Schedule=""/>
</Production>
}

}
