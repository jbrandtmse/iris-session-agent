/// <p>Minimal Ensemble rule fixture class used by
/// <CLASS>SessionAgent.Test.GetRuleSourceTest</CLASS>. Provides a
/// <code>RuleDefinition</code> XData block with one rule that exercises
/// the <code>&lt;rule&gt;</code> / <code>&lt;when&gt;</code> /
/// <code>&lt;send&gt;</code> / <code>&lt;return&gt;</code> parse path.
/// Created by Story 13.2 because HSCUSTOM has no native rule classes with
/// RuleDefinition XData.</p>
Class SessionAgent.Test.Fixture.SampleRule Extends Ens.Rule.Definition
{

XData RuleDefinition
{
<ruleDefinition alias="" context="Ens.Rule.ContextBase">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="test-rule-1">
<when condition="1">
<send transform="" target="TestTarget"/>
<return/>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
