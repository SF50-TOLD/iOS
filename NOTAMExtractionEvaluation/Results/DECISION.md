# NOTAM extraction gate decisions

Each entry records one run of the `gate: held-out test set` test on the
held-out test half. Only the aggregate goes in the record; nobody reads the
per-NOTAM failures, so the test half stays usable for the next gate.

## 2026-09-25 — Stage A, stock on-device model: does not ship

- **Model:** `SystemLanguageModel(useCase: .general)`, variant “AFM 3 Core
  Advanced” (this Mac), greedy sampling, schema 1.4.0.
- **Data:** the test half, 156 reviewed NOTAMs.
- **Caveat:** iPhones run the smaller “AFM 3 Core”, so these numbers are an
  upper bound for the phone.
- **Summary:** `2026-09-25-AFM-3-Core-Advanced-test-summary.csv`. The detailed
  CSV was deleted unread.

| Gate | Needs | Result |
| --- | --- | --- |
| Readable | ≥ 0.95 | 1.00 |
| Cancellation recall / invented-cancellation safety | ≥ 0.98 | 1.00 / 0.99 |
| Negatives that propose nothing | ≥ 0.95 | **0.07** |

| Field | Recall | Safety | Ships |
| --- | ---: | ---: | --- |
| closure | 0.30 | 0.22 | no |
| closedLength | 0.09 | 0.57 | no |
| closedEnd | 0.00 | 0.03 | no |
| thresholdDisplacement | 0.13 | 0.76 | no |
| TORA | 0.28 | 0.50 | no |
| TODA | 0.31 | 0.50 | no |
| ASDA | 0.28 | 0.52 | no |
| LDA | 0.28 | 0.46 | no |
| rwyCC | 0.00 | 1.00 | no |
| contaminants | 0.00 | 0.01 | no |
| obstacleHeightAGL | 0.08 | 0.07 | no |
| obstacleHeightMSL | 0.00 | 0.12 | no |
| obstaclePosition | 0.00 | 0.00 | no |

**Decision:** no field ships from the stock model. That confirms the
development-half result, and Stage B (deterministic parsers for formatted
reports, plus a custom model for free text) replaces it.
