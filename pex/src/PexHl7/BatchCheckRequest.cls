/// A whole case batch for the .NET second opinion: one PEX round trip per batch instead of one per message.
Class PexHl7.BatchCheckRequest Extends Ens.Request
{

/// Batch / case id (e.g. C10), echoed back.
Property Fixture As %String(MAXLEN = 200);

/// Raw ER7 messages of the batch (segments separated by CR).
Property Messages As list Of %String(MAXLEN = "");

}
