/// Placeholder class so that the empty <code>src/SessionAgent/</code> package directory
/// can be tracked by git AND scanned by IPM without erroring on a stray
/// <code>.gitkeep</code> file. Will be removed in Story 1.3 when
/// <CLASS>SessionAgent.Audit.Emit</CLASS> ships as the first real class in this
/// package.
///
/// IPM's <code>Default.Package</code> resource processor walks the package
/// directory with a <code>*</code> wildcard, so a hidden <code>.gitkeep</code> file
/// would trigger an "Unknown file type" load error. This stub class compiles
/// cleanly, occupies the package, and lets <code>zpm load</code> succeed.
Class SessionAgent.Placeholder [ Hidden ]
{

}
