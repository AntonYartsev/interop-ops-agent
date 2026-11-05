# Test fixtures

`Agent.json` and `A.json` are frozen run results on the 12 synthetic cases (no real patients), with known
reference scores (Agent 10/12, A 8/12). Only the fields that `to_row()` in `scripts/test_score.py` reads are kept,
one case per line. `scripts/test_score.py` checks that `scripts/score_demo.py` gives the same scores.

| File | sha256 |
|---|---|
| `Agent.json` | `027871bb00af8bb780b55ea5f33300c1cdec222a48734b255c92d3b8e968b821` |
| `A.json` | `3766e8baa6787ddc33e066facdc2b2616d6c07a289917f5fc797b564054f2460` |

Do not edit them.
