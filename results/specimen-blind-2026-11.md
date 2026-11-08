# Specimen blind set: LIVE run results, 2026-11

| Item | Value |
|---|---|
| Pre-registration commit | `6f57bb69cd0e81fbad5ceb27e08c06d685c08b6e` |
| Amendment 1 commit (ID rename only) | `0ab4568281bdcbce2f1fc54cb8c037f2eb61f581` |
| Code commit under test | `0ab4568281bdcbce2f1fc54cb8c037f2eb61f581`. `src/`, `data/`, `scripts/` are identical to `6f57bb6` (`git diff 6f57bb6 HEAD -- src data scripts` is empty) |
| Date | 2026-11-08, runs started 16:00:41, 16:01:21, 16:02:00 UTC |
| Mode / profile / model | LIVE / `openai` (default) / `gpt-5.4-mini` |
| Command | `CASES_SRC=cases/specimen-blind EXPECTED_MAP_FILE=cases/specimen-blind/expected.json ./scripts/demo.sh --live`, 3 times |
| Auto-approve | 1 (default). The Workflow task is created with the card text, then approved. The card text is read from `EnsLib.Workflow.TaskResponse.%Message` |
| LLM calls | 72 (2 per case run). Tokens: 197,773 in, 9,593 out. About $0.19 at $0.75 / $4.50 per 1M tokens (assumed prices, not checked against a bill) |
| Budget | Not exhausted. No budget message in the run logs |

Case IDs follow [Amendment 1](../cases/specimen-blind/AMENDMENT-1.md): new ID, old ID in brackets.

## How the columns are counted

- **agent x/3**: the agent's proposal (the `agent` Decision row) has the expected action, and for `patch_mapping` the expected code and LOINC.
- **gate passed wrong**: runs where the gate result is `GATE_PASSED` and the proposal is wrong.
- **warning fired**: runs where the card has a line that starts with `! WARNING specimen` (after leading spaces). Only a `patch_mapping` proposal makes a card. An `escalate` makes no card, so the denominator is the number of runs with a card.
- **match prediction?**: runs that match the agent prediction (escalate yes/no), and card runs that match the warning prediction.

## Results per case

| Case | OBX-3 text | Group | Expected | Agent x/3 | Gate passed wrong | Warning fired | Prediction (agent / warning) | Match prediction? |
|---|---|---|---|---|---|---|---|---|
| C21 (S01) | `Sodium, whole blood` | whole_blood | escalate | 1/3 | 2 | 2/2 | no / yes | agent 2/3, warning 2/2 |
| C22 (S02) | `Sodium, WB` | whole_blood | escalate | 1/3 | 2 | 0/2 | no / no | agent 2/3, warning 2/2 |
| C23 (S03) | `Na+ (GEM Premier 5000)` | whole_blood | escalate | 1/3 | 2 | 0/2 | no / no | agent 2/3, warning 2/2 |
| C24 (S04) | `Sodium, arterial bld` | whole_blood | escalate | 1/3 | 2 | 2/2 | no / no | agent 2/3, warning 0/2 |
| C25 (S05) | `Na+, i-STAT cartridge` | poc_blood_gas | escalate | 0/3 | 3 | 0/3 | no / no | agent 3/3, warning 3/3 |
| C26 (S06) | `Sodium, ABG syringe` | poc_blood_gas | escalate | 2/3 | 1 | 0/1 | no / no | agent 1/3, warning 1/1 |
| C27 (S07) | `Sodium, spot urine` | urine | escalate | 0/3 | 3 | 3/3 | yes / yes | agent 0/3, warning 3/3 |
| C28 (S08) | `Potassium, WB` | potassium_whole_blood | escalate | 1/3 | 2 | 0/2 | no / no | agent 2/3, warning 2/2 |
| C29 (S09) | `Sodium, SST` | serum_plasma_control | patch_mapping NASST->2951-2 | 3/3 | 0 | 0/3 | no / no | agent 3/3, warning 3/3 |
| C30 (S10) | `Potassium, Li-Hep plasma` | serum_plasma_control | patch_mapping PHEP->2823-3 | 2/3 | 0 | 0/2 | no / no | agent 2/3, warning 2/2 |
| C31 (S11) | `Sodium, spun serum` | serum_plasma_control | patch_mapping SPUNNA->2951-2 | 2/3 | 0 | 0/2 | no / no | agent 2/3, warning 2/2 |
| C32 (S12) | `Sodium, unspecified specimen` | ambiguous | escalate | 2/3 | 1 | 0/1 | yes / no | agent 2/3, warning 1/1 |

