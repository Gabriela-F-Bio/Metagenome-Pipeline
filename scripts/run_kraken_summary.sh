#!/bin/bash
set -euo pipefail

# ============================================================
# Kraken2 + Bracken summary
#
# Inputs:
#   11kraken2/reports/*.kraken2.report
#   11kraken2/bracken/*.bracken.S.tsv
#
# Outputs:
#   11kraken2/summary/kraken2_classification_summary.tsv
#   11kraken2/summary/bracken_species_counts.tsv
#   11kraken2/summary/bracken_species_relative_abundance.tsv
# ============================================================

CONFIG_FILE="${1:-${CONFIG:-./config.sh}}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: config.sh not found at: $CONFIG_FILE" >&2
    exit 1
fi

source "$CONFIG_FILE"

KRAKEN2_DIR="${KRAKEN2_DIR:-$BASE/11kraken2}"
KRAKEN2_REPORT_DIR="${KRAKEN2_REPORT_DIR:-$KRAKEN2_DIR/reports}"
BRACKEN_DIR="${BRACKEN_DIR:-$KRAKEN2_DIR/bracken}"
KRAKEN2_SUMMARY_DIR="${KRAKEN2_SUMMARY_DIR:-$KRAKEN2_DIR/summary}"

BRACKEN_LEVEL="S"

mkdir -p "$KRAKEN2_SUMMARY_DIR"

CLASSIFICATION_SUMMARY="$KRAKEN2_SUMMARY_DIR/kraken2_classification_summary.tsv"
BRACKEN_COUNTS="$KRAKEN2_SUMMARY_DIR/bracken_species_counts.tsv"
BRACKEN_RELATIVE="$KRAKEN2_SUMMARY_DIR/bracken_species_relative_abundance.tsv"

# ------------------------------------------------------------
# Check required directories
# ------------------------------------------------------------

if [[ ! -d "$KRAKEN2_REPORT_DIR" ]]; then
    echo "ERROR: Kraken2 report directory not found:"
    echo "  $KRAKEN2_REPORT_DIR"
    exit 1
fi

if [[ ! -d "$BRACKEN_DIR" ]]; then
    echo "ERROR: Bracken directory not found:"
    echo "  $BRACKEN_DIR"
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required for Kraken2/Bracken summarization." >&2
    exit 1
fi

