# Test fixtures

`Agent.json` and `A.json` are trimmed copies of `results/Agent.json` and `results/A.json` from the
spike repository `spike-v2-message-path` (the preregistered experiment the 12 cases come from). They are the
spike's recorded run results on the synthetic cases; no real patients. Only the fields that `to_row()` in
`scripts/test_score.py` reads are kept, one case per line. `scripts/test_score.py` reads them by
default, so the test runs without the spike repository.

| File | sha256 |
|---|---|
| `Agent.json` | `027871bb00af8bb780b55ea5f33300c1cdec222a48734b255c92d3b8e968b821` |
| `A.json` | `3766e8baa6787ddc33e066facdc2b2616d6c07a289917f5fc797b564054f2460` |

Do not edit them; refresh by copying from the spike, trimming to the same fields and updating the hashes.
