#!/bin/bash
set -euo pipefail

# ============================================================
# Additional Bracken taxonomic-rank analysis
#
# Reuses existing Kraken2 reports without rerunning Kraken2.
#
# Usage through project run.sh:
#
#   ./run.sh bracken_rank P
#
# Supported ranks:
#   D = domain
#   P = phylum
#   C = class
#   O = order
#   F = family
#   G = genus
#
# Species-level Bracken analysis is handled by:
#
#   ./run.sh kraken2
#   ./run.sh kraken_summary
#
# Outputs:
#
#   11kraken2/bracken/*.bracken.<LEVEL>.tsv
#
#   11kraken2/summary/bracken_<rank>_counts.tsv
#   11kraken2/summary/bracken_<rank>_relative_abundance.tsv
#
# This script does NOT modify:
#
#   kraken2_classification_summary.tsv
#   bracken_species_counts.tsv
#   bracken_species_relative_abundance.tsv
# ============================================================


# ------------------------------------------------------------
# A. Inputs
# ------------------------------------------------------------

CONFIG_FILE="${1:-${CONFIG:-./config.sh}}"
REQUESTED_LEVEL="${2:-}"


if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: config.sh not found at:" >&2
    echo "  $CONFIG_FILE" >&2
    exit 1
fi


if [[ -z "$REQUESTED_LEVEL" ]]; then
    echo "ERROR: No Bracken taxonomic rank was supplied." >&2
    echo >&2
    echo "Usage:" >&2
    echo "  ./run.sh bracken_rank {D|P|C|O|F|G}" >&2
    exit 1
fi


# Normalize lowercase input if supplied

REQUESTED_LEVEL="$(
    printf '%s' "$REQUESTED_LEVEL" |
        tr '[:lower:]' '[:upper:]'
)"


# ------------------------------------------------------------
# B. Assign descriptive rank name
# ------------------------------------------------------------

case "$REQUESTED_LEVEL" in
    D)
        BRACKEN_RANK="domain"
        ;;
    P)
        BRACKEN_RANK="phylum"
        ;;
    C)
        BRACKEN_RANK="class"
        ;;
    O)
        BRACKEN_RANK="order"
        ;;
    F)
        BRACKEN_RANK="family"
        ;;
    G)
        BRACKEN_RANK="genus"
        ;;
    S)
        echo "ERROR: Species-level Bracken analysis is already handled by:" >&2
        echo "  ./run.sh kraken2" >&2
        echo "  ./run.sh kraken_summary" >&2
        exit 1
        ;;
    *)
        echo "ERROR: Unsupported Bracken rank: $REQUESTED_LEVEL" >&2
        echo >&2
        echo "Supported additional ranks:" >&2
        echo "  D = domain" >&2
        echo "  P = phylum" >&2
        echo "  C = class" >&2
        echo "  O = order" >&2
        echo "  F = family" >&2
        echo "  G = genus" >&2
        exit 1
        ;;
esac


# ------------------------------------------------------------
# C. Load project configuration
# ------------------------------------------------------------

source "$CONFIG_FILE"


KRAKEN2_DIR="${KRAKEN2_DIR:-$BASE/11kraken2}"

KRAKEN2_REPORT_DIR="$KRAKEN2_DIR/reports"

BRACKEN_DIR="$KRAKEN2_DIR/bracken"

KRAKEN2_SUMMARY_DIR="$KRAKEN2_DIR/summary"

LOG_DIR="${LOG_DIR:-$BASE/logs}"


mkdir -p \
    "$BRACKEN_DIR" \
    "$KRAKEN2_SUMMARY_DIR" \
    "$LOG_DIR"


BRACKEN_READ_LEN="${BRACKEN_READ_LEN:-150}"

LOG_FILE="$LOG_DIR/bracken_${BRACKEN_RANK}_log.txt"


