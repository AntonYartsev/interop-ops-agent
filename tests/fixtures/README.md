# Test fixtures

`Agent.json` and `A.json` are read-only copies of `results/Agent.json` and `results/A.json` from the
spike repository `spike-v2-message-path` (the preregistered experiment the 12 cases come from). They are the
spike's recorded run results on the synthetic cases; no real patients. `scripts/test_score.py` reads them by
default, so the test runs without the spike repository.

| File | sha256 |
|---|---|
| `Agent.json` | `82189572ee227fefa48bc9248cbae434170e6664399b0599876a2f5d88c6733d` |
| `A.json` | `94789175f3f82c0495500dfb1c6c7e7374a0d65daafd7bb2c42d8db637e90a68` |

Do not edit them; refresh by copying from the spike and updating the hashes.
