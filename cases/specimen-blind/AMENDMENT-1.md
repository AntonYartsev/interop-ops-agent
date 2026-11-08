# Amendment 1: rename case IDs (no content change)

- Time: 2026-11-08 16:57 +0100 (15:57 UTC)
- Pre-registration commit: `6f57bb69cd0e81fbad5ceb27e08c06d685c08b6e`
- Code under test: `6f57bb69cd0e81fbad5ceb27e08c06d685c08b6e` (unchanged by this amendment)

## Reason

The code under test accepts only case IDs of the form `C` + 2 digits.
`InteropOps.Util.Ids.CaseIdFromMSH10` matches `(?i)C\d\d([-_.].*)?` and returns `""` for any other ID
([`src/InteropOps/Util/Ids.cls:9`](../../src/InteropOps/Util/Ids.cls)).
The production read the files `S01`-`S12`, but wrote no decision for them.

## State before this amendment

- One LIVE attempt ran (`./scripts/demo.sh --live` with `CASE_GLOB='S??-*.hl7'`).
- It made 0 LLM calls and wrote 0 decisions. All 12 cases were `MISSING`.
- No agent result, gate result or review card for this set was seen.

## Change

Only the ID token changes. OBX-3 text, values, expected actions, targets and predictions are not changed.

Changed: `.hl7` file names, the `Sxx-` prefix of MSH-10 inside each `.hl7` (30 per file),
the keys and the `id` and `file` fields in `expected.json`, the IDs in `PREREGISTRATION.md`.

Not changed: `MANIFEST`. It keeps the pre-registration names and hashes. The reverse check below verifies against it.

| Old | New |
|---|---|
| S01 | C21 |
| S02 | C22 |
| S03 | C23 |
| S04 | C24 |
| S05 | C25 |
| S06 | C26 |
| S07 | C27 |
| S08 | C28 |
| S09 | C29 |
| S10 | C30 |
| S11 | C31 |
| S12 | C32 |

Before the rename, `grep -rE "C(2[1-9]|3[0-2])-" cases/ src/ scripts/ data/` found nothing,
and `git ls-files` had no file named `C21`-`C32`. `Demo/API.cls` selects the "pair" set by directory (`cases/pair/`), not by ID range.

## Check: the rename is mechanical

1. Copy the 12 `.hl7` files, `expected.json` and `PREREGISTRATION.md` to a temp directory.
   In names and contents, replace `\bC(2[1-9]|3[0-2])\b` with `S01`-`S12`.
2. Extract the same 14 files from commit `6f57bb6` with `git show 6f57bb6:<path>`.
3. Run `diff -r <from-commit> <reverse-renamed>`.

Result: exit code 0, diff output empty (0 bytes), 14 files on each side.
`shasum -a 256 -c` against `MANIFEST` from `6f57bb6`: all 13 listed files `OK`.

```
$ diff -r orig rev
$ echo $?
0
```