# ------------------------------------------------------------
# D. Check Kraken2 reports
# ------------------------------------------------------------

if [[ ! -d "$KRAKEN2_REPORT_DIR" ]]; then
    echo "ERROR: Kraken2 report directory does not exist:" >&2
    echo "  $KRAKEN2_REPORT_DIR" >&2
    echo >&2
    echo "Run Kraken2 first:" >&2
    echo "  ./run.sh kraken2" >&2
    exit 1
fi


shopt -s nullglob
REPORTS=("$KRAKEN2_REPORT_DIR"/*.kraken2.report)
shopt -u nullglob


if [[ ${#REPORTS[@]} -eq 0 ]]; then
    echo "ERROR: No Kraken2 reports were found in:" >&2
    echo "  $KRAKEN2_REPORT_DIR" >&2
    echo >&2
    echo "Run Kraken2 first:" >&2
    echo "  ./run.sh kraken2" >&2
    exit 1
fi


# ------------------------------------------------------------
# E. Check Kraken2 / Bracken database
# ------------------------------------------------------------

if [[ -z "${KRAKEN2_DB:-}" || ! -d "$KRAKEN2_DB" ]]; then
    echo "ERROR: KRAKEN2_DB does not exist:" >&2
    echo "  ${KRAKEN2_DB:-unset}" >&2
    exit 1
fi


BRACKEN_DISTRIB="$KRAKEN2_DB/database${BRACKEN_READ_LEN}mers.kmer_distrib"


if [[ ! -f "$BRACKEN_DISTRIB" ]]; then
    echo "ERROR: Required Bracken support file was not found:" >&2
    echo "  $BRACKEN_DISTRIB" >&2
    echo >&2
    echo "BRACKEN_READ_LEN must match a support file in the Kraken2 database." >&2
    exit 1
fi


# ------------------------------------------------------------
# F. Kraken2 / Bracken environment
# ------------------------------------------------------------

KRAKEN2_ENV_NAME="${KRAKEN2_ENV_NAME:-kraken2_env}"

KRAKEN2_ENV_PATH="$TOOLS_ROOT/envs/$KRAKEN2_ENV_NAME"


if [[ -z "${MICROMAMBA_BIN:-}" || ! -x "$MICROMAMBA_BIN" ]]; then
    echo "ERROR: MICROMAMBA_BIN is not set or is not executable:" >&2
    echo "  ${MICROMAMBA_BIN:-unset}" >&2
    exit 1
fi


# Prefer shared path-based environment.
# Fall back to the named user environment.

if [[ -d "$KRAKEN2_ENV_PATH" ]]; then

    KRAKEN2_ENV_ARGS=(
        -p
        "$KRAKEN2_ENV_PATH"
    )

    KRAKEN2_ENV_LABEL="$KRAKEN2_ENV_PATH"

else

    KRAKEN2_ENV_ARGS=(
        -n
        "$KRAKEN2_ENV_NAME"
    )

    KRAKEN2_ENV_LABEL="$KRAKEN2_ENV_NAME"

fi


if ! "$MICROMAMBA_BIN" run \
    "${KRAKEN2_ENV_ARGS[@]}" \
    bracken -v \
    >/dev/null 2>&1
then
    echo "ERROR: Bracken is unavailable in the configured environment." >&2
    echo "Environment:" >&2
    echo "  $KRAKEN2_ENV_LABEL" >&2
    exit 1
fi


# ------------------------------------------------------------
# G. Output filenames
# ------------------------------------------------------------

BRACKEN_COUNTS="$KRAKEN2_SUMMARY_DIR/bracken_${BRACKEN_RANK}_counts.tsv"

BRACKEN_RELATIVE="$KRAKEN2_SUMMARY_DIR/bracken_${BRACKEN_RANK}_relative_abundance.tsv"


# ------------------------------------------------------------
# H. Run Bracken at requested taxonomic rank
# ------------------------------------------------------------

: > "$LOG_FILE"


echo "=== Additional Bracken analysis starting ===" |
    tee -a "$LOG_FILE"

echo "Config file:       $CONFIG_FILE" |
    tee -a "$LOG_FILE"

echo "Taxonomic rank:    $BRACKEN_RANK ($REQUESTED_LEVEL)" |
    tee -a "$LOG_FILE"

echo "Kraken2 reports:   ${#REPORTS[@]}" |
    tee -a "$LOG_FILE"

echo "Kraken2 database:  $KRAKEN2_DB" |
    tee -a "$LOG_FILE"

echo "Bracken read len:  $BRACKEN_READ_LEN" |
    tee -a "$LOG_FILE"

echo "Environment:       $KRAKEN2_ENV_LABEL" |
    tee -a "$LOG_FILE"

echo |
    tee -a "$LOG_FILE"


for REPORT in "${REPORTS[@]}"; do

    SAMPLE="$(
        basename \
            "$REPORT" \
            .kraken2.report
    )"

    BRACKEN_OUT="$BRACKEN_DIR/${SAMPLE}.bracken.${REQUESTED_LEVEL}.tsv"


    # Restart-safe:
    # retain an existing non-empty rank-specific Bracken output.

    if [[ -s "$BRACKEN_OUT" ]]; then

        echo "Skipping $SAMPLE: existing output found" |
            tee -a "$LOG_FILE"

        echo "  $BRACKEN_OUT" |
            tee -a "$LOG_FILE"

        continue

    fi


    echo "Processing $SAMPLE..." |
        tee -a "$LOG_FILE"

    echo "  Input:  $REPORT" |
        tee -a "$LOG_FILE"

    echo "  Output: $BRACKEN_OUT" |
        tee -a "$LOG_FILE"


    "$MICROMAMBA_BIN" run \
        "${KRAKEN2_ENV_ARGS[@]}" \
        bracken \
        -d "$KRAKEN2_DB" \
        -i "$REPORT" \
        -o "$BRACKEN_OUT" \
        -r "$BRACKEN_READ_LEN" \
        -l "$REQUESTED_LEVEL" \
        >> "$LOG_FILE" 2>&1


    echo "Finished $SAMPLE" |
        tee -a "$LOG_FILE"

done


# ------------------------------------------------------------
# I. Confirm rank-specific Bracken outputs
# ------------------------------------------------------------

shopt -s nullglob

BRACKEN_FILES=(
    "$BRACKEN_DIR"/*.bracken."${REQUESTED_LEVEL}".tsv
)

shopt -u nullglob


if [[ ${#BRACKEN_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No rank-specific Bracken outputs were created." >&2
    echo "Expected files matching:" >&2
    echo "  $BRACKEN_DIR/*.bracken.${REQUESTED_LEVEL}.tsv" >&2
    exit 1
fi


if [[ ${#BRACKEN_FILES[@]} -ne ${#REPORTS[@]} ]]; then

    echo "WARNING: Number of Bracken files does not match Kraken2 reports." |
        tee -a "$LOG_FILE"

    echo "Kraken2 reports: ${#REPORTS[@]}" |
        tee -a "$LOG_FILE"

    echo "Bracken files:   ${#BRACKEN_FILES[@]}" |
        tee -a "$LOG_FILE"

fi


# ------------------------------------------------------------
# J. Combine Bracken outputs into abundance matrices
# ------------------------------------------------------------

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required for Bracken summarization." >&2
    exit 1
fi


python3 - \
    "$BRACKEN_DIR" \
    "$REQUESTED_LEVEL" \
    "$BRACKEN_RANK" \
    "$BRACKEN_COUNTS" \
    "$BRACKEN_RELATIVE" <<'PY'

import csv
import glob
import os
import re
import sys


bracken_dir = sys.argv[1]
level = sys.argv[2]
rank_name = sys.argv[3]
counts_out = sys.argv[4]
relative_out = sys.argv[5]


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
        for x in re.split(
            r"(\d+)",
            text
        )
    ]


def sample_from_path(path):

    suffix = f".bracken.{level}.tsv"

    name = os.path.basename(path)

    if not name.endswith(suffix):
        return name

    return name[:-len(suffix)]


files = sorted(
    files,
    key=lambda p:
        natural_key(
            sample_from_path(p)
        )
)


samples = [
    sample_from_path(path)
    for path in files
]


# key = (taxonomy_id, taxon name)

taxa = {}


for path, sample in zip(
    files,
    samples
):

    with open(
        path,
        newline=""
    ) as handle:

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


        missing = required - set(
            reader.fieldnames
        )


        if missing:

            raise SystemExit(
                "ERROR: Missing required Bracken "
                f"columns in {path}: "
                f"{', '.join(sorted(missing))}"
            )


        for row in reader:

            taxid = row["taxonomy_id"]
            name = row["name"]

            key = (
                taxid,
                name
            )


            if key not in taxa:

                taxa[key] = {
                    "counts": {},
                    "relative": {}
                }


            try:

                count = float(
                    row["new_est_reads"]
                )

            except (
                TypeError,
                ValueError
            ):

                count = 0.0


            try:

                relative = float(
                    row["fraction_total_reads"]
                )

            except (
                TypeError,
                ValueError
            ):

                relative = 0.0


            taxa[key]["counts"][sample] = count

            taxa[key]["relative"][sample] = relative


sorted_taxa = sorted(
    taxa,
    key=lambda x: (
        x[1].lower(),
        x[0]
    )
)


# ------------------------------------------------------------
# Estimated Bracken read counts
# ------------------------------------------------------------

with open(
    counts_out,
    "w",
    newline=""
) as handle:

    writer = csv.writer(
        handle,
        delimiter="\t"
    )


    writer.writerow(
        [
            "taxonomy_id",
            rank_name
        ] + samples
    )


    for taxid, name in sorted_taxa:

        values = []


        for sample in samples:

            value = taxa[
                (
                    taxid,
                    name
                )
            ]["counts"].get(
                sample,
                0
            )


            if float(value).is_integer():
                value = int(value)


            values.append(
                value
            )


        writer.writerow(
            [
                taxid,
                name
            ] + values
        )


# ------------------------------------------------------------
# Bracken relative abundance
# ------------------------------------------------------------

with open(
    relative_out,
    "w",
    newline=""
) as handle:

    writer = csv.writer(
        handle,
        delimiter="\t"
    )


    writer.writerow(
        [
            "taxonomy_id",
            rank_name
        ] + samples
    )


    for taxid, name in sorted_taxa:

        values = [

            taxa[
                (
                    taxid,
                    name
                )
            ]["relative"].get(
                sample,
                0
            )

            for sample in samples
        ]


        writer.writerow(
            [
                taxid,
                name
            ] + values
        )


print(
    f"Combined {len(samples)} Bracken samples "
    f"across {len(taxa)} {rank_name} taxa."
)

PY


# ------------------------------------------------------------
# K. Finished
# ------------------------------------------------------------

echo |
    tee -a "$LOG_FILE"

echo "=== Additional Bracken analysis complete ===" |
    tee -a "$LOG_FILE"

echo |
    tee -a "$LOG_FILE"

echo "Created:" |
    tee -a "$LOG_FILE"

echo "  $BRACKEN_COUNTS" |
    tee -a "$LOG_FILE"

echo "  $BRACKEN_RELATIVE" |
    tee -a "$LOG_FILE"

echo |
    tee -a "$LOG_FILE"

echo "Per-sample Bracken files:" |
    tee -a "$LOG_FILE"

echo "  $BRACKEN_DIR/*.bracken.${REQUESTED_LEVEL}.tsv" |
    tee -a "$LOG_FILE"