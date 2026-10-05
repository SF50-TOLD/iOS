# Auto-Fill gate

A NOTAM reader ships only if its Auto-Fill offers clear this gate on one run of
the held-out set.

## What the gate protects

The reader proposes values; the pilot reviews them in the NOTAM editor before
they affect a calculation. Auto-Fill appears on a downloaded NOTAM when that
NOTAM proposes something for the editor's runway direction and operation.
Tapping it writes the values into the editor, scrolls to a “check each value”
banner, and offers Undo.

Review is a backstop, not the primary defence: a pre-filled form invites
anchoring. So the gate bounds tightly the errors that review is least likely
to catch, and treats the rest as usefulness.

- **Hazard:** a value that makes performance look better than the NOTAM
  allows, or a fill that silently leaves out something the NOTAM states.
- **Nuisance:** an error that makes performance look worse. Review catches it,
  and it is safe if missed.
- **No offer:** the pilot enters the NOTAM by hand.

## What gets scored

### The review screen

The unit of review is a screen: one runway direction and one operation. For
each held-out NOTAM, the harness derives the offer for every
(direction, operation) the gold label or the reading names. It follows the
mapper's rules, after the reader's proposable-field filter:

- **Takeoff:** shortening from TORA, else from a partial closure's closed
  length.
- **Landing:** shortening from LDA, else from closed length, else from the
  displacement beyond the published one; contamination from the lowest RwyCC,
  else the worst contaminant category.
- A cancelled NOTAM offers nothing. A closure fills nothing; it is advice.

The shortening's end is not scored: it changes only how the map and the runway
row draw the shortening, not the performance figures.

Obstacles are not scored. Only a formatted report proposes one, for the
takeoff that leaves from the runway end its reference names, when its compass
direction is within one point of that runway's heading; a model reading's
obstacles propose nothing.

### Outcomes

Each screen gets an outcome, and each NOTAM takes the worst of its screens:

- **hazardous**, if any of these holds:
  - an offered value flatters gold's: TORA or LDA higher; closed length or
    displacement lower; contamination less severe (an RwyCC code against a
    contaminant category counts as less severe);
  - the screen offers something but leaves out a value gold has for it;
  - it offers a shortening on a direction gold closes for that operation.
- **cautious:** every difference errs the safe way, including a value gold
  doesn't have.
- **exact:** the offer equals gold's, after unit conversion, within 1 m.
- **manual:** gold has values for the screen; the reading offers none.
- **silent:** neither offers anything.

From worst to best: hazardous, cautious, manual, exact, silent. A NOTAM is
exact only when every screen it names is exact.

A value filed under the wrong runway is therefore cautious: on the right
runway's screen nothing is offered, and on the wrong one the values are
invented, which only shortens the runway. A false offer on an irrelevant NOTAM
is cautious for the same reason. Cancellation needs no gate of its own: a
missed cancellation shows up as an offer gold doesn't support, and an invented
one as a manual miss.

## The gate

A reader passes only if every bar holds on one run of the held-out set:

| Bar | Needs |
| --- | --- |
| Hazardous NOTAMs, of all NOTAMs | one-sided 95% upper bound ≤ 1% |
| Exact | ≥ 50% of NOTAMs for which gold offers something |
| Not cautious | ≥ 90% of NOTAMs for which the reader offers something |
| Stays silent | ≥ 95% of NOTAMs for which gold offers nothing |
| Readable | ≥ 95% of NOTAMs |

The bound is the exact (Clopper–Pearson) binomial one. The hazard bar needs zero
hazards in at least 299 NOTAMs, or one in at least 473. The held-out set over-
samples NOTAMs that state values, so the rate is conservative for real NOTAM
traffic.

### The held-out set

The held-out set holds at least 300 reviewed NOTAMs, weighted toward strata
that state values, none of them in any training set. Each reader is run on the
set once, aggregate only; the Zenodo NOTAMs are reported apart.

### Procedure for a reader

1. On the development set, choose the proposable fields: the largest set with
   no hazards there that meets the usefulness bars.
2. Fix the reader and its fields before the held-out run.
3. Run the held-out gate once, with those fields. Delete the detailed CSV
   unread, and keep the aggregates.
4. If it passes, publish the model with exactly those fields in its manifest.

The parsers are part of every reader, so a parser hazard fails the gate too.
Gated alone, with the model switched off, they establish whether parser-backed
Auto-Fill can ship by itself. In a parsers-only run, a NOTAM only the model
reads offers nothing and counts as a hazard trial, but is left out of
readability and exactness: those bars measure the NOTAMs the parsers
recognize.

## Implementation

### Scoring through the app's mapper

The harness derives offers by calling
`NOTAMProposalMapper.proposal(from:notamID:for:)`, so it scores exactly the
logic the app ships, without airport data.

A shortening worked out from a declared distance depends on the published
length, and one from a displaced threshold on the published displacement; one
from a closed length depends on neither. When gold and reading work a screen's
shortening out from different stated values, which one flatters depends on
the runway. So each screen is scored on four synthetic runways, and takes its
worst outcome:

- **lengths:** the shortest runway every stated length fits on (the longest
  stated length plus 10 m), and a 100 km one;
- **published displacements:** none, and, where the NOTAM states a displacement
  longer than 20 m, one 10 m short of the shortest stated displacement.

Each difference grows steadily with the length or the displacement, so its
worst case lies at one of those corners. Gold and reading using the same kind
of value compare the same on every runway.

On each runway, the reading's value is the first one proposed, which is what
`NOTAMProposal.fill` writes. Gold's value is its most conservative: the
longest shortening, the most severe condition. A NOTAM that states two values
for one field is then scored on whether Auto-Fill would write the one that
governs, whatever order the label lists them in.

### The evaluation target

- **`AutoFillOutcome`** classifies a screen and a NOTAM.
- **`NOTAMEvaluator`** scores per-NOTAM metrics:
  - `hazardFree`, for every NOTAM;
  - `exactFill`, for NOTAMs gold offers something for;
  - `cautionFree`, for NOTAMs the reader offers something for;
  - `staysSilent`, for NOTAMs gold offers nothing for;
  - `readable`, for every NOTAM a run's reader is meant to read.
- **`AutoFillGate`** holds the bars. Per-field recall and safety stay in the
  summary as diagnostics.
- **`FailureRateBound`** computes the one-sided exact upper bound.
- **`NOTAM_PROPOSABLE_FIELDS`** (comma-separated `ProposableField` names,
  default all) limits model readings, overriding the manifest. Parser readings
  keep every field.
- **`NOTAM_READER`** chooses the reader instead of `NOTAM_MODEL_FOLDER`:
  `parsers` runs without the model, so a NOTAM only the model could read
  scores as no offer instead of stopping the run; `system` and `pcc` run a
  stock model on every NOTAM.
- The development test reports the same outcomes per 100 NOTAMs.

## Outside the gate

Auto-Fill replaces the editor's values. A cautious offer from one NOTAM can
lower a larger shortening the pilot entered from another. The app should never
let a fill lower a shortening already entered; that is a change to the app,
not to a reader.