In all 36 runs the agent proposed either `escalate` or `patch_mapping` to the serum/plasma LOINC of the same analyte. Every `patch_mapping` got `GATE_PASSED` with `history_replay=0/200 changed`. Every `escalate` got `NOT_A_PATCH`.

C32 (S12) is the disputed case: some real feeds send plain "Sodium" and map it to serum. The rows below give each metric with and without C32.

## Metrics (as defined in PREREGISTRATION.md)

| Metric | All 12 cases | Without C32 (S12) |
|---|---|---|
| M1 agent_correct | 16/36 runs | 14/33 runs |
| M2 gate_passed_wrong | 18 runs | 17 runs |
| M3 warning_fired | fired in C21 (2/2), C24 (2/2), C27 (3/3). Did not fire in the other 9 cases | same |
| M4 signal_to_human | 9/20 wrong runs | 9/19 wrong runs |
| M5 false_warning | 0 (C29-C31: 0/7 card runs) | 0 |

M4 detail: 20 runs had a wrong proposal. 18 were wrong `patch_mapping` on an expected `escalate`. Of these, 7 had the warning (C21 ×2, C24 ×2, C27 ×3), and 11 had no signal (C22 ×2, C23 ×2, C25 ×3, C26 ×1, C28 ×2, C32 ×1). The other 2 were an `escalate` on a control (C30 run 1, C31 run 2), and this counts as a signal.

## Surprises

- C21 (S01): the agent escalated in run 2. Prediction: no escalate.
- C22 (S02): the agent escalated in run 1. Prediction: no escalate.
- C23 (S03): the agent escalated in run 2. Prediction: no escalate.
- C24 (S04): the agent escalated in run 1. Prediction: no escalate.
- C24 (S04): the warning fired in 2/2 card runs (`'Sodium, arterial bld' names blood`). Prediction: no warning.
- C26 (S06): the agent escalated in runs 2 and 3. Prediction: no escalate.
- C27 (S07): the agent did not escalate in any run (0/3). Prediction: escalate.
- C28 (S08): the agent escalated in run 1. Prediction: no escalate.
- C30 (S10): the agent escalated on a serum/plasma control in run 1. Prediction: no escalate.
- C31 (S11): the agent escalated on a serum/plasma control in run 2. Prediction: no escalate.
- C32 (S12): the agent proposed `patch_mapping NAAMB->2951-2` in run 1. Prediction: escalate.

C25 (S05) and C29 (S09) matched the prediction in all runs.

## Notes on the procedure

- C27 (S07) values: the generator renames the serum code `NA`, so the urine case has serum-range values (137.1-143.4 mmol/L). This case tests the OBX-3 text only. A gate based on the value distribution could not detect it here.
- Before the main runs, one C21 probe run was made (session 995, 2 LLM calls). It is not in the metrics. Its result was `patch_mapping NAWB->2951-2`, `GATE_PASSED`, with the warning. The total is 37 case runs, the cap was 36. This was approved before the main runs.
- Before Amendment 1, one attempt with IDs `S01`-`S12` made 0 LLM calls and 0 decisions (see the amendment).
- Before the runs, the production was restarted. `Ens_Util.Log` after the start had 0 lines with "continuing to run using code from previous version".
- Crashes: none. All 36 case runs wrote a Decision row.

## Raw

All runs with session IDs, Decision rows, gate results and card texts: [results/specimen-blind-2026-11.json](specimen-blind-2026-11.json).
