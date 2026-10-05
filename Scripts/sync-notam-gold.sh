#!/usr/bin/env bash
# Copies the reviewed NOTAM gold set from the Model Training repository into the evaluation target,
# refusing a set exported under a schema version the Swift mirror doesn't implement.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
training_root="${MODEL_TRAINING_ROOT:-$repo_root/../Model Training}"
destination="$repo_root/NOTAMExtractionEvaluation/Data"

# The held-out sets are each run once per model, for the gate, so they are only copied in when asked for.
splits=(dev)
for option in "$@"; do
  case "$option" in
    --with-test) splits+=(test) ;;
    --with-holdout) splits+=(holdout) ;;
    *)
      echo "Usage: $(basename "$0") [--with-test] [--with-holdout]" >&2
      exit 2
      ;;
  esac
done

exported_version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["schemaVersion"])' \
  "$training_root/schema/notam_extraction.schema.json")"
mirrored_version="$(sed -n 's/.*static let schemaVersion = "\(.*\)".*/\1/p' \
  "$repo_root/NOTAMModel/Sources/NOTAMModel/Extraction/NOTAMExtraction.swift")"

if [[ "$exported_version" != "$mirrored_version" ]]; then
  echo "Gold set is schema $exported_version; NOTAMExtraction mirrors $mirrored_version. Update the mirror first." >&2
  exit 1
fi

for split in "${splits[@]}"; do
  stale_lines="$(python3 -c 'import json, sys
print(sum(json.loads(line).get("schemaVersion") != sys.argv[2] for line in open(sys.argv[1]) if line.strip()))' \
    "$training_root/eval/notam_$split.meta.jsonl" "$mirrored_version")"
  if [[ "$stale_lines" != "0" ]]; then
    echo "$stale_lines notam_$split labels weren't exported under schema $mirrored_version. Re-export the gold set first." >&2
    exit 1
  fi
done

# A NOTAM that is also a SCHEMA.md worked example is already in the smoke set, which the instructions
# are written against, so it is left out of every split to keep its scores honest.
for split in "${splits[@]}"; do
  python3 -c 'import json, sys
source, destination = sys.argv[1], sys.argv[2]
samples = open(f"{source}.jsonl").read().splitlines()
metadata = open(f"{source}.meta.jsonl").read().splitlines()
assert len(samples) == len(metadata), "samples and metadata differ in length"
kept = [(sample, meta) for sample, meta in zip(samples, metadata) if not json.loads(meta).get("workedExample")]
with open(f"{destination}.jsonl", "w") as out: out.writelines(sample + "\n" for sample, _ in kept)
with open(f"{destination}.meta.jsonl", "w") as out: out.writelines(meta + "\n" for _, meta in kept)' \
    "$training_root/eval/notam_$split" "$destination/notam_$split"
done
echo "Synced gold set (schema $exported_version): ${splits[*]}; $(wc -l < "$destination/notam_dev.jsonl") dev NOTAMs."
