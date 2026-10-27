/// Vector Search knowledge base (bonus, not wired into the agent): one runbook / past-incident entry.
/// Two vector columns because the embedders have different dimensions: EmbLocal (local hashed embedder,
/// InteropOps.KB.Embedder.Local, 384) and EmbOpenAI (text-embedding-3-small, 1536, empty unless Reembed("openai") ran).
/// Search: InteropOps.KB.Store.Search (SQL VECTOR_COSINE). Data: data/kb_runbook.json (precomputed EmbLocal vectors).
Class InteropOps.KB.Entry Extends %Persistent
{

/// Stable entry id, e.g. kb-glucose-units
Property Slug As %String(MAXLEN = 64) [ Required ];

Property Title As %String(MAXLEN = 200);

Property Body As %String(MAXLEN = 4000);

/// Comma-separated tags
Property Tags As %String(MAXLEN = 400);

/// Model id that produced EmbLocal (e.g. local-hash-384-v1)
Property LocalModel As %String(MAXLEN = 64);

Property EmbLocal As %Library.Vector(DATATYPE = "DOUBLE", LEN = 384);

/// Model id that produced EmbOpenAI (text-embedding-3-small), empty if never embedded
Property OpenAIModel As %String(MAXLEN = 64);

Property EmbOpenAI As %Library.Vector(DATATYPE = "DOUBLE", LEN = 1536);

Index SlugIdx On Slug [ Unique ];

}