shopt -s nullglob
REPORTS=("$KRAKEN2_REPORT_DIR"/*.kraken2.report)
BRACKEN_FILES=("$BRACKEN_DIR"/*.bracken."${BRACKEN_LEVEL}".tsv)
shopt -u nullglob

if [[ ${#REPORTS[@]} -eq 0 ]]; then
    echo "ERROR: No Kraken2 reports found in:"
    echo "  $KRAKEN2_REPORT_DIR"
    exit 1
fi

if [[ ${#BRACKEN_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No Bracken ${BRACKEN_LEVEL}-level files found in:"
    echo "  $BRACKEN_DIR"
    exit 1
fi

echo "=== Kraken2/Bracken summary starting ==="
echo "Kraken2 reports: ${#REPORTS[@]}"
echo "Bracken files:   ${#BRACKEN_FILES[@]}"
echo "Bracken level:   $BRACKEN_LEVEL"
echo

# ------------------------------------------------------------
# 1. Kraken2 classification summary
# ------------------------------------------------------------

echo -e \
"sample\ttotal_reads\tclassified_reads\tclassified_percent\tunclassified_reads\tunclassified_percent\tbracken_species_detected" \
> "$CLASSIFICATION_SUMMARY"

for REPORT in "${REPORTS[@]}"; do

    SAMPLE="$(basename "$REPORT" .kraken2.report)"
    BRACKEN_FILE="$BRACKEN_DIR/${SAMPLE}.bracken.${BRACKEN_LEVEL}.tsv"

    # Kraken2 report:
    # column 2 = reads in clade
    # column 4 = rank
    # column 5 = taxid
    #
    # Root (taxid 1) represents classified reads.
    # U / taxid 0 represents unclassified reads.

    CLASSIFIED="$(
        awk '$4 == "R" && $5 == 1 {print $2; exit}' "$REPORT"
    )"

    UNCLASSIFIED="$(
        awk '$4 == "U" && $5 == 0 {print $2; exit}' "$REPORT"
    )"

    CLASSIFIED="${CLASSIFIED:-0}"
    UNCLASSIFIED="${UNCLASSIFIED:-0}"

    TOTAL=$((CLASSIFIED + UNCLASSIFIED))

    if [[ "$TOTAL" -gt 0 ]]; then
        CLASSIFIED_PERCENT="$(
            awk -v c="$CLASSIFIED" -v t="$TOTAL" \
                'BEGIN {printf "%.2f", (c/t)*100}'
        )"

        UNCLASSIFIED_PERCENT="$(
            awk -v u="$UNCLASSIFIED" -v t="$TOTAL" \
                'BEGIN {printf "%.2f", (u/t)*100}'
        )"
    else
        CLASSIFIED_PERCENT="0.00"
        UNCLASSIFIED_PERCENT="0.00"
    fi

    if [[ -s "$BRACKEN_FILE" ]]; then
        SPECIES_DETECTED=$(
            awk 'NR > 1 {count++} END {print count+0}' "$BRACKEN_FILE"
        )
    else
        SPECIES_DETECTED="NA"
    fi

    echo -e \
"${SAMPLE}\t${TOTAL}\t${CLASSIFIED}\t${CLASSIFIED_PERCENT}\t${UNCLASSIFIED}\t${UNCLASSIFIED_PERCENT}\t${SPECIES_DETECTED}" \
    >> "$CLASSIFICATION_SUMMARY"
done

# Natural sample order (1, 2, ... 10, 11 rather than 1, 10, 11, 2)
{
    head -n 1 "$CLASSIFICATION_SUMMARY"
    tail -n +2 "$CLASSIFICATION_SUMMARY" | sort -V
} > "${CLASSIFICATION_SUMMARY}.tmp"

mv "${CLASSIFICATION_SUMMARY}.tmp" "$CLASSIFICATION_SUMMARY"

# ------------------------------------------------------------
# 2. Combine Bracken outputs into abundance matrices
#
# Bracken columns normally include:
#   name
#   taxonomy_id
#   taxonomy_lvl
#   kraken_assigned_reads
#   added_reads
#   new_est_reads
#   fraction_total_reads
#
# We retain taxonomy_id so species names remain unambiguous.
# ------------------------------------------------------------

python3 - "$BRACKEN_DIR" "$BRACKEN_LEVEL" "$BRACKEN_COUNTS" "$BRACKEN_RELATIVE" <<'PY'
import csv
import glob
import os
import re
import sys

bracken_dir = sys.argv[1]
level = sys.argv[2]
counts_out = sys.argv[3]
relative_out = sys.argv[4]

pattern = os.path.join(
    bracken_dir,
    f"*.bracken.{level}.tsv"
)

files = glob.glob(pattern)

if not files:
    raise SystemExit(
        f"ERROR: No Bracken files matched {pattern}"
    )

def natural_key(text):
    return [
        int(x) if x.isdigit() else x.lower()
        for x in re.split(r"(\d+)", text)
    ]

def sample_from_path(path):
    suffix = f".bracken.{level}.tsv"
    name = os.path.basename(path)

    if not name.endswith(suffix):
        return name

    return name[:-len(suffix)]

files = sorted(
    files,
    key=lambda p: natural_key(sample_from_path(p))
)

samples = [sample_from_path(path) for path in files]

# key = (taxonomy_id, species name)
taxa = {}

for path, sample in zip(files, samples):

    with open(path, newline="") as handle:
        reader = csv.DictReader(
            handle,
            delimiter="\t"
        )

        required = {
            "name",
            "taxonomy_id",
            "new_est_reads",
            "fraction_total_reads"
        }

        if reader.fieldnames is None:
            raise SystemExit(
                f"ERROR: Missing header in {path}"
            )

        missing = required - set(reader.fieldnames)

        if missing:
            raise SystemExit(
                f"ERROR: Missing required Bracken columns "
                f"in {path}: {', '.join(sorted(missing))}"
            )

        for row in reader:

            taxid = row["taxonomy_id"]
            name = row["name"]

            key = (taxid, name)

            if key not in taxa:
                taxa[key] = {
                    "counts": {},
                    "relative": {}
                }

            try:
                count = float(row["new_est_reads"])
            except (TypeError, ValueError):
                count = 0.0

            try:
                relative = float(row["fraction_total_reads"])
            except (TypeError, ValueError):
                relative = 0.0

            taxa[key]["counts"][sample] = count
            taxa[key]["relative"][sample] = relative

sorted_taxa = sorted(
    taxa,
    key=lambda x: (x[1].lower(), x[0])
)

# Estimated Bracken read counts
with open(counts_out, "w", newline="") as handle:
    writer = csv.writer(
        handle,
        delimiter="\t"
    )

    writer.writerow(
        ["taxonomy_id", "species"] + samples
    )

    for taxid, name in sorted_taxa:
        values = []

        for sample in samples:
            value = taxa[(taxid, name)]["counts"].get(
                sample,
                0
            )

            # Bracken estimated reads are effectively counts.
            # Write integers when possible.
            if float(value).is_integer():
                value = int(value)

            values.append(value)

        writer.writerow(
            [taxid, name] + values
        )

# Relative abundance reported by Bracken
with open(relative_out, "w", newline="") as handle:
    writer = csv.writer(
        handle,
        delimiter="\t"
    )

    writer.writerow(
        ["taxonomy_id", "species"] + samples
    )

    for taxid, name in sorted_taxa:
        values = [
            taxa[(taxid, name)]["relative"].get(
                sample,
                0
            )
            for sample in samples
        ]

        writer.writerow(
            [taxid, name] + values
        )

print(
    f"Combined {len(samples)} Bracken samples "
    f"across {len(taxa)} taxa."
)
PY

echo
echo "=== Kraken2/Bracken summary complete ==="
echo
echo "Created:"
echo "  $CLASSIFICATION_SUMMARY"
echo "  $BRACKEN_COUNTS"
echo "  $BRACKEN_RELATIVE"