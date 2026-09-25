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

## 2026-09-25 — Stage B v4, parsers + fine-tuned model: partial; negatives fail

- **Reader:** deterministic parsers (FICON, RSC, SNOWTAM, FAA OBST), then
  Qwen3-0.6B fine-tuned on 5,392 silver-labelled training NOTAMs (none from
  the gold set), block-wise int8 (605 MB), grammar-constrained, grounded.
- **Tuned on:** the development half only (v1–v4).
- **Data:** the test half, 156 reviewed NOTAMs, run once.
- **Summary:** `2026-09-25-v4-int8b32-test-summary.csv`. The detailed CSV
  was deleted unread.

| Gate | Needs | Result |
| --- | --- | --- |
| Readable | ≥ 0.95 | 0.99 |
| Cancellation recall / invented-cancellation safety | ≥ 0.98 | 1.00 / 1.00 |
| Negatives that propose nothing | ≥ 0.95 | **0.87** |

| Field | Recall | Safety | Ships |
| --- | ---: | ---: | --- |
| closure | 0.91 | 0.85 | no |
| closedLength | 0.82 | 1.00 | yes |
| closedEnd | 0.82 | 1.00 | yes |
| thresholdDisplacement | 0.88 | 0.94 | no |
| TORA | 0.94 | 0.85 | no |
| TODA | 1.00 | 0.84 | no |
| ASDA | 0.94 | 0.85 | no |
| LDA | 0.94 | 0.85 | no |
| rwyCC | 1.00 | 1.00 | yes |
| contaminants | 1.00 | 1.00 | yes |
| obstacleHeightAGL | 0.62 | 0.93 | no |
| obstacleHeightMSL | 0.67 | 0.92 | no |
| obstaclePosition | 0.86 | 1.00 | yes |

**Decision:** pending. The development half overstated the model: every
declared distance cleared the gate there and none does here, and the
negatives gate fails.
